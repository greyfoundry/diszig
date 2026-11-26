//! Discord Gateway transport compression.
//!
//! `zlib-stream` uses one shared zlib context for the lifetime of a single
//! Gateway connection. Each gateway payload is terminated by the four-byte
//! `Z_SYNC_FLUSH` marker `00 00 ff ff`, and the next payload continues the same
//! stream, so back-references may reach into earlier payloads. Zig's
//! `std.compress.flate.Decompress` cannot be paused between input chunks, so
//! this module binds zlib's incremental inflate interface (`zlib.zig`).
//!
//! The decoder owns one output buffer. `message()` borrows from it and stays
//! valid until the next `feed`, `reset` or `deinit`.

const std = @import("std");
const z = @import("zlib.zig");

pub const sync_flush_suffix = [4]u8{ 0x00, 0x00, 0xff, 0xff };

pub const Mode = enum {
    none,
    zlib_stream,
    /// Documented transport compression that this phase does not implement.
    zstd_stream,

    /// Value for the Gateway `compress` query parameter, or null to omit it.
    pub fn queryValue(self: Mode) ?[]const u8 {
        return switch (self) {
            .none => null,
            .zlib_stream => "zlib-stream",
            .zstd_stream => "zstd-stream",
        };
    }
};

pub const Error = error{
    InvalidConfiguration,
    UnsupportedCompression,
    CompressionInitFailed,
    MessageTooLarge,
    InvalidCompressedData,
    UnexpectedStreamEnd,
    OutOfMemory,
};

/// Incremental `zlib-stream` inflater for one Gateway connection.
///
/// A decoder is single-threaded. Callers must serialise `feed`; the Gateway
/// session owns exactly one reader task per connection.
pub const Inflater = struct {
    const scratch_bytes = 8 * 1024;

    allocator: std.mem.Allocator,
    stream: z.z_stream,
    initialized: bool,
    failed: bool,
    complete: bool,
    max_message_bytes: usize,
    out: std.ArrayList(u8),
    scratch: [scratch_bytes]u8,
    last4: [4]u8,
    have: u8,
    compressed_len: usize,

    /// `max_message_bytes` bounds both the decompressed payload and the
    /// compressed bytes accumulated between two `Z_SYNC_FLUSH` markers. It is
    /// an expansion-bomb guard, not the Gateway's documented payload limit.
    ///
    /// zlib keeps a back-pointer to `stream`, so the `Inflater` must not be
    /// moved or copied after `init`. Allocate it stably (as `Connection` does).
    pub fn init(self: *Inflater, allocator: std.mem.Allocator, max_message_bytes: usize) Error!void {
        if (max_message_bytes == 0) return error.InvalidConfiguration;
        self.* = .{
            .allocator = allocator,
            .stream = std.mem.zeroes(z.z_stream),
            .initialized = false,
            .failed = false,
            .complete = false,
            .max_message_bytes = max_message_bytes,
            .out = .empty,
            .scratch = undefined,
            .last4 = .{ 0, 0, 0, 0 },
            .have = 0,
            .compressed_len = 0,
        };
        errdefer self.out.deinit(self.allocator);
        if (z.inflateInit2(&self.stream, z.MAX_WBITS) != z.Z_OK) return error.CompressionInitFailed;
        self.initialized = true;
    }

    pub fn deinit(self: *Inflater) void {
        if (self.initialized) _ = z.inflateEnd(&self.stream);
        self.out.deinit(self.allocator);
        self.* = undefined;
    }

    /// Starts a fresh zlib context. A new Gateway connection must call this (or
    /// `init`) rather than reusing a previous connection's history window.
    pub fn reset(self: *Inflater) Error!void {
        if (!self.initialized) return error.CompressionInitFailed;
        if (z.inflateReset(&self.stream) != z.Z_OK) return error.CompressionInitFailed;
        self.out.clearRetainingCapacity();
        self.failed = false;
        self.complete = false;
        self.last4 = .{ 0, 0, 0, 0 };
        self.have = 0;
        self.compressed_len = 0;
    }

    /// Feeds the bytes of one WebSocket message. Returns true when those bytes
    /// closed a gateway payload (`Z_SYNC_FLUSH` seen at a message boundary), in
    /// which case `message()` is complete.
    ///
    /// A payload boundary is recognised only at the end of a `chunk`, matching
    /// Discord's documented "check the last four bytes of the received
    /// message" rule. A caller must not merge two gateway payloads into one
    /// chunk; the WebSocket transport passes one message at a time.
    pub fn feed(self: *Inflater, chunk: []const u8) Error!bool {
        if (self.failed) return error.InvalidCompressedData;
        if (self.complete) {
            // The previous payload was consumed; start the next one.
            self.out.clearRetainingCapacity();
            self.compressed_len = 0;
            self.complete = false;
        }
        if (chunk.len == 0) return false;
        if (chunk.len > std.math.maxInt(z.uInt)) return self.poison(error.MessageTooLarge);

        self.compressed_len = std.math.add(usize, self.compressed_len, chunk.len) catch
            return self.poison(error.MessageTooLarge);
        if (self.compressed_len > self.max_message_bytes) return self.poison(error.MessageTooLarge);

        self.trackSuffix(chunk);

        self.stream.next_in = @constCast(chunk.ptr);
        self.stream.avail_in = @intCast(chunk.len);
        while (true) {
            self.stream.next_out = &self.scratch;
            self.stream.avail_out = self.scratch.len;
            const rc = z.inflate(&self.stream, z.Z_SYNC_FLUSH);
            const produced = self.scratch.len - self.stream.avail_out;
            if (produced > 0) try self.append(self.scratch[0..produced]);
            switch (rc) {
                z.Z_OK => {
                    if (self.stream.avail_in == 0 and self.stream.avail_out != 0) break;
                },
                // No progress possible: the payload continues in a later
                // WebSocket message.
                z.Z_BUF_ERROR => break,
                z.Z_STREAM_END => return self.poison(error.UnexpectedStreamEnd),
                else => return self.poison(error.InvalidCompressedData),
            }
        }

        if (self.suffixAtEnd()) {
            self.complete = true;
            return true;
        }
        return false;
    }

    /// The most recently completed payload. Borrowed until the next `feed`.
    pub fn message(self: *const Inflater) []const u8 {
        return self.out.items;
    }

    fn append(self: *Inflater, bytes: []const u8) Error!void {
        const total = std.math.add(usize, self.out.items.len, bytes.len) catch
            return self.poison(error.MessageTooLarge);
        if (total > self.max_message_bytes) return self.poison(error.MessageTooLarge);
        self.out.appendSlice(self.allocator, bytes) catch return error.OutOfMemory;
    }

    fn trackSuffix(self: *Inflater, chunk: []const u8) void {
        var window = self.last4;
        var have = self.have;
        for (chunk) |byte| {
            window[0] = window[1];
            window[1] = window[2];
            window[2] = window[3];
            window[3] = byte;
            if (have < 4) have += 1;
        }
        self.last4 = window;
        self.have = have;
    }

    fn suffixAtEnd(self: *const Inflater) bool {
        return self.have == 4 and std.mem.eql(u8, &self.last4, &sync_flush_suffix);
    }

    fn poison(self: *Inflater, err: Error) Error {
        self.failed = true;
        return err;
    }
};

test "mode maps to the documented query parameter" {
    try std.testing.expectEqual(@as(?[]const u8, null), Mode.none.queryValue());
    try std.testing.expectEqualStrings("zlib-stream", Mode.zlib_stream.queryValue().?);
    try std.testing.expectEqualStrings("zstd-stream", Mode.zstd_stream.queryValue().?);
}

test "zero message bound is rejected before initialising zlib" {
    var inflater: Inflater = undefined;
    try std.testing.expectError(error.InvalidConfiguration, inflater.init(std.testing.allocator, 0));
}

test "reset clears boundary state" {
    var inflater: Inflater = undefined;
    try inflater.init(std.testing.allocator, 1024);
    defer inflater.deinit();
    try std.testing.expect(!inflater.complete);
    try inflater.reset();
    try std.testing.expect(!inflater.failed);
    try std.testing.expectEqual(@as(usize, 0), inflater.message().len);
}

const std = @import("std");

const c = @import("zlib.zig");

const Allocator = std.mem.Allocator;

pub const Error = error{
    CompressionInitFailed,
    CompressionFailed,
    CompressionResetFailed,
    DecompressionInitFailed,
    DecompressionFailed,
    DecompressionResetFailed,
    InvalidCompressionTail,
    MessageTooLarge,
};

pub const Compressor = struct {
    stream: c.z_stream,

    pub fn init(self: *Compressor, _: Allocator) Error!void {
        self.stream = std.mem.zeroes(c.z_stream);
        if (c.deflateInit2(
            &self.stream,
            c.Z_DEFAULT_COMPRESSION,
            c.Z_DEFLATED,
            -c.MAX_WBITS,
            8,
            c.Z_DEFAULT_STRATEGY,
        ) != c.Z_OK) return error.CompressionInitFailed;
    }

    pub fn deinit(self: *Compressor) void {
        _ = c.deflateEnd(&self.stream);
    }

    pub fn reset(self: *Compressor) Error!void {
        if (c.deflateReset(&self.stream) != c.Z_OK)
            return error.CompressionResetFailed;
    }

    /// zlib writes into the caller's buffer, which the caller frees
    pub fn releaseOutput(_: *Compressor) void {}

    pub fn compress(
        self: *Compressor,
        allocator: Allocator,
        input: []const u8,
        output: *std.ArrayList(u8),
    ) (Allocator.Error || Error)![]const u8 {
        output.clearRetainingCapacity();
        var input_offset: usize = 0;
        while (true) {
            if (self.stream.avail_in == 0 and input_offset < input.len) {
                const n = @min(input.len - input_offset, std.math.maxInt(c.uInt));
                self.stream.next_in = @constCast(input[input_offset..].ptr);
                self.stream.avail_in = @intCast(n);
                input_offset += n;
            }

            try output.ensureUnusedCapacity(allocator, 16 * 1024);
            const writable = output.unusedCapacitySlice();
            const capacity = @min(writable.len, std.math.maxInt(c.uInt));
            self.stream.next_out = writable.ptr;
            self.stream.avail_out = @intCast(capacity);
            const flush: c_int = if (input_offset == input.len) c.Z_SYNC_FLUSH else c.Z_NO_FLUSH;
            const result = c.deflate(&self.stream, flush);
            if (result != c.Z_OK) return error.CompressionFailed;
            const written = capacity - self.stream.avail_out;
            output.items.len += written;

            if (flush == c.Z_SYNC_FLUSH and self.stream.avail_in == 0 and self.stream.avail_out != 0)
                break;
        }

        const tail = "\x00\x00\xff\xff";
        if (output.items.len < tail.len or
            !std.mem.eql(u8, output.items[output.items.len - tail.len ..], tail))
            return error.InvalidCompressionTail;
        output.items.len -= tail.len;
        return output.items;
    }
};

pub const Decompressor = struct {
    stream: c.z_stream,

    pub fn init(self: *Decompressor, _: Allocator) Error!void {
        self.stream = std.mem.zeroes(c.z_stream);
        if (c.inflateInit2(&self.stream, -c.MAX_WBITS) != c.Z_OK)
            return error.DecompressionInitFailed;
    }

    pub fn deinit(self: *Decompressor) void {
        _ = c.inflateEnd(&self.stream);
    }

    pub fn reset(self: *Decompressor) Error!void {
        if (c.inflateReset(&self.stream) != c.Z_OK)
            return error.DecompressionResetFailed;
    }

    /// decompress one message's payload (RFC 7692: the sync-flush tail
    /// stripped) into `output`, writing at most `max_len` bytes
    pub fn decompress(self: *Decompressor, payload: []const u8, output: *std.Io.Writer, max_len: usize) Error!usize {
        var produced: usize = 0;
        var chunk: [16 * 1024]u8 = undefined;
        // restore the tail the sender stripped. it is intentionally not a
        // final block: message framing, not BFINAL, ends the payload.
        for ([_][]const u8{ payload, "\x00\x00\xff\xff" }) |input| {
            var input_offset: usize = 0;
            while (true) {
                if (self.stream.avail_in == 0 and input_offset < input.len) {
                    const n = @min(input.len - input_offset, std.math.maxInt(c.uInt));
                    self.stream.next_in = @constCast(input[input_offset..].ptr);
                    self.stream.avail_in = @intCast(n);
                    input_offset += n;
                }
                self.stream.next_out = &chunk;
                self.stream.avail_out = chunk.len;
                const result = c.inflate(&self.stream, c.Z_SYNC_FLUSH);
                if (result != c.Z_OK and result != c.Z_BUF_ERROR)
                    return error.DecompressionFailed;
                const written = chunk.len - self.stream.avail_out;
                if (produced + written > max_len) return error.MessageTooLarge;
                output.writeAll(chunk[0..written]) catch return error.DecompressionFailed;
                produced += written;

                if (input_offset == input.len and self.stream.avail_in == 0 and self.stream.avail_out != 0)
                    break;
                if (written == 0 and self.stream.avail_in == 0 and input_offset == input.len)
                    return error.DecompressionFailed;
            }
        }
        return produced;
    }
};

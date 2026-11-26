//! Gateway framing contracts: the zlib-stream payload boundary, chunked and
//! fragmented input, expansion bounds and explicit transport configuration.
//!
//! The compressed fixtures were produced with Python's zlib implementation
//! using one compressor object and `Z_SYNC_FLUSH` per payload, matching the
//! documented Gateway `zlib-stream` shape (a single stream per connection).

const std = @import("std");
const diszig = @import("diszig");
const gateway = diszig.gateway;

/// `{"op":10,"d":{"heartbeat_interval":41250}}`
const msg_a = "{\"op\":10,\"d\":{\"heartbeat_interval\":41250}}";
/// `{"op":0,"t":"READY","s":1,"d":{"user":{"id":"1"}}}`
const msg_b = "{\"op\":0,\"t\":\"READY\",\"s\":1,\"d\":{\"user\":{\"id\":\"1\"}}}";

/// Two sync-flushed payloads sharing one zlib context.
const stream_hex = "789caa56ca2f50b23234d0514a51b2aa56ca484d2c2a494a4d2c89cfcc2b492d2a4bcc51b23231343235a8ad05000000ffff" ++
    "aa06ab34d0512a51b2520a7275748954d2512a56b232846a2d2d4e2d02d199294a564a864ab5b5b500000000ffff";

/// 64 KiB of `A` compressed to 86 bytes: expands past a 1 KiB bound.
const bomb_hex = "78daecc181000000008020b6fda516a90a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000006a000000ffff";

/// A valid zlib header whose final marker was corrupted.
const corrupt_hex = "789caa56ca2f50b232d4514a51b23231aa05000000ff00";

fn hexDigit(comptime c: u8) u8 {
    return switch (c) {
        '0'...'9' => c - '0',
        'a'...'f' => c - 'a' + 10,
        else => @compileError("invalid fixture hex"),
    };
}

fn decode(comptime hex: []const u8) [hex.len / 2]u8 {
    var out: [hex.len / 2]u8 = undefined;
    inline for (0..hex.len / 2) |i| {
        out[i] = (hexDigit(hex[i * 2]) << 4) | hexDigit(hex[i * 2 + 1]);
    }
    return out;
}

fn newInflater(bound: usize) !*gateway.Inflater {
    const inf = try std.testing.allocator.create(gateway.Inflater);
    inf.init(std.testing.allocator, bound) catch |err| {
        std.testing.allocator.destroy(inf);
        return err;
    };
    return inf;
}

fn freeInflater(inf: *gateway.Inflater) void {
    inf.deinit();
    std.testing.allocator.destroy(inf);
}

fn boundary(stream: []const u8) usize {
    var i: usize = 0;
    while (i + gateway.compression.sync_flush_suffix.len <= stream.len) : (i += 1) {
        if (std.mem.eql(
            u8,
            stream[i..][0..gateway.compression.sync_flush_suffix.len],
            &gateway.compression.sync_flush_suffix,
        )) return i + gateway.compression.sync_flush_suffix.len;
    }
    return stream.len;
}

fn freeMessages(allocator: std.mem.Allocator, messages: [][]u8) void {
    for (messages) |message| allocator.free(message);
    allocator.free(messages);
}

fn collect(inf: *gateway.Inflater, chunks: []const []const u8) ![][]u8 {
    const allocator = std.testing.allocator;
    var list: std.ArrayList([]u8) = .empty;
    errdefer {
        for (list.items) |item| allocator.free(item);
        list.deinit(allocator);
    }
    for (chunks) |chunk| {
        if (try inf.feed(chunk)) {
            try list.append(allocator, try allocator.dupe(u8, inf.message()));
        }
    }
    return list.toOwnedSlice(allocator);
}

test "two payloads in one stream dispatch as two messages" {
    const stream = decode(stream_hex);
    const end = boundary(&stream);
    const first: []const u8 = stream[0..end];
    const second: []const u8 = stream[end..];

    const inf = try newInflater(4096);
    defer freeInflater(inf);

    const messages = try collect(inf, &.{ first, second });
    defer freeMessages(std.testing.allocator, messages);

    try std.testing.expectEqual(@as(usize, 2), messages.len);
    try std.testing.expectEqualStrings(msg_a, messages[0]);
    try std.testing.expectEqualStrings(msg_b, messages[1]);
}

test "one-byte fragments reconstruct both payloads" {
    const stream = decode(stream_hex);
    const inf = try newInflater(4096);
    defer freeInflater(inf);

    var chunks: std.ArrayList([]const u8) = .empty;
    defer chunks.deinit(std.testing.allocator);
    for (stream, 0..) |_, i| try chunks.append(std.testing.allocator, stream[i .. i + 1]);

    const messages = try collect(inf, chunks.items);
    defer freeMessages(std.testing.allocator, messages);

    try std.testing.expectEqual(@as(usize, 2), messages.len);
    try std.testing.expectEqualStrings(msg_a, messages[0]);
    try std.testing.expectEqualStrings(msg_b, messages[1]);
}

test "the first payload reconstructs across every internal split" {
    const stream = decode(stream_hex);
    const end = boundary(&stream);
    var split: usize = 1;
    while (split < end) : (split += 1) {
        const inf = try newInflater(4096);
        defer freeInflater(inf);
        const messages = try collect(inf, &.{ stream[0..split], stream[split..end] });
        defer freeMessages(std.testing.allocator, messages);

        try std.testing.expectEqual(@as(usize, 1), messages.len);
        try std.testing.expectEqualStrings(msg_a, messages[0]);
    }
}

test "a payload split across messages is not dispatched early" {
    const stream = decode(stream_hex);
    const inf = try newInflater(4096);
    defer freeInflater(inf);

    var dispatched: usize = 0;
    const end = boundary(&stream);
    var i: usize = 0;
    while (i + 1 < end) : (i += 1) {
        if (try inf.feed(stream[i .. i + 1])) dispatched += 1;
    }
    try std.testing.expectEqual(@as(usize, 0), dispatched);
    try std.testing.expect(try inf.feed(stream[end - 1 .. end]));
    try std.testing.expectEqualStrings(msg_a, inf.message());
}

test "expansion bomb is bounded" {
    const bomb = decode(bomb_hex);
    const inf = try newInflater(1024);
    defer freeInflater(inf);

    try std.testing.expectError(error.MessageTooLarge, inf.feed(&bomb));
    // A failed decoder must stay failed; the session closes the connection.
    try std.testing.expectError(error.InvalidCompressedData, inf.feed(&bomb));
}

test "corrupt compressed data fails explicitly" {
    const corrupt = decode(corrupt_hex);
    const inf = try newInflater(4096);
    defer freeInflater(inf);

    const result = inf.feed(&corrupt);
    try std.testing.expectError(error.InvalidCompressedData, result);
}

test "reset starts a fresh connection context" {
    const stream = decode(stream_hex);
    const first: []const u8 = stream[0..boundary(&stream)];
    const inf = try newInflater(4096);
    defer freeInflater(inf);

    _ = try inf.feed(first[0..10]);
    try inf.reset();

    const messages = try collect(inf, &.{first});
    defer freeMessages(std.testing.allocator, messages);
    try std.testing.expectEqual(@as(usize, 1), messages.len);
    try std.testing.expectEqualStrings(msg_a, messages[0]);
}

test "zstd transport compression is explicitly unsupported" {
    const url = try gateway.Url.parse("ws://127.0.0.1:9999/");
    try std.testing.expectError(
        error.UnsupportedCompression,
        gateway.Connection.connect(std.testing.allocator, std.testing.io, .{
            .url = url,
            .compression = .zstd_stream,
        }),
    );
}

test "invalid bounds are rejected before any socket work" {
    const url = try gateway.Url.parse("ws://127.0.0.1:9999/");
    try std.testing.expectError(
        error.InvalidConfiguration,
        gateway.Connection.connect(std.testing.allocator, std.testing.io, .{
            .url = url,
            .max_message_bytes = 0,
        }),
    );
    try std.testing.expectError(
        error.InvalidConfiguration,
        gateway.Connection.connect(std.testing.allocator, std.testing.io, .{
            .url = url,
            .read_buffer_bytes = 0,
        }),
    );
    // The WebSocket reader has a static buffer; a buffer larger than the
    // message bound would let over-sized messages through.
    try std.testing.expectError(
        error.InvalidConfiguration,
        gateway.Connection.connect(std.testing.allocator, std.testing.io, .{
            .url = url,
            .max_message_bytes = 4096,
            .read_buffer_bytes = 8192,
        }),
    );
}

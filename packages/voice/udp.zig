//! Discord voice UDP IP discovery framing.
//!
//! Request: `type=1, length=70, ssrc, 64-byte zero address, port=0`.
//! Response: `type=2, length=70, ssrc, 64-byte NUL-terminated address, port`.
//! The length excludes the type and length fields themselves.

const std = @import("std");

pub const Error = error{
    TruncatedPacket,
    UnexpectedType,
    UnexpectedLength,
    SsrcMismatch,
    MissingAddressTerminator,
    InvalidAddress,
    InvalidPort,
    BufferTooSmall,
};

pub const request_type: u16 = 0x1;
pub const response_type: u16 = 0x2;
pub const discovery_length: u16 = 70;
pub const packet_len: usize = 74;
const address_len: usize = 64;

pub const Discovery = struct {
    ssrc: u32,
    /// Borrowed slice into the packet, NUL terminator excluded.
    address: []const u8,
    port: u16,
};

pub fn writeRequest(out: []u8, ssrc: u32) Error![]const u8 {
    if (out.len < packet_len) return error.BufferTooSmall;
    std.mem.writeInt(u16, out[0..2], request_type, .big);
    std.mem.writeInt(u16, out[2..4], discovery_length, .big);
    std.mem.writeInt(u32, out[4..8], ssrc, .big);
    @memset(out[8 .. 8 + address_len], 0);
    std.mem.writeInt(u16, out[8 + address_len ..][0..2], 0, .big);
    return out[0..packet_len];
}

/// Parses a discovery response and enforces the SSRC binding; an answer for a
/// different session is rejected rather than accepted as our address.
pub fn parseResponse(packet: []const u8, expected_ssrc: u32) Error!Discovery {
    if (packet.len < packet_len) return error.TruncatedPacket;
    if (std.mem.readInt(u16, packet[0..2], .big) != response_type) return error.UnexpectedType;
    if (std.mem.readInt(u16, packet[2..4], .big) != discovery_length) return error.UnexpectedLength;
    if (std.mem.readInt(u32, packet[4..8], .big) != expected_ssrc) return error.SsrcMismatch;

    const raw = packet[8 .. 8 + address_len];
    const terminator = std.mem.indexOfScalar(u8, raw, 0) orelse return error.MissingAddressTerminator;
    const address = raw[0..terminator];
    if (address.len == 0) return error.InvalidAddress;
    for (address) |c| {
        if (c < 0x21 or c == 0x7f) return error.InvalidAddress;
    }

    const port = std.mem.readInt(u16, packet[8 + address_len ..][0..2], .big);
    if (port == 0) return error.InvalidPort;
    return .{ .ssrc = expected_ssrc, .address = address, .port = port };
}

test "discovery request and response round-trip" {
    var request: [packet_len]u8 = undefined;
    const built = try writeRequest(&request, 123);
    try std.testing.expectEqual(@as(usize, packet_len), built.len);
    try std.testing.expectEqual(@as(u16, 1), std.mem.readInt(u16, built[0..2], .big));
    try std.testing.expectEqual(@as(u16, 70), std.mem.readInt(u16, built[2..4], .big));

    var response: [packet_len]u8 = @splat(0);
    std.mem.writeInt(u16, response[0..2], 2, .big);
    std.mem.writeInt(u16, response[2..4], 70, .big);
    std.mem.writeInt(u32, response[4..8], 123, .big);
    const address = "203.0.113.7";
    @memcpy(response[8 .. 8 + address.len], address);
    std.mem.writeInt(u16, response[8 + address_len ..][0..2], 50000, .big);

    const discovery = try parseResponse(&response, 123);
    try std.testing.expectEqualStrings(address, discovery.address);
    try std.testing.expectEqual(@as(u16, 50000), discovery.port);
}

test "discovery rejects truncation, wrong type, wrong ssrc and bad address" {
    var response: [packet_len]u8 = @splat(0);
    std.mem.writeInt(u16, response[0..2], 2, .big);
    std.mem.writeInt(u16, response[2..4], 70, .big);
    std.mem.writeInt(u32, response[4..8], 1, .big);
    @memcpy(response[8..15], "1.2.3.4");
    std.mem.writeInt(u16, response[8 + address_len ..][0..2], 1234, .big);

    try std.testing.expectError(error.TruncatedPacket, parseResponse(response[0 .. packet_len - 1], 1));
    try std.testing.expectError(error.SsrcMismatch, parseResponse(&response, 2));

    var wrong_type = response;
    std.mem.writeInt(u16, wrong_type[0..2], 1, .big);
    try std.testing.expectError(error.UnexpectedType, parseResponse(&wrong_type, 1));

    var bad_address = response;
    @memset(bad_address[8 .. 8 + address_len], 0xff);
    try std.testing.expectError(error.MissingAddressTerminator, parseResponse(&bad_address, 1));

    var empty_address = response;
    @memset(empty_address[8 .. 8 + address_len], 0);
    try std.testing.expectError(error.InvalidAddress, parseResponse(&empty_address, 1));

    var zero_port = response;
    std.mem.writeInt(u16, zero_port[8 + address_len ..][0..2], 0, .big);
    try std.testing.expectError(error.InvalidPort, parseResponse(&zero_port, 1));
}

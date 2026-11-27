//! RTP media path glue for encoded Opus frames.
//!
//! Send order: Opus frame (already DAVE-encrypted when a session is active) ->
//! RTP header -> rtpsize AEAD. Receive reverses it. The caller owns sockets,
//! the codec and the optional DAVE encryptor/decryptor.

const std = @import("std");
const audio = @import("audio.zig");
const gateway = @import("gateway.zig");
const rtp = @import("rtp.zig");

pub const Error = rtp.Error;

/// Send-side RTP state. Sequence and timestamp progress with unsigned wrapping;
/// the timestamp advances by one 20 ms frame per packet.
pub const Sender = struct {
    cipher: rtp.Cipher,
    ssrc: u32,
    sequence: u16 = 0,
    timestamp: u32 = 0,

    pub fn init(mode: gateway.EncryptionMode, ssrc: u32, key: [32]u8) Sender {
        var cipher = rtp.Cipher.init(mode);
        cipher.setKey(key);
        return .{ .cipher = cipher, .ssrc = ssrc };
    }

    pub fn deinit(self: *Sender) void {
        self.cipher.deinit();
    }

    /// Wraps one encoded frame in an encrypted RTP packet.
    pub fn packetize(self: *Sender, encoded: []const u8, out: []u8) Error![]const u8 {
        const packet = try self.cipher.encrypt(out, .{
            .sequence = self.sequence,
            .timestamp = self.timestamp,
            .ssrc = self.ssrc,
            .length = rtp.fixed_header_len,
        }, encoded);
        self.sequence +%= 1;
        self.timestamp +%= audio.frame_samples;
        return packet;
    }
};

/// Receive-side RTP state. Decryption authenticates before any Opus payload is
/// exposed.
pub const Receiver = struct {
    cipher: rtp.Cipher,

    pub fn init(mode: gateway.EncryptionMode, key: [32]u8) Receiver {
        var cipher = rtp.Cipher.init(mode);
        cipher.setKey(key);
        return .{ .cipher = cipher };
    }

    pub fn deinit(self: *Receiver) void {
        self.cipher.deinit();
    }

    pub fn depacketize(self: *Receiver, packet: []const u8, out: []u8) Error![]const u8 {
        return self.cipher.decrypt(out, packet);
    }
};

test "encoded frames round-trip through RTP and AEAD with sequence progression" {
    const key: [32]u8 = @splat(3);
    var sender = Sender.init(.aead_aes256_gcm_rtpsize, 7, key);
    defer sender.deinit();
    var receiver = Receiver.init(.aead_aes256_gcm_rtpsize, key);
    defer receiver.deinit();

    var packet: [256]u8 = undefined;
    var plain: [128]u8 = undefined;
    const first = try sender.packetize("opus-frame-1", &packet);
    const decoded = try receiver.depacketize(first, &plain);
    try std.testing.expectEqualStrings("opus-frame-1", decoded);
    try std.testing.expectEqual(@as(u16, 1), sender.sequence);
    try std.testing.expectEqual(@as(u32, audio.frame_samples), sender.timestamp);

    const second = try sender.packetize("opus-frame-2", &packet);
    const decoded2 = try receiver.depacketize(second, &plain);
    try std.testing.expectEqualStrings("opus-frame-2", decoded2);
    try std.testing.expectEqual(@as(u16, 2), sender.sequence);
}

test "tampered packets never expose media" {
    const key: [32]u8 = @splat(4);
    var sender = Sender.init(.aead_xchacha20_poly1305_rtpsize, 1, key);
    defer sender.deinit();
    var receiver = Receiver.init(.aead_xchacha20_poly1305_rtpsize, key);
    defer receiver.deinit();

    var packet: [256]u8 = undefined;
    var plain: [128]u8 = undefined;
    const encrypted = try sender.packetize("secret", &packet);
    packet[encrypted.len - 6] ^= 0xff;
    try std.testing.expectError(error.AuthenticationFailed, receiver.depacketize(encrypted, &plain));
    for (plain[0..6]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "sequence and timestamp wrap as unsigned values" {
    const key: [32]u8 = @splat(5);
    var sender = Sender.init(.aead_aes256_gcm_rtpsize, 2, key);
    defer sender.deinit();
    sender.sequence = 0xFFFF;
    sender.timestamp = 0xFFFF_FFFF;

    var packet: [256]u8 = undefined;
    _ = try sender.packetize("frame", &packet);
    try std.testing.expectEqual(@as(u16, 0), sender.sequence);
    try std.testing.expectEqual(@as(u32, 959), sender.timestamp);
}

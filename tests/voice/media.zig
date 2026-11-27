//! Voice media path contracts.

const std = @import("std");
const diszig = @import("diszig");
const voice = diszig.voice;

test "media path is exported" {
    _ = voice.media.Sender;
    _ = voice.media.Receiver;
}

test "encoded frames round-trip through RTP and AEAD" {
    const key: [32]u8 = @splat(8);
    var sender = voice.media.Sender.init(.aead_aes256_gcm_rtpsize, 11, key);
    defer sender.deinit();
    var receiver = voice.media.Receiver.init(.aead_aes256_gcm_rtpsize, key);
    defer receiver.deinit();

    var packet: [256]u8 = undefined;
    var plain: [64]u8 = undefined;
    const encrypted = try sender.packetize("frame", &packet);
    const decoded = try receiver.depacketize(encrypted, &plain);
    try std.testing.expectEqualStrings("frame", decoded);
    try std.testing.expectEqual(@as(u16, 1), sender.sequence);
}

test "wrong key fails authentication" {
    const key_a: [32]u8 = @splat(1);
    const key_b: [32]u8 = @splat(2);
    var sender = voice.media.Sender.init(.aead_xchacha20_poly1305_rtpsize, 1, key_a);
    defer sender.deinit();
    var receiver = voice.media.Receiver.init(.aead_xchacha20_poly1305_rtpsize, key_b);
    defer receiver.deinit();

    var packet: [256]u8 = undefined;
    var plain: [64]u8 = undefined;
    const encrypted = try sender.packetize("frame", &packet);
    try std.testing.expectError(error.AuthenticationFailed, receiver.depacketize(encrypted, &plain));
}

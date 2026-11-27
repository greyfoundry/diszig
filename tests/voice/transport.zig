//! Voice UDP, RTP and transport-encryption contracts.

const std = @import("std");
const diszig = @import("diszig");
const voice = diszig.voice;

test "transport modules are exported" {
    _ = voice.rtp.Cipher;
    _ = voice.udp.writeRequest;
    try std.testing.expectEqual(@as(u8, 0x78), voice.rtp.opus_payload_type);
}

test "aes and xchacha rtpsize round-trip through the public API" {
    const plaintext = "opus payload";
    inline for (.{
        voice.gateway.EncryptionMode.aead_aes256_gcm_rtpsize,
        voice.gateway.EncryptionMode.aead_xchacha20_poly1305_rtpsize,
    }) |mode| {
        var cipher = voice.rtp.Cipher.init(mode);
        defer cipher.deinit();
        cipher.setKey(@splat(3));

        var packet: [128]u8 = undefined;
        const encrypted = try cipher.encrypt(&packet, .{
            .sequence = 7,
            .timestamp = 960,
            .ssrc = 9,
            .length = 12,
        }, plaintext);
        try std.testing.expectEqual(voice.rtp.encryptedSize(plaintext.len), encrypted.len);

        var out: [64]u8 = undefined;
        const decrypted = try cipher.decrypt(&out, encrypted);
        try std.testing.expectEqualStrings(plaintext, decrypted);
    }
}

test "truncated rtp packets are rejected" {
    var cipher = voice.rtp.Cipher.init(.aead_aes256_gcm_rtpsize);
    defer cipher.deinit();
    cipher.setKey(@splat(1));
    var out: [64]u8 = undefined;
    const short: [20]u8 = @splat(0x80);
    try std.testing.expectError(error.TruncatedPacket, cipher.decrypt(&out, &short));
}

test "discovery response binds to the session ssrc" {
    var response: [voice.udp.packet_len]u8 = @splat(0);
    std.mem.writeInt(u16, response[0..2], 2, .big);
    std.mem.writeInt(u16, response[2..4], 70, .big);
    std.mem.writeInt(u32, response[4..8], 77, .big);
    @memcpy(response[8..17], "192.0.2.1");
    std.mem.writeInt(u16, response[72..74], 40000, .big);

    const discovery = try voice.udp.parseResponse(&response, 77);
    try std.testing.expectEqualStrings("192.0.2.1", discovery.address);
    try std.testing.expectError(error.SsrcMismatch, voice.udp.parseResponse(&response, 78));
}

//! RTP framing and Discord `rtpsize` transport encryption.
//!
//! Crypto uses Zig's audited AEAD implementations. Nonce layout follows
//! Discord's documented `rtpsize` modes as implemented by discord.js: the
//! 32-bit counter is incremented, written big-endian at the start of a
//! zero-filled IV (12 bytes for AES-GCM, 24 for XChaCha20-Poly1305), encrypted
//! as `header || ciphertext || tag`, and the same 4 counter bytes are appended
//! after the tag. The header is the AEAD associated data.
//!
//! Packet layout: `RTP header (12) || ciphertext || tag (16) || nonce (4)`.

const std = @import("std");
const voice_gateway = @import("gateway.zig");

pub const Error = error{
    TruncatedPacket,
    InvalidVersion,
    InvalidPayloadType,
    UnsupportedHeaderExtension,
    BufferTooSmall,
    MissingKey,
    AuthenticationFailed,
};

pub const opus_payload_type: u8 = 0x78;
pub const fixed_header_len: usize = 12;
pub const tag_len: usize = 16;
pub const nonce_len: usize = 4;

pub const Header = struct {
    sequence: u16,
    timestamp: u32,
    ssrc: u32,
    /// 12 plus CSRC and extension preamble bytes when present.
    length: usize,
};

/// Writes the fixed 12-byte Opus RTP header. Callers own sequence/timestamp
/// progression; both use unsigned wrapping arithmetic.
pub fn writeHeader(out: []u8, header: Header) void {
    std.debug.assert(out.len >= fixed_header_len);
    out[0] = 0x80; // version 2, no padding, no CSRC, no extension
    out[1] = opus_payload_type;
    std.mem.writeInt(u16, out[2..4], header.sequence, .big);
    std.mem.writeInt(u32, out[4..8], header.timestamp, .big);
    std.mem.writeInt(u32, out[8..12], header.ssrc, .big);
}

/// Parses a received RTP header and computes the unencrypted header length,
/// including CSRCs and an optional extension preamble.
pub fn parseHeader(packet: []const u8) Error!Header {
    if (packet.len < fixed_header_len) return error.TruncatedPacket;
    if ((packet[0] >> 6) != 2) return error.InvalidVersion;
    if (packet[1] != opus_payload_type) return error.InvalidPayloadType;

    const csrc_count: usize = packet[0] & 0x0f;
    var length: usize = fixed_header_len + csrc_count * 4;
    if (length > packet.len) return error.TruncatedPacket;
    if ((packet[0] & 0x10) != 0) {
        if (length + 4 > packet.len) return error.TruncatedPacket;
        const words = std.mem.readInt(u16, packet[length + 2 ..][0..2], .big);
        length += 4 + @as(usize, words) * 4;
        if (length > packet.len) return error.TruncatedPacket;
    }

    return .{
        .sequence = std.mem.readInt(u16, packet[2..4], .big),
        .timestamp = std.mem.readInt(u32, packet[4..8], .big),
        .ssrc = std.mem.readInt(u32, packet[8..12], .big),
        .length = length,
    };
}

pub fn encryptedSize(plaintext_len: usize) usize {
    return fixed_header_len + plaintext_len + tag_len + nonce_len;
}

/// Transport cipher state. The key is owned and zeroed on rotation/deinit; the
/// counter wraps at 2^32 and restarts at 1 after a key change.
pub const Cipher = struct {
    mode: voice_gateway.EncryptionMode,
    key: [32]u8 = @splat(0),
    counter: u32 = 0,
    has_key: bool = false,

    pub fn init(mode: voice_gateway.EncryptionMode) Cipher {
        return .{ .mode = mode };
    }

    pub fn setKey(self: *Cipher, key: [32]u8) void {
        @memset(&self.key, 0);
        self.key = key;
        self.counter = 0;
        self.has_key = true;
    }

    pub fn deinit(self: *Cipher) void {
        @memset(&self.key, 0);
        self.counter = 0;
        self.has_key = false;
    }

    /// Encrypts `plaintext` as one RTP packet. `out` must be at least
    /// `encryptedSize(plaintext.len)`. Returns the packet slice.
    pub fn encrypt(
        self: *Cipher,
        out: []u8,
        header: Header,
        plaintext: []const u8,
    ) Error![]const u8 {
        if (!self.has_key) return error.MissingKey;
        const total = encryptedSize(plaintext.len);
        if (out.len < total) return error.BufferTooSmall;

        const rtp = out[0..fixed_header_len];
        writeHeader(rtp, header);

        self.counter +%= 1;
        const nonce_bytes: [4]u8 = .{
            @truncate(self.counter >> 24),
            @truncate(self.counter >> 16),
            @truncate(self.counter >> 8),
            @truncate(self.counter),
        };

        const ciphertext = out[fixed_header_len .. fixed_header_len + plaintext.len];
        const tag_ptr: *[tag_len]u8 = @ptrCast(out.ptr + fixed_header_len + plaintext.len);
        switch (self.mode) {
            .aead_aes256_gcm_rtpsize => {
                var nonce: [12]u8 = @splat(0);
                nonce[0..4].* = nonce_bytes;
                std.crypto.aead.aes_gcm.Aes256Gcm.encrypt(
                    ciphertext,
                    tag_ptr,
                    plaintext,
                    rtp,
                    nonce,
                    self.key,
                );
            },
            .aead_xchacha20_poly1305_rtpsize => {
                var nonce: [24]u8 = @splat(0);
                nonce[0..4].* = nonce_bytes;
                std.crypto.aead.chacha_poly.XChaCha20Poly1305.encrypt(
                    ciphertext,
                    tag_ptr,
                    plaintext,
                    rtp,
                    nonce,
                    self.key,
                );
            },
        }
        @memcpy(out[total - nonce_len .. total], &nonce_bytes);
        return out[0..total];
    }

    /// Decrypts one RTP packet into `out`. The nonce trailer is read from the
    /// packet. On authentication failure the output buffer is zeroed and no
    /// plaintext is returned.
    pub fn decrypt(self: *Cipher, out: []u8, packet: []const u8) Error![]const u8 {
        if (!self.has_key) return error.MissingKey;
        if (packet.len < fixed_header_len + tag_len + nonce_len) return error.TruncatedPacket;
        const header = try parseHeader(packet);
        if (header.length + tag_len + nonce_len > packet.len) return error.TruncatedPacket;

        const ciphertext = packet[header.length .. packet.len - tag_len - nonce_len];
        var tag: [tag_len]u8 = undefined;
        @memcpy(&tag, packet[packet.len - tag_len - nonce_len ..][0..tag_len]);
        var nonce_bytes: [nonce_len]u8 = undefined;
        @memcpy(&nonce_bytes, packet[packet.len - nonce_len ..]);
        if (ciphertext.len > out.len) return error.BufferTooSmall;

        const result = switch (self.mode) {
            .aead_aes256_gcm_rtpsize => blk: {
                var nonce: [12]u8 = @splat(0);
                nonce[0..4].* = nonce_bytes;
                break :blk std.crypto.aead.aes_gcm.Aes256Gcm.decrypt(
                    out[0..ciphertext.len],
                    ciphertext,
                    tag,
                    packet[0..header.length],
                    nonce,
                    self.key,
                );
            },
            .aead_xchacha20_poly1305_rtpsize => blk: {
                var nonce: [24]u8 = @splat(0);
                nonce[0..4].* = nonce_bytes;
                break :blk std.crypto.aead.chacha_poly.XChaCha20Poly1305.decrypt(
                    out[0..ciphertext.len],
                    ciphertext,
                    tag,
                    packet[0..header.length],
                    nonce,
                    self.key,
                );
            },
        };
        result catch |err| {
            @memset(out[0..ciphertext.len], 0);
            return err;
        };
        return out[0..ciphertext.len];
    }
};

test "rtp header round-trips and rejects malformed packets" {
    var bytes: [fixed_header_len]u8 = undefined;
    writeHeader(&bytes, .{ .sequence = 0xFFFF, .timestamp = 0xFFFFFFFF, .ssrc = 42, .length = 0 });
    const header = try parseHeader(&bytes);
    try std.testing.expectEqual(@as(u16, 0xFFFF), header.sequence);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), header.timestamp);
    try std.testing.expectEqual(@as(usize, 12), header.length);

    try std.testing.expectError(error.TruncatedPacket, parseHeader(bytes[0..8]));
    var wrong_version = bytes;
    wrong_version[0] = 0x40;
    try std.testing.expectError(error.InvalidVersion, parseHeader(&wrong_version));
    var wrong_type = bytes;
    wrong_type[1] = 0x6f;
    try std.testing.expectError(error.InvalidPayloadType, parseHeader(&wrong_type));
}

test "rtp header length includes csrc and extension" {
    var packet: [32]u8 = @splat(0);
    packet[0] = 0x80 | 0x10 | 0x01; // version 2, extension, one CSRC
    packet[1] = opus_payload_type;
    // CSRC at 12..16, extension preamble at 16..20, one word at 20..24.
    packet[18] = 0;
    packet[19] = 1;
    const header = try parseHeader(&packet);
    try std.testing.expectEqual(@as(usize, 24), header.length);
}

test "aes-gcm rtpsize round-trip and tamper rejection" {
    const key: [32]u8 = @splat(7);
    var cipher = Cipher.init(.aead_aes256_gcm_rtpsize);
    defer cipher.deinit();
    cipher.setKey(key);

    var packet: [128]u8 = undefined;
    const plaintext = "opus-frame";
    const encrypted = try cipher.encrypt(&packet, .{ .sequence = 1, .timestamp = 960, .ssrc = 5, .length = 12 }, plaintext);
    try std.testing.expectEqual(encryptedSize(plaintext.len), encrypted.len);
    try std.testing.expectEqual(@as(u8, 1), encrypted[encrypted.len - 1]);
    try std.testing.expectEqual(@as(u8, 0x80), encrypted[0]);

    var plain_out: [64]u8 = undefined;
    const decrypted = try cipher.decrypt(&plain_out, encrypted);
    try std.testing.expectEqualStrings(plaintext, decrypted);

    encrypted[encrypted.len - 6] ^= 1;
    try std.testing.expectError(error.AuthenticationFailed, cipher.decrypt(&plain_out, encrypted));
    for (plain_out[0..plaintext.len]) |byte| try std.testing.expectEqual(@as(u8, 0), byte);
}

test "xchacha rtpsize round-trip and nonce rollover" {
    const key: [32]u8 = @splat(9);
    var cipher = Cipher.init(.aead_xchacha20_poly1305_rtpsize);
    defer cipher.deinit();
    cipher.setKey(key);

    var packet: [128]u8 = undefined;
    cipher.counter = 0xFFFF_FFFF;
    const first = try cipher.encrypt(&packet, .{ .sequence = 0, .timestamp = 0, .ssrc = 1, .length = 12 }, "a");
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 0 }, first[first.len - 4 ..]);
    const second = try cipher.encrypt(&packet, .{ .sequence = 1, .timestamp = 960, .ssrc = 1, .length = 12 }, "b");
    try std.testing.expectEqualSlices(u8, &.{ 0, 0, 0, 1 }, second[second.len - 4 ..]);
}

test "key rotation discards the old context" {
    const key_a: [32]u8 = @splat(1);
    const key_b: [32]u8 = @splat(2);
    var cipher = Cipher.init(.aead_aes256_gcm_rtpsize);
    defer cipher.deinit();

    cipher.setKey(key_a);
    var packet: [96]u8 = undefined;
    const encrypted = try cipher.encrypt(&packet, .{ .sequence = 1, .timestamp = 1, .ssrc = 1, .length = 12 }, "frame");
    var out: [64]u8 = undefined;
    _ = try cipher.decrypt(&out, encrypted);

    cipher.setKey(key_b);
    try std.testing.expectError(error.AuthenticationFailed, cipher.decrypt(&out, encrypted));
    try std.testing.expectEqual(@as(u32, 0), cipher.counter);

    var no_key = Cipher.init(.aead_aes256_gcm_rtpsize);
    try std.testing.expectError(error.MissingKey, no_key.encrypt(&packet, .{ .sequence = 1, .timestamp = 1, .ssrc = 1, .length = 12 }, "x"));
}

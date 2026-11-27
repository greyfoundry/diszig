//! Optional voice capability report tests.

const std = @import("std");
const diszig = @import("diszig");
const voice = diszig.voice;

test "voice module is exported and reports unavailable" {
    try std.testing.expect(!voice.isAvailable());
    try std.testing.expectEqual(voice.Status.unavailable, voice.status);
}

test "voice gate returns an explicit unsupported error" {
    try std.testing.expectError(error.UnsupportedVoice, voice.require());
}

test "documented voice constants are exposed without a support claim" {
    try std.testing.expectEqual(@as(u8, 8), voice.documented_gateway_version);
    try std.testing.expectEqualStrings("aead_xchacha20_poly1305_rtpsize", voice.encryption_modes[0]);
    try std.testing.expect(voice.reasons.len >= 3);
}

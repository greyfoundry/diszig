//! CDN identity primitives: image hashes, formats, sizes and default-avatar
//! index rules. URL construction belongs to the resource models that know the
//! exact endpoint path.

const std = @import("std");
const Snowflake = @import("snowflake.zig").Snowflake;

pub const base_url = "https://cdn.discordapp.com";

pub const ImageFormat = enum {
    jpg,
    png,
    webp,
    gif,
    lottie,

    pub fn extension(self: ImageFormat) []const u8 {
        return switch (self) {
            .jpg => ".jpg",
            .png => ".png",
            .webp => ".webp",
            .gif => ".gif",
            .lottie => ".json",
        };
    }
};

pub const Size = enum(u16) {
    s16 = 16,
    s32 = 32,
    s64 = 64,
    s128 = 128,
    s256 = 256,
    s512 = 512,
    s1024 = 1024,
    s2048 = 2048,
    s4096 = 4096,

    pub fn parse(value: u16) ?Size {
        return switch (value) {
            16 => .s16,
            32 => .s32,
            64 => .s64,
            128 => .s128,
            256 => .s256,
            512 => .s512,
            1024 => .s1024,
            2048 => .s2048,
            4096 => .s4096,
            else => null,
        };
    }
};

pub const ImageHash = struct {
    value: []const u8,

    pub fn isAnimated(self: ImageHash) bool {
        return std.mem.startsWith(u8, self.value, "a_");
    }

    /// A 32-character hex digest, optionally prefixed with `a_` for an
    /// animated asset.
    pub fn isWellFormed(self: ImageHash) bool {
        const digest = if (self.isAnimated()) self.value[2..] else self.value;
        if (digest.len != 32) return false;
        for (digest) |c| {
            if (!std.ascii.isHex(c)) return false;
        }
        return true;
    }
};

/// Default avatar index for a legacy discriminator: `discriminator % 5`.
pub fn defaultAvatarIndexLegacy(discriminator: u16) u8 {
    return @intCast(discriminator % 5);
}

/// Default avatar index for the new username system: `(user_id >> 22) % 6`.
pub fn defaultAvatarIndexNew(user_id: Snowflake) u8 {
    return @intCast((user_id.toU64() >> 22) % 6);
}

test "formats expose documented extensions" {
    try std.testing.expectEqualStrings(".jpg", ImageFormat.jpg.extension());
    try std.testing.expectEqualStrings(".png", ImageFormat.png.extension());
    try std.testing.expectEqualStrings(".webp", ImageFormat.webp.extension());
    try std.testing.expectEqualStrings(".gif", ImageFormat.gif.extension());
    try std.testing.expectEqualStrings(".json", ImageFormat.lottie.extension());
}

test "only documented power-of-two sizes parse" {
    for ([_]u16{ 16, 32, 64, 128, 256, 512, 1024, 2048, 4096 }) |value| {
        try std.testing.expect(Size.parse(value) != null);
    }
    for ([_]u16{ 0, 8, 15, 17, 100, 8192 }) |value| {
        try std.testing.expectEqual(@as(?Size, null), Size.parse(value));
    }
}

test "image hashes validate static and animated digests" {
    try std.testing.expect((ImageHash{ .value = "0123456789abcdef0123456789abcdef" }).isWellFormed());
    const animated = ImageHash{ .value = "a_0123456789abcdef0123456789abcdef" };
    try std.testing.expect(animated.isWellFormed());
    try std.testing.expect(animated.isAnimated());
    try std.testing.expect(!(ImageHash{ .value = "a_0123" }).isWellFormed());
    try std.testing.expect(!(ImageHash{ .value = "zz23456789abcdef0123456789abcdef" }).isWellFormed());
}

test "default avatar index rules match the prose" {
    try std.testing.expectEqual(@as(u8, 0), defaultAvatarIndexLegacy(0));
    try std.testing.expectEqual(@as(u8, 4), defaultAvatarIndexLegacy(9));

    const id = Snowflake.fromU64((@as(u64, 7) << 22) | 123);
    try std.testing.expectEqual(@as(u8, 1), defaultAvatarIndexNew(id));
}

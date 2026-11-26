//! Standard Discord CDN URL construction.
//!
//! These endpoints are not signed. Attachment URLs supplied by Discord may
//! contain `ex`, `is` and `hm` query credentials; this module never builds or
//! logs those signed forms. Callers must use the server-provided URL for
//! attachments.

const std = @import("std");
const protocol = @import("protocol");

pub const Snowflake = protocol.Snowflake;
pub const Format = protocol.cdn.ImageFormat;
pub const Size = protocol.cdn.Size;
pub const base_url = protocol.cdn.base_url;

pub const Error = error{
    InvalidHash,
    UnsupportedFormat,
    InvalidSize,
    IndexOutOfRange,
    WriteFailed,
};

fn writeHash(writer: *std.Io.Writer, hash: []const u8) Error!void {
    const image = protocol.cdn.ImageHash{ .value = hash };
    if (!image.isWellFormed()) return error.InvalidHash;
    writer.writeAll(hash) catch return error.WriteFailed;
}

fn writeSize(writer: *std.Io.Writer, size: ?Size) Error!void {
    if (size) |value| {
        writer.print("?size={d}", .{@backingInt(value)}) catch return error.WriteFailed;
    }
}

fn writeFormat(writer: *std.Io.Writer, format: Format) Error!void {
    writer.writeAll(format.extension()) catch return error.WriteFailed;
}

pub fn writeCustomEmoji(
    writer: *std.Io.Writer,
    emoji_id: Snowflake,
    format: Format,
    size: ?Size,
) Error!void {
    if (format == .lottie) return error.UnsupportedFormat;
    writer.writeAll(base_url) catch return error.WriteFailed;
    writer.writeAll("/emojis/") catch return error.WriteFailed;
    writer.print("{d}", .{emoji_id.toU64()}) catch return error.WriteFailed;
    try writeFormat(writer, format);
    try writeSize(writer, size);
}

pub fn writeGuildIcon(
    writer: *std.Io.Writer,
    guild_id: Snowflake,
    hash: []const u8,
    format: Format,
    size: ?Size,
) Error!void {
    if (format == .lottie) return error.UnsupportedFormat;
    writer.writeAll(base_url) catch return error.WriteFailed;
    writer.writeAll("/icons/") catch return error.WriteFailed;
    writer.print("{d}/", .{guild_id.toU64()}) catch return error.WriteFailed;
    try writeHash(writer, hash);
    try writeFormat(writer, format);
    try writeSize(writer, size);
}

pub fn writeUserAvatar(
    writer: *std.Io.Writer,
    user_id: Snowflake,
    hash: []const u8,
    format: Format,
    size: ?Size,
) Error!void {
    if (format == .lottie) return error.UnsupportedFormat;
    writer.writeAll(base_url) catch return error.WriteFailed;
    writer.writeAll("/avatars/") catch return error.WriteFailed;
    writer.print("{d}/", .{user_id.toU64()}) catch return error.WriteFailed;
    try writeHash(writer, hash);
    try writeFormat(writer, format);
    try writeSize(writer, size);
}

pub fn writeDefaultAvatar(writer: *std.Io.Writer, index: u8) Error!void {
    if (index > 5) return error.IndexOutOfRange;
    writer.writeAll(base_url) catch return error.WriteFailed;
    writer.writeAll("/embed/avatars/") catch return error.WriteFailed;
    writer.print("{d}.png", .{index}) catch return error.WriteFailed;
}

test "documented CDN URLs are built with validated hashes" {
    const guild = Snowflake.fromU64(81384788765712384);
    const user = Snowflake.fromU64(175928847299117063);
    const hash = "0123456789abcdef0123456789abcdef";

    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeGuildIcon(&writer, guild, hash, .png, .s128);
    try std.testing.expectEqualStrings(
        "https://cdn.discordapp.com/icons/81384788765712384/0123456789abcdef0123456789abcdef.png?size=128",
        writer.buffered(),
    );

    var avatar_buffer: [512]u8 = undefined;
    var avatar_writer = std.Io.Writer.fixed(&avatar_buffer);
    try writeUserAvatar(&avatar_writer, user, "a_0123456789abcdef0123456789abcdef", .webp, null);
    try std.testing.expectEqualStrings(
        "https://cdn.discordapp.com/avatars/175928847299117063/a_0123456789abcdef0123456789abcdef.webp",
        avatar_writer.buffered(),
    );
}

test "invalid hashes and unsupported options are rejected" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.InvalidHash,
        writeGuildIcon(&writer, Snowflake.fromU64(1), "not-a-hash", .png, null),
    );

    var emoji_buffer: [256]u8 = undefined;
    var emoji_writer = std.Io.Writer.fixed(&emoji_buffer);
    try std.testing.expectError(
        error.UnsupportedFormat,
        writeCustomEmoji(&emoji_writer, Snowflake.fromU64(1), .lottie, null),
    );
}

test "default avatar indices are bounded" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeDefaultAvatar(&writer, 5);
    try std.testing.expectEqualStrings("https://cdn.discordapp.com/embed/avatars/5.png", writer.buffered());
    try std.testing.expectError(error.IndexOutOfRange, writeDefaultAvatar(&writer, 6));
}

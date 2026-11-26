const std = @import("std");
const diszig = @import("diszig");

test "public multipart writer streams multiple file parts" {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const files = [_]diszig.rest.multipart.FilePart{
        .{ .filename = "one.txt", .source = .{ .bytes = "one" } },
        .{ .filename = "two.txt", .source = .{ .bytes = "two" } },
    };
    try diszig.rest.multipart.write(
        &writer,
        std.testing.io,
        "BOUNDARY",
        "{\"content\":\"ok\"}",
        &files,
        1024,
    );
    const body = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, body, "files[0]") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "files[1]") != null);
    try std.testing.expect(std.mem.endsWith(u8, body, "--BOUNDARY--\r\n"));
}

test "public CDN helpers reject invalid hashes and formats" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.InvalidHash,
        diszig.rest.cdn.writeUserAvatar(&writer, diszig.Snowflake.fromU64(1), "bad", .png, null),
    );
    try std.testing.expectError(
        error.UnsupportedFormat,
        diszig.rest.cdn.writeCustomEmoji(&writer, diszig.Snowflake.fromU64(1), .lottie, null),
    );
}

test "documented CDN size options only" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try diszig.rest.cdn.writeGuildIcon(
        &writer,
        diszig.Snowflake.fromU64(1),
        "0123456789abcdef0123456789abcdef",
        .png,
        .s64,
    );
    try std.testing.expect(std.mem.endsWith(u8, writer.buffered(), "?size=64"));
}

const std = @import("std");
const diszig = @import("diszig");

test "bearer credentials never receive a bot prefix" {
    var client = try diszig.rest.Client.init(std.testing.allocator, std.testing.io, .{
        .auth = .{ .bearer = "abc" },
    });
    defer client.deinit();
    try std.testing.expectEqualStrings("Bearer abc", client.authHeader());
    try std.testing.expect(std.mem.startsWith(u8, client.authHeader(), "Bot ") == false);
}

test "route paths cannot escape the configured origin" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectError(
        error.InvalidPath,
        diszig.rest.transport.buildUri("https://discord.com/api/v10", "https://evil.test/x", &buffer),
    );
    try std.testing.expectError(
        error.InvalidPath,
        diszig.rest.transport.buildUri("https://discord.com/api/v10", "/a/../b", &buffer),
    );
}

test "different hosts are not same-origin" {
    const a = try std.Uri.parse("https://discord.com/api");
    const b = try std.Uri.parse("https://cdn.discordapp.com/x");
    try std.testing.expect(!diszig.rest.transport.sameOrigin(a, b));
}

test "empty response owns an empty allocation" {
    var response = diszig.rest.Response{
        .status = 204,
        .body = try std.testing.allocator.alloc(u8, 0),
        .allocator = std.testing.allocator,
    };
    defer response.deinit();
    try std.testing.expectEqual(@as(usize, 0), response.body.len);
}

//! Builds a documented OAuth2 authorization URL and shows the callback checks.
//! Run with `zig build examples` to compile; it performs no network I/O.

const std = @import("std");
const diszig = @import("diszig");

pub fn main() !void {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const url = try diszig.rest.oauth2.writeAuthorizationUrl(&writer, .{
        .client_id = "157730590492196864",
        .scopes = &.{ .identify, .guilds_join },
        .state = "replace-with-a-per-request-nonce",
        .redirect_uri = "https://example.test/callback",
        .prompt = .consent,
    });
    std.debug.print("{s}\n", .{url});

    diszig.rest.oauth2.validateCallback("replace-with-a-per-request-nonce", "replace-with-a-per-request-nonce") catch {
        std.debug.print("state did not match\n", .{});
        return;
    };
    std.debug.print("state matches; exchange the code server-side\n", .{});
}

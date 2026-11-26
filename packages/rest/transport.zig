//! REST transport helpers: credential kinds, URL validation and origin checks.

const std = @import("std");

pub const Auth = union(enum) {
    none,
    bot: []const u8,
    bearer: []const u8,
    webhook: []const u8,
    interaction: []const u8,
};

pub const AuthError = error{ TokenTooLong, InvalidToken };

/// Writes the Authorization value for credential kinds that use the header.
/// Webhook and interaction tokens stay in the route path and produce no
/// Authorization header.
pub fn writeAuthHeader(auth: Auth, buffer: []u8) AuthError![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    switch (auth) {
        .none, .webhook, .interaction => return "",
        .bot => |token| {
            try validateToken(token);
            writer.writeAll("Bot ") catch return error.TokenTooLong;
            writer.writeAll(token) catch return error.TokenTooLong;
        },
        .bearer => |token| {
            try validateToken(token);
            writer.writeAll("Bearer ") catch return error.TokenTooLong;
            writer.writeAll(token) catch return error.TokenTooLong;
        },
    }
    return writer.buffered();
}

fn validateToken(token: []const u8) AuthError!void {
    if (token.len == 0) return error.InvalidToken;
    for (token) |c| {
        if (c == '\r' or c == '\n' or c == 0) return error.InvalidToken;
    }
}

pub const UrlError = error{
    InvalidPath,
    PathTooLong,
    InvalidBaseUrl,
};

/// Builds an absolute request URI from the configured API base and a relative
/// route. Absolute URLs, control characters and path traversal are rejected.
pub fn buildUri(base_url: []const u8, path: []const u8, buffer: []u8) UrlError!std.Uri {
    if (path.len == 0 or path[0] != '/') return error.InvalidPath;
    if (std.mem.indexOf(u8, path, "://") != null) return error.InvalidPath;
    if (std.mem.indexOf(u8, path, "..") != null) return error.InvalidPath;
    for (path) |c| {
        if (c == '\r' or c == '\n' or c == 0) return error.InvalidPath;
    }
    if (base_url.len == 0) return error.InvalidBaseUrl;

    var writer = std.Io.Writer.fixed(buffer);
    writer.writeAll(base_url) catch return error.PathTooLong;
    if (base_url[base_url.len - 1] == '/') {
        writer.writeAll(path[1..]) catch return error.PathTooLong;
    } else {
        writer.writeAll(path) catch return error.PathTooLong;
    }
    return std.Uri.parse(writer.buffered()) catch return error.InvalidPath;
}

pub fn sameOrigin(a: std.Uri, b: std.Uri) bool {
    if (!std.ascii.eqlIgnoreCase(a.scheme, b.scheme)) return false;
    const ah = (a.host orelse return false).percent_encoded;
    const bh = (b.host orelse return false).percent_encoded;
    if (!std.ascii.eqlIgnoreCase(ah, bh)) return false;
    const default_port: u16 = if (std.ascii.eqlIgnoreCase(a.scheme, "https")) 443 else 80;
    return (a.port orelse default_port) == (b.port orelse default_port);
}

test "bot and bearer prefixes are distinct" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings("Bot abc", try writeAuthHeader(.{ .bot = "abc" }, &buffer));
    try std.testing.expectEqualStrings("Bearer abc", try writeAuthHeader(.{ .bearer = "abc" }, &buffer));
    try std.testing.expectEqualStrings("", try writeAuthHeader(.{ .webhook = "abc" }, &buffer));
}

test "route paths reject absolute URLs and traversal" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectError(error.InvalidPath, buildUri("https://discord.com/api/v10", "https://evil.test/x", &buffer));
    try std.testing.expectError(error.InvalidPath, buildUri("https://discord.com/api/v10", "/a/../b", &buffer));
    try std.testing.expectError(error.InvalidPath, buildUri("https://discord.com/api/v10", "/a\r\nInjected: x", &buffer));
    const uri = try buildUri("https://discord.com/api/v10", "/users/@me", &buffer);
    try std.testing.expectEqualStrings("/api/v10/users/@me", uri.path.percent_encoded);
}

test "same origin ignores default port spelling" {
    const a = try std.Uri.parse("https://discord.com/api");
    const b = try std.Uri.parse("https://discord.com:443/api");
    const c = try std.Uri.parse("https://cdn.discordapp.com/x");
    try std.testing.expect(sameOrigin(a, b));
    try std.testing.expect(!sameOrigin(a, c));
}

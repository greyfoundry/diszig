//! OAuth2 helpers: URL/body builders, callback checks and token parsing.

const std = @import("std");
const diszig = @import("diszig");
const oauth2 = diszig.rest.oauth2;

test "authorization URL redacts nothing secret because a secret is never a parameter" {
    var buffer: [512]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const url = try oauth2.writeAuthorizationUrl(&writer, .{
        .client_id = "157730590492196864",
        .scopes = &.{ .identify, .email },
        .state = "state-value",
        .redirect_uri = "https://example.test/callback",
    });
    try std.testing.expect(std.mem.indexOf(u8, url, "client_secret") == null);
    try std.testing.expect(std.mem.indexOf(u8, url, "identify%20email") != null);
}

test "endpoint constants follow the documented unversioned URLs" {
    try std.testing.expectEqualStrings("https://discord.com/oauth2/authorize", oauth2.endpoints.authorize);
    try std.testing.expectEqualStrings("https://discord.com/api/oauth2/token", oauth2.endpoints.token);
    try std.testing.expectEqualStrings("https://discord.com/api/oauth2/token/revoke", oauth2.endpoints.revoke);
    try std.testing.expectEqualStrings("https://discord.com", oauth2.endpoints.issuer);
}

test "implicit grant rejects role connections write" {
    try std.testing.expectError(
        error.ScopeNotAllowedForGrant,
        oauth2.validateScopes(.implicit, &.{.role_connections_write}),
    );
    try oauth2.validateScopes(.implicit, &.{.identify});
}

test "token grant names are exact" {
    try std.testing.expectEqualStrings("authorization_code", oauth2.Grant.authorization_code.wire());
    try std.testing.expectEqualStrings("refresh_token", oauth2.Grant.refresh_token.wire());
    try std.testing.expectEqualStrings("client_credentials", oauth2.Grant.client_credentials.wire());
}

test "secret values are only exposed through the redacted contract" {
    const secret = oauth2.Secret{ .value = "top-secret" };
    try std.testing.expectEqualStrings("<redacted>", secret.redacted());
}

test "a failed refresh cannot produce a parsed token" {
    try std.testing.expectError(
        error.TokenEndpointRejected,
        oauth2.parseAccessTokenResponse(std.testing.allocator, 401, "{\"error\":\"invalid_grant\"}"),
    );
}

test "access token response parses and reports expiry" {
    var parsed = try oauth2.parseAccessTokenResponse(std.testing.allocator, 200,
        \\{"access_token":"a","token_type":"Bearer","expires_in":604800,"refresh_token":"r","scope":"identify"}
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 604800), parsed.value.expires_in);
    try std.testing.expectEqualStrings("r", parsed.value.refresh_token.?);
}

test "revocation body includes the optional hint" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const body = try oauth2.writeRevokeBody(&writer, .{
        .token = "abc",
        .token_type_hint = .refresh_token,
    });
    try std.testing.expectEqualStrings("token=abc&token_type_hint=refresh_token", body);
}

fn parseToken(allocator: std.mem.Allocator, payload: []const u8) !void {
    var parsed = try oauth2.parseAccessTokenResponse(allocator, 200, payload);
    defer parsed.deinit();
}

test "allocation failure while parsing a token response is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseToken,
        .{"{\"access_token\":\"a\",\"token_type\":\"Bearer\",\"expires_in\":1,\"refresh_token\":\"r\",\"scope\":\"identify\"}"},
    );
}

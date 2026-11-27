//! Social wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

pub const ApplicationIdentityProviderAuthType = enum {
    OIDC,
    EPIC_ONLINE_SERVICES_ACCESS_TOKEN,
    EPIC_ONLINE_SERVICES_ID_TOKEN,
    STEAM_SESSION_TICKET,
    UNITY_SERVICES_ID_TOKEN,
    DISCORD_BOT_ISSUED_ACCESS_TOKEN,
    APPLE_ID_TOKEN,
    PLAYSTATION_NETWORK_ID_TOKEN,
};

pub const InboundApplicationIdentityProviderAuthType = json.InboundStringEnum(ApplicationIdentityProviderAuthType);

pub const OAuth2GetOpenIDConnectUserInfoResponse = struct {
    sub: []const u8,
    email: ?[]const u8 = null,
    email_verified: ?bool = null,
    preferred_username: ?[]const u8 = null,
    nickname: ?[]const u8 = null,
    picture: ?[]const u8 = null,
    locale: ?[]const u8 = null,
};

/// Provisional OAuth2 token response. Every token field is a credential:
/// callers must not log or persist it, and should release it as soon as the
/// exchange is complete.
pub const ProvisionalTokenResponse = struct {
    token_type: []const u8,
    access_token: []const u8,
    expires_in: i32,
    scope: []const u8,
    id_token: []const u8,
    refresh_token: ?[]const u8 = null,
    scopes: ?[]const []const u8 = null,
    expires_at_s: ?i32 = null,
};

test "identity provider auth types use the exact wire spelling" {
    try std.testing.expectEqualStrings("OIDC", @tagName(ApplicationIdentityProviderAuthType.OIDC));
    try std.testing.expectEqualStrings(
        "PLAYSTATION_NETWORK_ID_TOKEN",
        @tagName(ApplicationIdentityProviderAuthType.PLAYSTATION_NETWORK_ID_TOKEN),
    );
    try std.testing.expectEqualStrings(
        "DISCORD_BOT_ISSUED_ACCESS_TOKEN",
        @tagName(ApplicationIdentityProviderAuthType.DISCORD_BOT_ISSUED_ACCESS_TOKEN),
    );
}

test "openid user info requires sub only" {
    var parsed = try std.json.parseFromSlice(OAuth2GetOpenIDConnectUserInfoResponse, std.testing.allocator,
        \\{"sub":"1234"}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("1234", parsed.value.sub);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.value.email);

    var full = try std.json.parseFromSlice(OAuth2GetOpenIDConnectUserInfoResponse, std.testing.allocator,
        \\{"sub":"1234","email":null,"email_verified":true,"preferred_username":"user","nickname":null,"picture":"https://x/p.png","locale":"en-US"}
    , .{ .ignore_unknown_fields = true });
    defer full.deinit();
    try std.testing.expect(full.value.email_verified.?);
    try std.testing.expectEqual(@as(?[]const u8, null), full.value.nickname);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(OAuth2GetOpenIDConnectUserInfoResponse, std.testing.allocator, "{}", .{}),
    );
}

test "provisional token requires the documented fields" {
    var parsed = try std.json.parseFromSlice(ProvisionalTokenResponse, std.testing.allocator,
        \\{"token_type":"Bearer","access_token":"a","expires_in":3600,"scope":"identify","id_token":"i","scopes":["identify","email"],"expires_at_s":1700000000}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 3600), parsed.value.expires_in);
    try std.testing.expectEqual(@as(usize, 2), parsed.value.scopes.?.len);
    try std.testing.expectEqualStrings("email", parsed.value.scopes.?[1]);

    var nullable = try std.json.parseFromSlice(ProvisionalTokenResponse, std.testing.allocator,
        \\{"token_type":"Bearer","access_token":"a","expires_in":1,"scope":"s","id_token":"i","refresh_token":null,"scopes":null}
    , .{ .ignore_unknown_fields = true });
    defer nullable.deinit();
    try std.testing.expectEqual(@as(?[]const u8, null), nullable.value.refresh_token);
    try std.testing.expectEqual(@as(?[]const []const u8, null), nullable.value.scopes);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(ProvisionalTokenResponse, std.testing.allocator,
            \\{"token_type":"Bearer","access_token":"a","expires_in":1,"scope":"s"}
        , .{}),
    );
}

test "unknown inbound identity provider auth type is retained" {
    var parsed = try std.json.parseFromSlice(InboundApplicationIdentityProviderAuthType, std.testing.allocator,
        \\"FUTURE_PROVIDER"
    , .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?ApplicationIdentityProviderAuthType, null), parsed.value.known());
}

fn parseToken(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try std.json.parseFromSliceLeaky(ProvisionalTokenResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
}

test "allocation failure while parsing token and scopes is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseToken,
        .{"{\"token_type\":\"Bearer\",\"access_token\":\"a\",\"expires_in\":1,\"scope\":\"s\",\"id_token\":\"i\",\"scopes\":[\"identify\",\"email\"]}"},
    );
}

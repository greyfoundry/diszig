//! Social model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const social = diszig.protocol.models.social;

test "every listed schema is exported" {
    _ = social.ApplicationIdentityProviderAuthType;
    _ = social.OAuth2GetOpenIDConnectUserInfoResponse;
    _ = social.ProvisionalTokenResponse;
}

test "identity provider auth type wire values" {
    try std.testing.expectEqualStrings("OIDC", @tagName(social.ApplicationIdentityProviderAuthType.OIDC));
    try std.testing.expectEqualStrings(
        "STEAM_SESSION_TICKET",
        @tagName(social.ApplicationIdentityProviderAuthType.STEAM_SESSION_TICKET),
    );
    try std.testing.expectEqualStrings(
        "APPLE_ID_TOKEN",
        @tagName(social.ApplicationIdentityProviderAuthType.APPLE_ID_TOKEN),
    );
}

test "openid user info parses optional fields" {
    var parsed = try std.json.parseFromSlice(social.OAuth2GetOpenIDConnectUserInfoResponse, std.testing.allocator,
        \\{"sub":"s","email":"a@b","email_verified":false,"preferred_username":"u","picture":"https://x","locale":"en-US"}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("a@b", parsed.value.email.?);
    try std.testing.expect(!parsed.value.email_verified.?);
    try std.testing.expectEqual(@as(?[]const u8, null), parsed.value.nickname);
}

test "provisional token parses nullable and list fields" {
    var parsed = try std.json.parseFromSlice(social.ProvisionalTokenResponse, std.testing.allocator,
        \\{"token_type":"Bearer","access_token":"a","expires_in":60,"scope":"s","id_token":"i","refresh_token":"r","scopes":["s"],"expires_at_s":5}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("r", parsed.value.refresh_token.?);
    try std.testing.expectEqual(@as(i32, 5), parsed.value.expires_at_s.?);
    try std.testing.expectEqualStrings("s", parsed.value.scopes.?[0]);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(social.ProvisionalTokenResponse, std.testing.allocator,
            \\{"token_type":"Bearer","access_token":"a","expires_in":60,"scope":"s"}
        , .{}),
    );
}

test "unknown inbound auth type is retained" {
    var parsed = try std.json.parseFromSlice(social.InboundApplicationIdentityProviderAuthType, std.testing.allocator,
        \\"FUTURE_PROVIDER"
    , .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?social.ApplicationIdentityProviderAuthType, null), parsed.value.known());
    try std.testing.expectEqualStrings("FUTURE_PROVIDER", parsed.value.raw);
}

fn parseUserInfo(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try std.json.parseFromSliceLeaky(social.OAuth2GetOpenIDConnectUserInfoResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
}

test "allocation failure while parsing user info strings is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseUserInfo,
        .{"{\"sub\":\"s\",\"email\":\"a@b\",\"preferred_username\":\"u\",\"picture\":\"https://x\",\"locale\":\"en-US\"}"},
    );
}

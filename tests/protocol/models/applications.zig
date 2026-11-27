//! Applications model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const applications = diszig.protocol.models.applications;

test "every listed schema is exported" {
    _ = applications.ApplicationEventWebhooksStatus;
    _ = applications.ApplicationExplicitContentFilterTypes;
    _ = applications.ApplicationTypes;
    _ = applications.OAuth2Key;
    _ = applications.OAuth2Scopes;
    _ = applications.ApplicationOAuth2InstallParams;
    _ = applications.ApplicationOAuth2InstallParamsResponse;
    _ = applications.OAuth2GetKeys;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(applications.ApplicationEventWebhooksStatus.disabled));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(applications.ApplicationEventWebhooksStatus.enabled));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(applications.ApplicationEventWebhooksStatus.disabled_by_discord));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(applications.ApplicationExplicitContentFilterTypes.inherit));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(applications.ApplicationExplicitContentFilterTypes.always));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(applications.ApplicationTypes.guild_role_subscriptions));
}

test "every oauth2 scope round-trips through its wire value" {
    inline for (@typeInfo(applications.OAuth2Scopes).@"enum".field_values) |enum_value| {
        const scope: applications.OAuth2Scopes = @fromBackingInt(@intCast(enum_value));
        try std.testing.expectEqual(scope, applications.OAuth2Scopes.parseWire(scope.wire()).?);
    }
}

test "oauth2 key requires all fields and parses" {
    var parsed = try std.json.parseFromSlice(applications.OAuth2Key, std.testing.allocator,
        \\{"kty":"RSA","use":"sig","kid":"key-1","n":"modulus","e":"AQAB","alg":"RS256"}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("key-1", parsed.value.kid);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(applications.OAuth2Key, std.testing.allocator,
            \\{"kty":"RSA","use":"sig","kid":"key-1","n":"modulus","e":"AQAB"}
        , .{ .ignore_unknown_fields = true }),
    );
}

test "unknown inbound scope and application type are retained" {
    var scope = try std.json.parseFromSlice(applications.InboundOAuth2Scopes, std.testing.allocator, "\"future.scope\"", .{});
    defer scope.deinit();
    try std.testing.expectEqual(@as(?applications.OAuth2Scopes, null), scope.value.known());
    try std.testing.expectEqualStrings("future.scope", scope.value.raw);

    var app_type = try std.json.parseFromSlice(applications.InboundApplicationTypes, std.testing.allocator, "9", .{});
    defer app_type.deinit();
    try std.testing.expectEqual(@as(?applications.ApplicationTypes, null), app_type.value.known());
}

fn parseKey(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try std.json.parseFromSliceLeaky(applications.OAuth2Key, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
}

test "allocation failure while parsing key fields is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseKey,
        .{"{\"kty\":\"RSA\",\"use\":\"sig\",\"kid\":\"key-1\",\"n\":\"modulus\",\"e\":\"AQAB\",\"alg\":\"RS256\"}"},
    );
}

test "install params validate scopes and permissions" {
    try (applications.ApplicationOAuth2InstallParams{
        .scopes = &.{ .applications_commands, .bot },
        .permissions = 0,
    }).validate();
    try std.testing.expectError(
        error.EmptyScopes,
        (applications.ApplicationOAuth2InstallParams{ .scopes = &.{} }).validate(),
    );
    try std.testing.expectError(
        error.DuplicateScope,
        (applications.ApplicationOAuth2InstallParams{ .scopes = &.{ .bot, .bot } }).validate(),
    );
    try std.testing.expectError(
        error.ScopeNotInstallable,
        (applications.ApplicationOAuth2InstallParams{ .scopes = &.{.guilds} }).validate(),
    );
    try std.testing.expectError(
        error.PermissionsTooLarge,
        (applications.ApplicationOAuth2InstallParams{
            .permissions = applications.max_install_permissions + 1,
        }).validate(),
    );
}

fn parseInstallParams(allocator: std.mem.Allocator, payload: []const u8) !void {
    var parsed = try std.json.parseFromSlice(applications.ApplicationOAuth2InstallParamsResponse, allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
}

test "allocation failure while parsing install params is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseInstallParams,
        .{"{\"scopes\":[\"bot\",\"applications.commands\"],\"permissions\":\"2048\"}"},
    );
}

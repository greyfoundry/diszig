//! Integration wire models used by the integration Gateway events.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;
const User = @import("shared.zig").User;

pub const IntegrationType = enum {
    twitch,
    youtube,
    discord,
    guild_subscription,
};

pub const ExpireBehavior = enum(u8) {
    remove_role = 0,
    kick = 1,
};

pub const Account = struct {
    id: []const u8,
    name: []const u8,
};

pub const Application = struct {
    id: Snowflake,
    name: []const u8,
    icon: json.Presence([]const u8) = .absent,
    description: []const u8,
    bot: ?User = null,
};

pub const Integration = struct {
    id: Snowflake,
    name: []const u8,
    type: json.InboundStringEnum(IntegrationType),
    enabled: bool,
    /// Extra field on INTEGRATION_CREATE/UPDATE.
    guild_id: ?Snowflake = null,
    syncing: ?bool = null,
    role_id: json.Presence(Snowflake) = .absent,
    enable_emoticons: ?bool = null,
    expire_behavior: ?json.InboundEnum(ExpireBehavior) = null,
    expire_grace_period: ?i64 = null,
    /// Omitted for the create/update Gateway payloads.
    user: ?User = null,
    account: Account,
    synced_at: ?[]const u8 = null,
    subscriber_count: ?i64 = null,
    revoked: ?bool = null,
    application: ?Application = null,
    scopes: ?[]const []const u8 = null,
};

pub const IntegrationDelete = struct {
    id: Snowflake,
    guild_id: Snowflake,
    application_id: ?Snowflake = null,
};

test "integration object retains an unknown type and optional account" {
    var parsed = try std.json.parseFromSlice(Integration, std.testing.allocator,
        \\{"id":"1","name":"Hook","type":"discord","enabled":true,"account":{"id":"2","name":"acct"},"application":{"id":"3","name":"app","icon":null,"description":"d"}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(IntegrationType.discord, parsed.value.type.known().?);
    try std.testing.expectEqualStrings("acct", parsed.value.account.name);
    try std.testing.expect(parsed.value.application.?.icon.isNull());

    var unknown = try std.json.parseFromSlice(Integration, std.testing.allocator,
        \\{"id":"1","name":"Hook","type":"future","enabled":false,"account":{"id":"2","name":"acct"}}
    , .{ .ignore_unknown_fields = true });
    defer unknown.deinit();
    try std.testing.expectEqual(@as(?IntegrationType, null), unknown.value.type.known());
    try std.testing.expectEqualStrings("future", unknown.value.type.raw);
}

test "integration delete carries the optional application id" {
    var parsed = try std.json.parseFromSlice(IntegrationDelete, std.testing.allocator,
        \\{"id":"1","guild_id":"2","application_id":"3"}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 3), parsed.value.application_id.?.toU64());
}

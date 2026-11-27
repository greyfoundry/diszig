//! Interaction wire models used by INTERACTION_CREATE.
//!
//! Batch 1 types the envelope. `data`, `message`, `entitlements` and
//! `authorizing_integration_owners` are action-specific and preserved as raw
//! JSON for the callback lifetime; MODEL-INTERACTIONS-* types them.
//!
//! `token` is an interaction continuation secret. It is retained only in the
//! per-callback arena and must not be logged or stored after the callback.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;
const shared = @import("shared.zig");
const channels = @import("channels.zig");
const guilds = @import("guilds.zig");

pub const InteractionType = enum(u8) {
    ping = 1,
    application_command = 2,
    message_component = 3,
    application_command_autocomplete = 4,
    modal_submit = 5,
};

pub const ContextType = enum(u8) {
    guild = 0,
    bot_dm = 1,
    private_channel = 2,
};

pub const Member = struct {
    user: shared.User,
    nick: json.Presence([]const u8) = .absent,
    roles: []Snowflake,
    joined_at: []const u8,
    premium_since: json.Presence([]const u8) = .absent,
    deaf: ?bool = null,
    mute: ?bool = null,
    flags: ?u64 = null,
    pending: ?bool = null,
    permissions: ?shared.PermissionBits = null,
};

pub const Interaction = struct {
    id: Snowflake,
    application_id: Snowflake,
    type: json.InboundEnum(InteractionType),
    data: ?std.json.Value = null,
    guild: ?guilds.Guild = null,
    guild_id: ?Snowflake = null,
    channel: ?channels.Channel = null,
    channel_id: ?Snowflake = null,
    member: ?Member = null,
    user: ?shared.User = null,
    token: []const u8,
    version: i64,
    message: ?std.json.Value = null,
    app_permissions: ?shared.PermissionBits = null,
    locale: ?[]const u8 = null,
    guild_locale: ?[]const u8 = null,
    entitlements: ?std.json.Value = null,
    authorizing_integration_owners: ?std.json.Value = null,
    context: ?json.InboundEnum(ContextType) = null,
    attachment_size_limit: ?i64 = null,
};

test "guild command interaction keeps raw data and typed member" {
    var parsed = try std.json.parseFromSlice(Interaction, std.testing.allocator,
        \\{"id":"1","application_id":"2","type":2,"guild_id":"3","channel_id":"4","member":{"user":{"id":"5","username":"u"},"roles":["6"],"joined_at":"2024-01-01T00:00:00+00:00"},"token":"tok","version":1,"app_permissions":"1024","data":{"id":"7","name":"cmd"},"context":0}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(InteractionType.application_command, parsed.value.type.known().?);
    try std.testing.expectEqual(@as(u64, 1024), parsed.value.app_permissions.?.bits);
    try std.testing.expectEqual(ContextType.guild, parsed.value.context.?.known().?);
    try std.testing.expect(parsed.value.data != null);
    try std.testing.expectEqualStrings("tok", parsed.value.token);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.member.?.roles.len);
}

test "DM interaction uses user and unknown types are retained" {
    var parsed = try std.json.parseFromSlice(Interaction, std.testing.allocator,
        \\{"id":"1","application_id":"2","type":99,"user":{"id":"3","username":"dm"},"token":"t","version":1}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?InteractionType, null), parsed.value.type.known());
    try std.testing.expectEqual(@as(i64, 99), parsed.value.type.raw.integer);
    try std.testing.expect(parsed.value.member == null);
    try std.testing.expectEqualStrings("dm", parsed.value.user.?.username);
}

test "the interaction token is required" {
    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(Interaction, std.testing.allocator,
            \\{"id":"1","application_id":"2","type":2,"version":1}
        , .{ .ignore_unknown_fields = true }),
    );
}

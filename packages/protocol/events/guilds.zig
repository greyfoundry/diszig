//! Guild wire models used by the guild Gateway events (batch 1).
//!
//! The guild object is a documented subset; roles, emojis, members, channels,
//! threads, presences and stickers are MODEL-GUILDS-* work. Unknown JSON fields
//! are ignored and unknown values that are not enumerated are retained raw.
//! `Presence` keeps an omitted update field distinct from an explicit null.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;

pub const User = @import("shared.zig").User;

pub const Guild = struct {
    id: Snowflake,
    name: json.Presence([]const u8) = .absent,
    icon: json.Presence([]const u8) = .absent,
    description: json.Presence([]const u8) = .absent,
    splash: json.Presence([]const u8) = .absent,
    owner_id: ?Snowflake = null,
    afk_channel_id: json.Presence(Snowflake) = .absent,
    afk_timeout: ?i64 = null,
    verification_level: ?i64 = null,
    default_message_notifications: ?i64 = null,
    explicit_content_filter: ?i64 = null,
    features: ?[]const []const u8 = null,
    mfa_level: ?i64 = null,
    application_id: json.Presence(Snowflake) = .absent,
    system_channel_id: json.Presence(Snowflake) = .absent,
    rules_channel_id: json.Presence(Snowflake) = .absent,
    public_updates_channel_id: json.Presence(Snowflake) = .absent,
    joined_at: json.Presence([]const u8) = .absent,
    large: ?bool = null,
    /// Present as `true` on an outage/removal payload; absent on a full guild.
    unavailable: ?bool = null,
    member_count: ?i64 = null,
    premium_tier: ?i64 = null,
    premium_subscription_count: ?i64 = null,
    preferred_locale: ?[]const u8 = null,
    nsfw_level: ?i64 = null,
    banner: json.Presence([]const u8) = .absent,
    vanity_url_code: json.Presence([]const u8) = .absent,
    premium_progress_bar_enabled: ?bool = null,
    safety_alerts_channel_id: json.Presence(Snowflake) = .absent,
    max_members: ?i64 = null,
    max_presences: ?i64 = null,
};

/// `changes` values are action-specific; batch 1 preserves them as raw JSON for
/// the callback lifetime instead of inventing per-action unions.
pub const AuditLogChange = struct {
    key: []const u8,
    new_value: ?std.json.Value = null,
    old_value: ?std.json.Value = null,
};

pub const AuditLogEntry = struct {
    id: Snowflake,
    action_type: i64,
    /// Extra field on the `GUILD_AUDIT_LOG_ENTRY_CREATE` event.
    guild_id: ?Snowflake = null,
    target_id: ?[]const u8 = null,
    user_id: ?Snowflake = null,
    changes: ?[]const AuditLogChange = null,
    options: ?std.json.Value = null,
    reason: ?[]const u8 = null,
};

pub const GuildBan = struct {
    guild_id: Snowflake,
    user: User,
};

test "full guild and unavailable guild share one model" {
    var parsed = try std.json.parseFromSlice(Guild, std.testing.allocator,
        \\{"id":"1","name":"Guild","icon":null,"owner_id":"2","features":["COMMUNITY"],"unavailable":false}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Guild", parsed.value.name.get().?);
    try std.testing.expect(parsed.value.icon.isNull());
    try std.testing.expectEqual(@as(usize, 1), parsed.value.features.?.len);

    var unavailable = try std.json.parseFromSlice(Guild, std.testing.allocator,
        \\{"id":"1","unavailable":true}
    , .{ .ignore_unknown_fields = true });
    defer unavailable.deinit();
    try std.testing.expect(unavailable.value.unavailable.?);
    try std.testing.expect(unavailable.value.name.isAbsent());
    try std.testing.expect(unavailable.value.features == null);
}

test "audit log entry preserves action-specific changes as raw JSON" {
    var parsed = try std.json.parseFromSlice(AuditLogEntry, std.testing.allocator,
        \\{"id":"1","action_type":20,"guild_id":"2","target_id":"3","user_id":"4","changes":[{"key":"name","old_value":"a","new_value":"b"}],"options":{"channel_id":"5"},"reason":"test"}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 20), parsed.value.action_type);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.changes.?.len);
    try std.testing.expectEqualStrings("name", parsed.value.changes.?[0].key);
    try std.testing.expect(parsed.value.options != null);
}

test "ban payload includes the user subset" {
    var parsed = try std.json.parseFromSlice(GuildBan, std.testing.allocator,
        \\{"guild_id":"1","user":{"id":"2","username":"banned","bot":false}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("banned", parsed.value.user.username);
    try std.testing.expectEqual(@as(?bool, false), parsed.value.user.bot);
}

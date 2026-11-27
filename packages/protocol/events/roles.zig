//! Role wire models used by the role Gateway events.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;

/// Gradient colours. `primary_color` is always present and mirrors the
/// deprecated integer `color` field.
pub const RoleColors = struct {
    primary_color: i64,
    secondary_color: ?i64 = null,
    tertiary_color: ?i64 = null,
};

/// Wire flags whose "true" form is a JSON null and whose "false" form is an
/// absent field, as documented for role tags.
pub const NullFlag = enum {
    absent,
    present,

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !NullFlag {
        _ = allocator;
        _ = options;
        if (try source.peekNextTokenType() != .null) return error.UnexpectedToken;
        _ = try source.next();
        return .present;
    }

    pub fn isPresent(self: NullFlag) bool {
        return self == .present;
    }
};

/// Tags with a null value mean "true"; absent means false.
pub const RoleTags = struct {
    bot_id: ?Snowflake = null,
    integration_id: ?Snowflake = null,
    premium_subscriber: NullFlag = .absent,
    subscription_listing_id: ?Snowflake = null,
    available_for_purchase: NullFlag = .absent,
    guild_connections: NullFlag = .absent,
};

pub const Role = struct {
    id: Snowflake,
    name: []const u8,
    /// Deprecated integer colour; `colors` is authoritative.
    color: i64,
    colors: RoleColors,
    hoist: bool,
    icon: json.Presence([]const u8) = .absent,
    unicode_emoji: json.Presence([]const u8) = .absent,
    position: i64,
    /// Permission bit set as a decimal string.
    permissions: []const u8,
    managed: bool,
    mentionable: bool,
    tags: ?RoleTags = null,
    flags: i64,
};

pub const RoleCreate = struct {
    guild_id: Snowflake,
    role: Role,
};

pub const RoleUpdate = struct {
    guild_id: Snowflake,
    role: Role,
};

pub const RoleDelete = struct {
    guild_id: Snowflake,
    role_id: Snowflake,
};

test "role create parses colours and null tags" {
    var parsed = try std.json.parseFromSlice(RoleCreate, std.testing.allocator,
        \\{"guild_id":"1","role":{"id":"2","name":"Moderator","color":16711680,"colors":{"primary_color":16711680,"secondary_color":null,"tertiary_color":null},"hoist":true,"icon":null,"unicode_emoji":null,"position":3,"permissions":"8","managed":false,"mentionable":true,"flags":0,"tags":{"premium_subscriber":null,"bot_id":"3"}}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("Moderator", parsed.value.role.name);
    try std.testing.expectEqual(@as(i64, 16711680), parsed.value.role.colors.primary_color);
    try std.testing.expect(parsed.value.role.icon.isNull());
    try std.testing.expect(parsed.value.role.tags.?.premium_subscriber.isPresent());
    try std.testing.expect(!parsed.value.role.tags.?.available_for_purchase.isPresent());
    try std.testing.expect(parsed.value.role.tags.?.bot_id != null);
}

test "role update and delete carry their documented fields" {
    var updated = try std.json.parseFromSlice(RoleUpdate, std.testing.allocator,
        \\{"guild_id":"1","role":{"id":"2","name":"Renamed","color":0,"colors":{"primary_color":0},"hoist":false,"position":0,"permissions":"0","managed":false,"mentionable":false,"flags":0}}
    , .{ .ignore_unknown_fields = true });
    defer updated.deinit();
    try std.testing.expectEqualStrings("Renamed", updated.value.role.name);
    try std.testing.expectEqual(@as(?i64, null), updated.value.role.colors.secondary_color);

    var deleted = try std.json.parseFromSlice(RoleDelete, std.testing.allocator,
        \\{"guild_id":"1","role_id":"2"}
    , .{ .ignore_unknown_fields = true });
    defer deleted.deinit();
    try std.testing.expectEqual(@as(u64, 2), deleted.value.role_id.toU64());
}

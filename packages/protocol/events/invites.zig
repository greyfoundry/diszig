//! Invite wire models used by the invite Gateway events.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;
const shared = @import("shared.zig");

pub const TargetType = enum(u8) {
    stream = 1,
    embedded_application = 2,
};

pub const InviteCreate = struct {
    channel_id: Snowflake,
    code: []const u8,
    created_at: []const u8,
    guild_id: ?Snowflake = null,
    inviter: ?shared.User = null,
    max_age: i64,
    max_uses: i64,
    target_type: ?json.InboundEnum(TargetType) = null,
    target_user: ?shared.User = null,
    /// Partial application object; raw for batch 1.
    target_application: ?std.json.Value = null,
    temporary: bool,
    uses: i64,
    expires_at: json.Presence([]const u8) = .absent,
    role_ids: ?[]Snowflake = null,
};

pub const InviteDelete = struct {
    channel_id: Snowflake,
    guild_id: ?Snowflake = null,
    code: []const u8,
};

test "invite create requires the documented fields" {
    var parsed = try std.json.parseFromSlice(InviteCreate, std.testing.allocator,
        \\{"channel_id":"1","code":"abc","created_at":"2024-01-01T00:00:00+00:00","guild_id":"2","inviter":{"id":"3","username":"u"},"max_age":3600,"max_uses":0,"temporary":false,"uses":0,"expires_at":null,"role_ids":["4"]}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("abc", parsed.value.code);
    try std.testing.expect(parsed.value.expires_at.isNull());
    try std.testing.expectEqual(@as(usize, 1), parsed.value.role_ids.?.len);
}

test "unknown invite target type is retained" {
    var parsed = try std.json.parseFromSlice(InviteCreate, std.testing.allocator,
        \\{"channel_id":"1","code":"abc","created_at":"2024-01-01T00:00:00+00:00","max_age":0,"max_uses":0,"temporary":true,"uses":0,"target_type":9}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?TargetType, null), parsed.value.target_type.?.known());
    try std.testing.expectEqual(@as(i64, 9), parsed.value.target_type.?.raw.integer);
}

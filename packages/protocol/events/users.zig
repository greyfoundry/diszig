//! User/presence wire models used by the user Gateway events.

const std = @import("std");
const Snowflake = @import("../snowflake.zig").Snowflake;
const shared = @import("shared.zig");

/// `PRESENCE_UPDATE.user` can be partial and its field types are explicitly not
/// validated by Discord, so the user, activities and client status stay raw in
/// this batch. Status strings are open-ended for forward compatibility.
pub const PresenceUpdate = struct {
    user: std.json.Value,
    guild_id: Snowflake,
    status: []const u8,
    activities: []std.json.Value,
    client_status: std.json.Value,
};

pub const TypingStart = struct {
    channel_id: Snowflake,
    guild_id: ?Snowflake = null,
    user_id: Snowflake,
    timestamp: i64,
    /// Guild member payload; raw in this batch.
    member: ?std.json.Value = null,
};

pub const UserUpdate = shared.User;

test "presence update keeps the partial user raw" {
    var parsed = try std.json.parseFromSlice(PresenceUpdate, std.testing.allocator,
        \\{"user":{"id":"1"},"guild_id":"2","status":"online","activities":[{"name":"Spotify","type":2,"created_at":0}],"client_status":{"desktop":"online"}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("online", parsed.value.status);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.activities.len);
    try std.testing.expect(parsed.value.user == .object);
}

test "typing start and user update parse" {
    var typing = try std.json.parseFromSlice(TypingStart, std.testing.allocator,
        \\{"channel_id":"1","guild_id":"2","user_id":"3","timestamp":1700000000}
    , .{ .ignore_unknown_fields = true });
    defer typing.deinit();
    try std.testing.expectEqual(@as(i64, 1700000000), typing.value.timestamp);

    var user = try std.json.parseFromSlice(UserUpdate, std.testing.allocator,
        \\{"id":"1","username":"renamed","global_name":"Name"}
    , .{ .ignore_unknown_fields = true });
    defer user.deinit();
    try std.testing.expectEqualStrings("renamed", user.value.username);
}

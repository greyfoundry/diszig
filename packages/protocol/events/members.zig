//! Guild member wire models used by the member Gateway events.

const std = @import("std");
const Snowflake = @import("../snowflake.zig").Snowflake;
const shared = @import("shared.zig");

/// GUILD_MEMBER_ADD/UPDATE carry the member fields inline with an extra guild_id.
/// The gateway decoder parses the flat payload into this pair.
pub const MemberEvent = struct {
    guild_id: Snowflake,
    member: shared.Member,
};

pub const MemberRemove = struct {
    guild_id: Snowflake,
    user: shared.User,
};

pub const MembersChunk = struct {
    guild_id: Snowflake,
    members: []shared.Member,
    chunk_index: i64,
    chunk_count: i64,
    not_found: ?[]Snowflake = null,
    /// Presence objects are raw for batch 1.
    presences: ?std.json.Value = null,
    nonce: ?[]const u8 = null,
};

test "member remove and chunk parse" {
    var parsed = try std.json.parseFromSlice(MemberRemove, std.testing.allocator,
        \\{"guild_id":"1","user":{"id":"2","username":"u"}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("u", parsed.value.user.username);

    var chunk = try std.json.parseFromSlice(MembersChunk, std.testing.allocator,
        \\{"guild_id":"1","members":[{"user":{"id":"2","username":"u"},"roles":["3"],"joined_at":"2024-01-01T00:00:00+00:00","deaf":false,"mute":false,"flags":0}],"chunk_index":0,"chunk_count":1,"not_found":["4"],"nonce":"n"}
    , .{ .ignore_unknown_fields = true });
    defer chunk.deinit();
    try std.testing.expectEqual(@as(usize, 1), chunk.value.members.len);
    try std.testing.expectEqualStrings("n", chunk.value.nonce.?);
}

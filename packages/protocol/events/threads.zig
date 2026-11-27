//! Thread wire models used by the thread Gateway events.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;
const channels = @import("channels.zig");

pub const Channel = channels.Channel;
pub const ChannelType = channels.ChannelType;
pub const ThreadMetadata = channels.ThreadMetadata;
pub const Overwrite = channels.Overwrite;

/// Thread member as documented. `id`/`user_id` are omitted in some contexts;
/// the guild member and presence payloads remain raw in this batch.
pub const ThreadMember = struct {
    id: ?Snowflake = null,
    user_id: ?Snowflake = null,
    join_timestamp: []const u8,
    flags: i64,
    member: ?std.json.Value = null,
    presence: ?std.json.Value = null,
};

/// `THREAD_CREATE` is the channel object plus `newly_created` and an optional
/// thread member. The channel fields are duplicated because the payload is flat.
pub const ThreadCreate = struct {
    id: Snowflake,
    type: json.InboundEnum(ChannelType),
    guild_id: ?Snowflake = null,
    parent_id: json.Presence(Snowflake) = .absent,
    owner_id: ?Snowflake = null,
    name: json.Presence([]const u8) = .absent,
    last_message_id: json.Presence(Snowflake) = .absent,
    rate_limit_per_user: ?i64 = null,
    thread_metadata: ?ThreadMetadata = null,
    message_count: ?i64 = null,
    member_count: ?i64 = null,
    total_message_sent: ?i64 = null,
    flags: ?u64 = null,
    newly_created: ?bool = null,
    member: ?ThreadMember = null,
};

pub const ThreadDelete = struct {
    id: Snowflake,
    guild_id: Snowflake,
    parent_id: ?Snowflake = null,
    type: json.InboundEnum(ChannelType),
};

pub const ThreadListSync = struct {
    guild_id: Snowflake,
    /// Omitted means every channel in the guild was synced.
    channel_ids: ?[]Snowflake = null,
    threads: []Channel,
    members: []ThreadMember,
};

pub const ThreadMemberUpdate = struct {
    guild_id: Snowflake,
    id: ?Snowflake = null,
    user_id: ?Snowflake = null,
    join_timestamp: []const u8,
    flags: i64,
    member: ?std.json.Value = null,
    presence: ?std.json.Value = null,
};

pub const ThreadMembersUpdate = struct {
    id: Snowflake,
    guild_id: Snowflake,
    member_count: i64,
    added_members: ?[]ThreadMember = null,
    removed_member_ids: ?[]Snowflake = null,
};

test "thread create parses flat channel fields and extras" {
    var parsed = try std.json.parseFromSlice(ThreadCreate, std.testing.allocator,
        \\{"id":"1","type":11,"guild_id":"2","parent_id":"3","owner_id":"4","name":"thread","thread_metadata":{"archived":false,"auto_archive_duration":1440,"archive_timestamp":"2024-01-01T00:00:00+00:00"},"newly_created":true,"member":{"id":"1","user_id":"4","join_timestamp":"2024-01-01T00:00:00+00:00","flags":0}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("thread", parsed.value.name.get().?);
    try std.testing.expect(parsed.value.newly_created.?);
    try std.testing.expectEqual(@as(u64, 4), parsed.value.member.?.user_id.?.toU64());
}

test "thread list sync and members update parse bounded arrays" {
    var sync = try std.json.parseFromSlice(ThreadListSync, std.testing.allocator,
        \\{"guild_id":"1","channel_ids":["2","3"],"threads":[{"id":"4","type":11}],"members":[{"id":"4","user_id":"5","join_timestamp":"2024-01-01T00:00:00+00:00","flags":1}]}
    , .{ .ignore_unknown_fields = true });
    defer sync.deinit();
    try std.testing.expectEqual(@as(usize, 2), sync.value.channel_ids.?.len);
    try std.testing.expectEqual(@as(usize, 1), sync.value.members.len);

    var update = try std.json.parseFromSlice(ThreadMembersUpdate, std.testing.allocator,
        \\{"id":"1","guild_id":"2","member_count":3,"added_members":[{"id":"1","user_id":"4","join_timestamp":"2024-01-01T00:00:00+00:00","flags":0}],"removed_member_ids":["5"]}
    , .{ .ignore_unknown_fields = true });
    defer update.deinit();
    try std.testing.expectEqual(@as(i64, 3), update.value.member_count);
    try std.testing.expectEqual(@as(usize, 1), update.value.removed_member_ids.?.len);
}

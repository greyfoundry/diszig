//! Channel wire models used by the channel Gateway events.
//!
//! This is the batch-1 subset. Unknown JSON fields are ignored by the parser;
//! unknown enum values are retained through `InboundEnum` instead of failing the
//! whole dispatch. Nullable fields use `Presence` so an omitted update field is
//! distinct from an explicit `null` clear.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;

pub const ChannelType = enum(u8) {
    text = 0,
    dm = 1,
    voice = 2,
    group_dm = 3,
    category = 4,
    announcement = 5,
    announcement_thread = 10,
    public_thread = 11,
    private_thread = 12,
    stage_voice = 13,
    directory = 14,
    forum = 15,
    media = 16,
};

pub const OverwriteType = enum(u8) {
    role = 0,
    member = 1,
};

/// Permission bitfields arrive as decimal strings.
pub const PermissionBits = struct {
    bits: u64,

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        const text = try std.json.innerParse([]const u8, allocator, source, options);
        return .{ .bits = try std.fmt.parseInt(u64, text, 10) };
    }
};

pub const Overwrite = struct {
    id: Snowflake,
    type: json.InboundEnum(OverwriteType),
    allow: PermissionBits,
    deny: PermissionBits,
};

pub const ThreadMetadata = struct {
    archived: bool,
    auto_archive_duration: i64,
    archive_timestamp: []const u8,
    locked: bool = false,
    invitable: ?bool = null,
    create_timestamp: ?[]const u8 = null,
};

pub const Channel = struct {
    id: Snowflake,
    type: json.InboundEnum(ChannelType),
    guild_id: ?Snowflake = null,
    position: ?i64 = null,
    permission_overwrites: ?[]Overwrite = null,
    name: json.Presence([]const u8) = .absent,
    topic: json.Presence([]const u8) = .absent,
    nsfw: ?bool = null,
    last_message_id: json.Presence(Snowflake) = .absent,
    bitrate: ?i64 = null,
    user_limit: ?i64 = null,
    rate_limit_per_user: ?i64 = null,
    parent_id: json.Presence(Snowflake) = .absent,
    last_pin_timestamp: json.Presence([]const u8) = .absent,
    flags: ?u64 = null,
    message_count: ?i64 = null,
    member_count: ?i64 = null,
    default_auto_archive_duration: ?i64 = null,
    thread_metadata: ?ThreadMetadata = null,
};

pub const ChannelInfoEntry = struct {
    id: Snowflake,
    status: json.Presence([]const u8) = .absent,
    voice_start_time: json.Presence(i64) = .absent,
};

pub const ChannelInfo = struct {
    guild_id: Snowflake,
    channels: []ChannelInfoEntry,
};

pub const ChannelPinsUpdate = struct {
    guild_id: ?Snowflake = null,
    channel_id: Snowflake,
    last_pin_timestamp: json.Presence([]const u8) = .absent,
};

test "minimal channel parses with absent nullable fields" {
    var parsed = try std.json.parseFromSlice(Channel, std.testing.allocator,
        \\{"id":"1","type":0,"guild_id":"2","name":"general","position":3}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqual(ChannelType.text, parsed.value.type.known().?);
    try std.testing.expectEqual(@as(?u64, 2), if (parsed.value.guild_id) |id| id.toU64() else null);
    try std.testing.expectEqualStrings("general", parsed.value.name.get().?);
    try std.testing.expect(parsed.value.topic.isAbsent());
    try std.testing.expect(parsed.value.parent_id.isAbsent());
}

test "explicit null and unknown enum are retained" {
    var parsed = try std.json.parseFromSlice(Channel, std.testing.allocator,
        \\{"id":"1","type":99,"name":null,"topic":"hello","parent_id":null}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(?ChannelType, null), parsed.value.type.known());
    try std.testing.expectEqual(@as(i64, 99), parsed.value.type.raw.integer);
    try std.testing.expect(parsed.value.name.isNull());
    try std.testing.expectEqualStrings("hello", parsed.value.topic.get().?);
    try std.testing.expect(parsed.value.parent_id.isNull());
}

test "permission overwrites parse stringified bitfields" {
    var parsed = try std.json.parseFromSlice(Channel, std.testing.allocator,
        \\{"id":"1","type":0,"permission_overwrites":[{"id":"2","type":0,"allow":"1024","deny":"2048"}]}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const overwrite = parsed.value.permission_overwrites.?[0];
    try std.testing.expectEqual(@as(u64, 1024), overwrite.allow.bits);
    try std.testing.expectEqual(@as(u64, 2048), overwrite.deny.bits);
    try std.testing.expectEqual(OverwriteType.role, overwrite.type.known().?);
}

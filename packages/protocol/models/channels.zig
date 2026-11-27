//! Channels wire contracts, dependency layer 0, batch 1.
//!
//! The pinned schema's `ChannelPermissionOverwrites` is the overwrite *type*
//! enum (role/member), not the overwrite object.

const std = @import("std");
const json = @import("../json.zig");

pub const ChannelPermissionOverwrites = enum(u8) {
    role = 0,
    member = 1,
};

pub const InboundChannelPermissionOverwrites = json.InboundEnum(ChannelPermissionOverwrites);

pub const ChannelTypes = enum(u8) {
    guild_text = 0,
    dm = 1,
    guild_voice = 2,
    group_dm = 3,
    guild_category = 4,
    guild_announcement = 5,
    announcement_thread = 10,
    public_thread = 11,
    private_thread = 12,
    guild_stage_voice = 13,
    guild_directory = 14,
    guild_forum = 15,
};

pub const InboundChannelTypes = json.InboundEnum(ChannelTypes);

pub const ForumLayout = enum(u8) {
    default = 0,
    list = 1,
    grid = 2,
};

pub const InboundForumLayout = json.InboundEnum(ForumLayout);

pub const ThreadAutoArchiveDuration = enum(u16) {
    one_hour = 60,
    one_day = 1440,
    three_day = 4320,
    seven_day = 10080,
};

pub const InboundThreadAutoArchiveDuration = json.InboundEnum(ThreadAutoArchiveDuration);

pub const ThreadSearchTagSetting = enum {
    match_all,
    match_some,
};

pub const InboundThreadSearchTagSetting = json.InboundStringEnum(ThreadSearchTagSetting);

pub const ThreadSortOrder = enum(u8) {
    latest_activity = 0,
    creation_date = 1,
};

pub const InboundThreadSortOrder = json.InboundEnum(ThreadSortOrder);

pub const ThreadSortingMode = enum {
    relevance,
    creation_time,
    last_message_time,
    archive_time,
};

pub const InboundThreadSortingMode = json.InboundStringEnum(ThreadSortingMode);

test "documented channel enum values" {
    try std.testing.expectEqual(@as(u8, 0), @backingInt(ChannelTypes.guild_text));
    try std.testing.expectEqual(@as(u8, 15), @backingInt(ChannelTypes.guild_forum));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(ChannelPermissionOverwrites.member));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(ForumLayout.grid));
    try std.testing.expectEqual(@as(u16, 10080), @backingInt(ThreadAutoArchiveDuration.seven_day));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(ThreadSortOrder.creation_date));
    try std.testing.expectEqualStrings("match_some", @tagName(ThreadSearchTagSetting.match_some));
    try std.testing.expectEqualStrings("archive_time", @tagName(ThreadSortingMode.archive_time));
}

test "unknown inbound channel enums are retained" {
    var integer = try std.json.parseFromSlice(InboundChannelTypes, std.testing.allocator, "99", .{});
    defer integer.deinit();
    try std.testing.expectEqual(@as(?ChannelTypes, null), integer.value.known());

    var string = try std.json.parseFromSlice(InboundThreadSortingMode, std.testing.allocator, "\"future_mode\"", .{});
    defer string.deinit();
    try std.testing.expectEqual(@as(?ThreadSortingMode, null), string.value.known());
    try std.testing.expectEqualStrings("future_mode", string.value.raw);
}

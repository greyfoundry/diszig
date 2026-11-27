//! Channels model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const channels = diszig.protocol.models.channels;

test "every listed schema is exported" {
    _ = channels.ChannelPermissionOverwrites;
    _ = channels.ChannelTypes;
    _ = channels.ForumLayout;
    _ = channels.ThreadAutoArchiveDuration;
    _ = channels.ThreadSearchTagSetting;
    _ = channels.ThreadSortOrder;
    _ = channels.ThreadSortingMode;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 0), @backingInt(channels.ChannelPermissionOverwrites.role));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(channels.ChannelPermissionOverwrites.member));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(channels.ChannelTypes.guild_text));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(channels.ChannelTypes.dm));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(channels.ChannelTypes.group_dm));
    try std.testing.expectEqual(@as(u8, 10), @backingInt(channels.ChannelTypes.announcement_thread));
    try std.testing.expectEqual(@as(u8, 12), @backingInt(channels.ChannelTypes.private_thread));
    try std.testing.expectEqual(@as(u8, 15), @backingInt(channels.ChannelTypes.guild_forum));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(channels.ForumLayout.grid));
    try std.testing.expectEqual(@as(u16, 60), @backingInt(channels.ThreadAutoArchiveDuration.one_hour));
    try std.testing.expectEqual(@as(u16, 10080), @backingInt(channels.ThreadAutoArchiveDuration.seven_day));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(channels.ThreadSortOrder.latest_activity));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(channels.ThreadSortOrder.creation_date));
    try std.testing.expectEqualStrings("match_all", @tagName(channels.ThreadSearchTagSetting.match_all));
    try std.testing.expectEqualStrings("creation_time", @tagName(channels.ThreadSortingMode.creation_time));
}

test "unknown inbound channel enums are retained" {
    var integer = try std.json.parseFromSlice(channels.InboundChannelTypes, std.testing.allocator, "99", .{});
    defer integer.deinit();
    try std.testing.expectEqual(@as(?channels.ChannelTypes, null), integer.value.known());
    try std.testing.expectEqual(@as(i64, 99), integer.value.raw.integer);

    var string = try std.json.parseFromSlice(channels.InboundThreadSearchTagSetting, std.testing.allocator, "\"future\"", .{});
    defer string.deinit();
    try std.testing.expectEqual(@as(?channels.ThreadSearchTagSetting, null), string.value.known());
    try std.testing.expectEqualStrings("future", string.value.raw);
}

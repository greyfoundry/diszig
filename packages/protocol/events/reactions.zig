//! Reaction wire models used by the reaction Gateway events.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;
const messages = @import("../models/messages.zig");

/// Partial emoji. Custom emoji carry an id and usually a name; standard emoji
/// carry only a name.
pub const Emoji = struct {
    id: ?Snowflake = null,
    name: ?[]const u8 = null,
    animated: ?bool = null,
};

pub const ReactionType = json.InboundEnum(messages.ReactionTypes);

pub const ReactionAdd = struct {
    user_id: Snowflake,
    channel_id: Snowflake,
    message_id: Snowflake,
    guild_id: ?Snowflake = null,
    /// Guild member payload; raw in this batch.
    member: ?std.json.Value = null,
    emoji: Emoji,
    message_author_id: ?Snowflake = null,
    burst: bool,
    burst_colors: ?[]const []const u8 = null,
    type: ReactionType,
};

pub const ReactionRemove = struct {
    user_id: Snowflake,
    channel_id: Snowflake,
    message_id: Snowflake,
    guild_id: ?Snowflake = null,
    emoji: Emoji,
    burst: bool,
    type: ReactionType,
};

pub const ReactionRemoveAll = struct {
    channel_id: Snowflake,
    message_id: Snowflake,
    guild_id: ?Snowflake = null,
};

pub const ReactionRemoveEmoji = struct {
    channel_id: Snowflake,
    guild_id: ?Snowflake = null,
    message_id: Snowflake,
    emoji: Emoji,
};

test "reaction events parse documented fields" {
    var add = try std.json.parseFromSlice(ReactionAdd, std.testing.allocator,
        \\{"user_id":"1","channel_id":"2","message_id":"3","guild_id":"4","emoji":{"id":"5","name":"wave","animated":false},"message_author_id":"6","burst":true,"burst_colors":["#ff0000"],"type":1}
    , .{ .ignore_unknown_fields = true });
    defer add.deinit();
    try std.testing.expect(add.value.burst);
    try std.testing.expectEqual(messages.ReactionTypes.burst, add.value.type.known().?);
    try std.testing.expectEqual(@as(usize, 1), add.value.burst_colors.?.len);

    var remove_emoji = try std.json.parseFromSlice(ReactionRemoveEmoji, std.testing.allocator,
        \\{"channel_id":"1","message_id":"2","emoji":{"name":"👍"}}
    , .{ .ignore_unknown_fields = true });
    defer remove_emoji.deinit();
    try std.testing.expectEqualStrings("👍", remove_emoji.value.emoji.name.?);
    try std.testing.expectEqual(@as(?Snowflake, null), remove_emoji.value.emoji.id);
}

test "unknown inbound reaction type is retained" {
    var parsed = try std.json.parseFromSlice(ReactionRemove, std.testing.allocator,
        \\{"user_id":"1","channel_id":"2","message_id":"3","emoji":{"name":"x"},"burst":false,"type":9}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?messages.ReactionTypes, null), parsed.value.type.known());
    try std.testing.expectEqual(@as(i64, 9), parsed.value.type.raw.integer);
}

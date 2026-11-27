//! Poll wire models used by the poll vote events.

const std = @import("std");
const Snowflake = @import("../snowflake.zig").Snowflake;

pub const PollVote = struct {
    user_id: Snowflake,
    channel_id: Snowflake,
    message_id: Snowflake,
    guild_id: ?Snowflake = null,
    /// Answer index within the poll.
    answer_id: i64,
};

pub const PollVoteAdd = PollVote;
pub const PollVoteRemove = PollVote;

test "poll vote parses the documented fields" {
    var parsed = try std.json.parseFromSlice(PollVote, std.testing.allocator,
        \\{"user_id":"1","channel_id":"2","message_id":"3","guild_id":"4","answer_id":0}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i64, 0), parsed.value.answer_id);
    try std.testing.expectEqual(@as(u64, 4), parsed.value.guild_id.?.toU64());

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(PollVote, std.testing.allocator,
            \\{"user_id":"1","channel_id":"2","message_id":"3"}
        , .{}),
    );
}

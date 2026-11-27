//! Poll Gateway event batch contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;

test "poll vote events decode through the dispatcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const added = try events.decode(
        arena.allocator(),
        "MESSAGE_POLL_VOTE_ADD",
        1,
        "{\"op\":0,\"t\":\"MESSAGE_POLL_VOTE_ADD\",\"s\":1,\"d\":{\"user_id\":\"1\",\"channel_id\":\"2\",\"message_id\":\"3\",\"answer_id\":2}}",
        1024,
    );
    try std.testing.expect(added == .poll_vote_add);
    try std.testing.expectEqual(@as(i64, 2), added.poll_vote_add.answer_id);

    const removed = try events.decode(
        arena.allocator(),
        "MESSAGE_POLL_VOTE_REMOVE",
        2,
        "{\"op\":0,\"t\":\"MESSAGE_POLL_VOTE_REMOVE\",\"s\":2,\"d\":{\"user_id\":\"1\",\"channel_id\":\"2\",\"message_id\":\"3\",\"guild_id\":\"4\",\"answer_id\":2}}",
        1024,
    );
    try std.testing.expect(removed == .poll_vote_remove);
    try std.testing.expect(removed.poll_vote_remove.guild_id != null);
}

test "unknown poll-like names stay raw" {
    const event = try events.decode(
        std.testing.allocator,
        "MESSAGE_POLL_FUTURE",
        3,
        "{\"op\":0,\"t\":\"MESSAGE_POLL_FUTURE\",\"s\":3,\"d\":{}}",
        512,
    );
    try std.testing.expect(event == .raw);
}

//! Reaction Gateway event batch contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;

test "reaction events decode through the dispatcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const added = try events.decode(
        arena.allocator(),
        "MESSAGE_REACTION_ADD",
        1,
        "{\"op\":0,\"t\":\"MESSAGE_REACTION_ADD\",\"s\":1,\"d\":{\"user_id\":\"1\",\"channel_id\":\"2\",\"message_id\":\"3\",\"emoji\":{\"name\":\"wave\"},\"burst\":false,\"type\":0}}",
        2048,
    );
    try std.testing.expect(added == .message_reaction_add);
    try std.testing.expectEqualStrings("wave", added.message_reaction_add.emoji.name.?);

    const removed = try events.decode(
        arena.allocator(),
        "MESSAGE_REACTION_REMOVE_EMOJI",
        2,
        "{\"op\":0,\"t\":\"MESSAGE_REACTION_REMOVE_EMOJI\",\"s\":2,\"d\":{\"channel_id\":\"2\",\"message_id\":\"3\",\"emoji\":{\"id\":\"4\",\"name\":\"wave\"}}}",
        2048,
    );
    try std.testing.expect(removed == .message_reaction_remove_emoji);
    try std.testing.expect(removed.message_reaction_remove_emoji.emoji.id != null);
}

test "unknown reaction-like names stay raw" {
    const event = try events.decode(
        std.testing.allocator,
        "MESSAGE_REACTION_FUTURE",
        3,
        "{\"op\":0,\"t\":\"MESSAGE_REACTION_FUTURE\",\"s\":3,\"d\":{}}",
        1024,
    );
    try std.testing.expect(event == .raw);
}

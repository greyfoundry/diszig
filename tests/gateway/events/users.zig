//! User/presence Gateway event batch contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;

test "presence, typing and user update decode through the dispatcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const presence = try events.decode(
        arena.allocator(),
        "PRESENCE_UPDATE",
        1,
        "{\"op\":0,\"t\":\"PRESENCE_UPDATE\",\"s\":1,\"d\":{\"user\":{\"id\":\"1\"},\"guild_id\":\"2\",\"status\":\"dnd\",\"activities\":[{\"name\":\"x\"}],\"client_status\":{\"web\":\"dnd\"}}}",
        2048,
    );
    try std.testing.expect(presence == .presence_update);
    try std.testing.expectEqualStrings("dnd", presence.presence_update.status);
    try std.testing.expectEqual(@as(usize, 1), presence.presence_update.activities.len);

    const typing = try events.decode(
        arena.allocator(),
        "TYPING_START",
        2,
        "{\"op\":0,\"t\":\"TYPING_START\",\"s\":2,\"d\":{\"channel_id\":\"1\",\"user_id\":\"2\",\"timestamp\":1}}",
        1024,
    );
    try std.testing.expect(typing == .typing_start);

    const updated = try events.decode(
        arena.allocator(),
        "USER_UPDATE",
        3,
        "{\"op\":0,\"t\":\"USER_UPDATE\",\"s\":3,\"d\":{\"id\":\"1\",\"username\":\"new-name\"}}",
        1024,
    );
    try std.testing.expect(updated == .user_update);
    try std.testing.expectEqualStrings("new-name", updated.user_update.username);
}

test "unknown user-like names stay raw" {
    const event = try events.decode(
        std.testing.allocator,
        "PRESENCE_FUTURE",
        4,
        "{\"op\":0,\"t\":\"PRESENCE_FUTURE\",\"s\":4,\"d\":{}}",
        512,
    );
    try std.testing.expect(event == .raw);
}

//! Thread Gateway event batch contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;

test "thread events decode through the dispatcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const created = try events.decode(
        arena.allocator(),
        "THREAD_CREATE",
        1,
        "{\"op\":0,\"t\":\"THREAD_CREATE\",\"s\":1,\"d\":{\"id\":\"1\",\"type\":11,\"guild_id\":\"2\",\"parent_id\":\"3\",\"name\":\"t\",\"newly_created\":true}}",
        2048,
    );
    try std.testing.expect(created == .thread_create);
    try std.testing.expect(created.thread_create.newly_created.?);

    const updated = try events.decode(
        arena.allocator(),
        "THREAD_UPDATE",
        2,
        "{\"op\":0,\"t\":\"THREAD_UPDATE\",\"s\":2,\"d\":{\"id\":\"1\",\"type\":11,\"guild_id\":\"2\",\"name\":\"renamed\"}}",
        2048,
    );
    try std.testing.expect(updated == .thread_update);
    try std.testing.expectEqualStrings("renamed", updated.thread_update.name.get().?);

    const synced = try events.decode(
        arena.allocator(),
        "THREAD_LIST_SYNC",
        3,
        "{\"op\":0,\"t\":\"THREAD_LIST_SYNC\",\"s\":3,\"d\":{\"guild_id\":\"1\",\"threads\":[{\"id\":\"2\",\"type\":11}],\"members\":[{\"id\":\"2\",\"user_id\":\"3\",\"join_timestamp\":\"2024-01-01T00:00:00+00:00\",\"flags\":0}]}}",
        2048,
    );
    try std.testing.expect(synced == .thread_list_sync);
    try std.testing.expectEqual(@as(usize, 1), synced.thread_list_sync.threads.len);
}

test "unknown thread-like names stay raw" {
    const event = try events.decode(
        std.testing.allocator,
        "THREAD_FUTURE",
        4,
        "{\"op\":0,\"t\":\"THREAD_FUTURE\",\"s\":4,\"d\":{}}",
        1024,
    );
    try std.testing.expect(event == .raw);
}

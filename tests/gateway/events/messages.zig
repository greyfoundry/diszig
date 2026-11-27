//! Message Gateway event contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;
const models = diszig.protocol.events.messages;

fn parse(allocator: std.mem.Allocator, name: []const u8, envelope: []const u8) !events.Event {
    return events.decode(allocator, name, 1, envelope, 16384);
}

test "message create is typed with author and attachment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "MESSAGE_CREATE",
        "{\"op\":0,\"t\":\"MESSAGE_CREATE\",\"d\":{\"id\":\"1\",\"channel_id\":\"2\",\"guild_id\":\"3\",\"author\":{\"id\":\"4\",\"username\":\"u\"},\"content\":\"hi\",\"timestamp\":\"2024-01-01T00:00:00+00:00\",\"type\":0,\"pinned\":false,\"attachments\":[{\"id\":\"5\",\"filename\":\"a.txt\",\"size\":3,\"url\":\"https://x\",\"proxy_url\":\"https://p\"}]}}",
    );
    try std.testing.expect(event == .message_create);
    const message = event.message_create;
    try std.testing.expectEqualStrings("hi", message.content.get().?);
    try std.testing.expectEqualStrings("u", message.author.?.username);
    try std.testing.expectEqual(@as(usize, 1), message.attachments.?.len);
}

test "message update is a partial message" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "MESSAGE_UPDATE",
        "{\"op\":0,\"t\":\"MESSAGE_UPDATE\",\"d\":{\"id\":\"1\",\"content\":\"edited\"}}",
    );
    try std.testing.expect(event == .message_update);
    try std.testing.expectEqualStrings("edited", event.message_update.content.get().?);
    try std.testing.expect(event.message_update.author == null);
    try std.testing.expect(event.message_update.attachments == null);
}

test "message delete and bulk delete" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const deleted = try parse(
        arena.allocator(),
        "MESSAGE_DELETE",
        "{\"op\":0,\"t\":\"MESSAGE_DELETE\",\"d\":{\"id\":\"1\",\"channel_id\":\"2\"}}",
    );
    try std.testing.expect(deleted == .message_delete);
    try std.testing.expect(deleted.message_delete.guild_id == null);

    const bulk = try parse(
        arena.allocator(),
        "MESSAGE_DELETE_BULK",
        "{\"op\":0,\"t\":\"MESSAGE_DELETE_BULK\",\"d\":{\"ids\":[\"1\",\"2\"],\"channel_id\":\"3\",\"guild_id\":\"4\"}}",
    );
    try std.testing.expect(bulk == .message_delete_bulk);
    try std.testing.expectEqual(@as(usize, 2), bulk.message_delete_bulk.ids.len);
}

test "unknown message type is retained" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const event = try parse(
        arena.allocator(),
        "MESSAGE_CREATE",
        "{\"op\":0,\"t\":\"MESSAGE_CREATE\",\"d\":{\"id\":\"1\",\"type\":250}}",
    );
    try std.testing.expectEqual(@as(?models.MessageType, null), event.message_create.type.?.known());
    try std.testing.expectEqual(@as(i64, 250), event.message_create.type.?.raw.integer);
}

test "unrelated events still fall back to raw" {
    const event = try parse(
        std.testing.allocator,
        "GUILD_ROLE_FUTURE",
        "{\"op\":0,\"t\":\"GUILD_ROLE_FUTURE\",\"d\":{\"guild_id\":\"1\"}}",
    );
    try std.testing.expect(event == .raw);
}

fn parseWithArena(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try parse(arena.allocator(), "MESSAGE_CREATE", envelope);
    try std.testing.expect(event == .message_create);
}

test "allocation failure while decoding is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseWithArena,
        .{"{\"op\":0,\"d\":{\"id\":\"1\",\"channel_id\":\"2\",\"author\":{\"id\":\"3\",\"username\":\"u\"},\"content\":\"hi\",\"timestamp\":\"2024-01-01T00:00:00+00:00\",\"mentions\":[{\"id\":\"4\",\"username\":\"m\"}],\"attachments\":[{\"id\":\"5\",\"filename\":\"a\",\"size\":1,\"url\":\"u\",\"proxy_url\":\"p\"}]}}"},
    );
}

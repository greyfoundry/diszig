//! Channel Gateway event contracts: typed values, partial updates, explicit
//! nulls, unknown enums, raw fallback and allocation-failure cleanup.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;
const channels = diszig.protocol.events.channels;

fn parse(allocator: std.mem.Allocator, name: []const u8, envelope: []const u8) !events.Event {
    return events.decode(allocator, name, 1, envelope, 4096);
}

test "minimal channel create keeps absent fields absent" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "CHANNEL_CREATE",
        "{\"op\":0,\"t\":\"CHANNEL_CREATE\",\"s\":1,\"d\":{\"id\":\"1\",\"type\":0,\"guild_id\":\"2\",\"name\":\"general\"}}",
    );
    try std.testing.expect(event == .channel_create);
    const channel = event.channel_create;
    try std.testing.expectEqual(@as(u64, 1), channel.id.toU64());
    try std.testing.expectEqual(channels.ChannelType.text, channel.type.known().?);
    try std.testing.expectEqualStrings("general", channel.name.get().?);
    try std.testing.expect(channel.topic.isAbsent());
    try std.testing.expect(channel.parent_id.isAbsent());
}

test "partial update does not clear missing fields and explicit null clears" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const partial = try parse(
        arena.allocator(),
        "CHANNEL_UPDATE",
        "{\"op\":0,\"t\":\"CHANNEL_UPDATE\",\"s\":2,\"d\":{\"id\":\"1\",\"type\":0}}",
    );
    try std.testing.expect(partial == .channel_update);
    try std.testing.expect(partial.channel_update.name.isAbsent());
    try std.testing.expect(partial.channel_update.topic.isAbsent());
    try std.testing.expect(partial.channel_update.parent_id.isAbsent());

    const cleared = try parse(
        arena.allocator(),
        "CHANNEL_UPDATE",
        "{\"op\":0,\"t\":\"CHANNEL_UPDATE\",\"s\":3,\"d\":{\"id\":\"1\",\"type\":0,\"name\":null,\"parent_id\":null}}",
    );
    try std.testing.expect(cleared.channel_update.name.isNull());
    try std.testing.expect(cleared.channel_update.parent_id.isNull());
}

test "privileged or thread-only data absent is an explicit partial state" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "CHANNEL_UPDATE",
        "{\"op\":0,\"t\":\"CHANNEL_UPDATE\",\"d\":{\"id\":\"1\",\"type\":11}}",
    );
    try std.testing.expectEqual(channels.ChannelType.public_thread, event.channel_update.type.known().?);
    try std.testing.expectEqual(@as(?i64, null), event.channel_update.member_count);
    try std.testing.expectEqual(@as(?i64, null), event.channel_update.message_count);
    try std.testing.expect(event.channel_update.thread_metadata == null);
}

test "unknown channel type is retained instead of failing the event" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "CHANNEL_DELETE",
        "{\"op\":0,\"t\":\"CHANNEL_DELETE\",\"d\":{\"id\":\"1\",\"type\":250,\"future\":true}}",
    );
    try std.testing.expect(event == .channel_delete);
    try std.testing.expectEqual(@as(?channels.ChannelType, null), event.channel_delete.type.known());
    try std.testing.expectEqual(@as(i64, 250), event.channel_delete.type.raw.integer);
}

test "channel info and pins update are typed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const info = try parse(
        arena.allocator(),
        "CHANNEL_INFO",
        "{\"op\":0,\"t\":\"CHANNEL_INFO\",\"d\":{\"guild_id\":\"2\",\"channels\":[{\"id\":\"1\",\"status\":null},{\"id\":\"3\",\"voice_start_time\":1700000000}]}}",
    );
    try std.testing.expect(info == .channel_info);
    try std.testing.expect(info.channel_info.channels[0].status.isNull());
    try std.testing.expect(info.channel_info.channels[0].voice_start_time.isAbsent());

    const pins = try parse(
        arena.allocator(),
        "CHANNEL_PINS_UPDATE",
        "{\"op\":0,\"t\":\"CHANNEL_PINS_UPDATE\",\"d\":{\"channel_id\":\"1\",\"last_pin_timestamp\":null}}",
    );
    try std.testing.expect(pins == .channel_pins_update);
    try std.testing.expect(pins.channel_pins_update.guild_id == null);
    try std.testing.expect(pins.channel_pins_update.last_pin_timestamp.isNull());
}

test "an unrelated event still falls back to raw" {
    const event = try parse(
        std.testing.allocator,
        "MESSAGE_CREATE",
        "{\"op\":0,\"t\":\"MESSAGE_CREATE\",\"d\":{\"id\":\"1\"}}",
    );
    try std.testing.expect(event == .raw);
    try std.testing.expectEqualStrings("MESSAGE_CREATE", event.raw.name);
}

fn parseWithArena(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try parse(arena.allocator(), "CHANNEL_CREATE", envelope);
    try std.testing.expect(event == .channel_create);
}

test "allocation failure while decoding is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseWithArena,
        .{"{\"op\":0,\"t\":\"CHANNEL_CREATE\",\"d\":{\"id\":\"1\",\"type\":0,\"name\":\"general\",\"permission_overwrites\":[{\"id\":\"2\",\"type\":0,\"allow\":\"1\",\"deny\":\"2\"}]}}"},
    );
}

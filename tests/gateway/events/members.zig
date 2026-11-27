//! Guild member Gateway event contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;

fn parse(allocator: std.mem.Allocator, name: []const u8, envelope: []const u8) !events.Event {
    return events.decode(allocator, name, 1, envelope, 8192);
}

test "member add and update keep member fields typed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const added = try parse(
        arena.allocator(),
        "GUILD_MEMBER_ADD",
        "{\"op\":0,\"t\":\"GUILD_MEMBER_ADD\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\",\"bot\":false},\"roles\":[\"3\"],\"joined_at\":\"2024-01-01T00:00:00+00:00\",\"deaf\":false,\"mute\":true,\"flags\":0}}",
    );
    try std.testing.expect(added == .guild_member_add);
    try std.testing.expectEqualStrings("u", added.guild_member_add.member.user.?.username);
    try std.testing.expectEqual(@as(usize, 1), added.guild_member_add.member.roles.len);
    try std.testing.expect(added.guild_member_add.member.mute);

    const updated = try parse(
        arena.allocator(),
        "GUILD_MEMBER_UPDATE",
        "{\"op\":0,\"t\":\"GUILD_MEMBER_UPDATE\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"},\"roles\":[],\"nick\":null,\"joined_at\":\"2024-01-01T00:00:00+00:00\",\"deaf\":false,\"mute\":false,\"flags\":0}}",
    );
    try std.testing.expect(updated == .guild_member_update);
    try std.testing.expect(updated.guild_member_update.member.nick.isNull());
    try std.testing.expect(updated.guild_member_update.member.premium_since.isAbsent());
}

test "member remove and chunk decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const removed = try parse(
        arena.allocator(),
        "GUILD_MEMBER_REMOVE",
        "{\"op\":0,\"t\":\"GUILD_MEMBER_REMOVE\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"}}}",
    );
    try std.testing.expect(removed == .guild_member_remove);

    const chunk = try parse(
        arena.allocator(),
        "GUILD_MEMBERS_CHUNK",
        "{\"op\":0,\"t\":\"GUILD_MEMBERS_CHUNK\",\"d\":{\"guild_id\":\"1\",\"members\":[{\"user\":{\"id\":\"2\",\"username\":\"u\"},\"roles\":[],\"joined_at\":null,\"deaf\":false,\"mute\":false,\"flags\":0}],\"chunk_index\":0,\"chunk_count\":2,\"not_found\":[\"9\"],\"nonce\":\"req\"}}",
    );
    try std.testing.expect(chunk == .guild_members_chunk);
    try std.testing.expectEqual(@as(i64, 2), chunk.guild_members_chunk.chunk_count);
    try std.testing.expectEqualStrings("req", chunk.guild_members_chunk.nonce.?);
}

test "unrelated events still fall back to raw" {
    const event = try parse(
        std.testing.allocator,
        "GUILD_ROLE_CREATE",
        "{\"op\":0,\"t\":\"GUILD_ROLE_CREATE\",\"d\":{\"guild_id\":\"1\"}}",
    );
    try std.testing.expect(event == .raw);
}

fn parseWithArena(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try parse(arena.allocator(), "GUILD_MEMBER_ADD", envelope);
    try std.testing.expect(event == .guild_member_add);
}

test "allocation failure while decoding is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseWithArena,
        .{"{\"op\":0,\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"},\"roles\":[\"3\",\"4\"],\"joined_at\":\"2024-01-01T00:00:00+00:00\",\"deaf\":false,\"mute\":false,\"flags\":0}}"},
    );
}

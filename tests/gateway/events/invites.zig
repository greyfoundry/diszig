//! Invite Gateway event contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;
const models = diszig.protocol.events.invites;

fn parse(allocator: std.mem.Allocator, name: []const u8, envelope: []const u8) !events.Event {
    return events.decode(allocator, name, 1, envelope, 8192);
}

test "invite create and delete are typed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const created = try parse(
        arena.allocator(),
        "INVITE_CREATE",
        "{\"op\":0,\"t\":\"INVITE_CREATE\",\"d\":{\"channel_id\":\"1\",\"code\":\"abc\",\"created_at\":\"2024-01-01T00:00:00+00:00\",\"guild_id\":\"2\",\"inviter\":{\"id\":\"3\",\"username\":\"u\"},\"max_age\":3600,\"max_uses\":5,\"temporary\":true,\"uses\":0,\"expires_at\":\"2024-01-02T00:00:00+00:00\"}}",
    );
    try std.testing.expect(created == .invite_create);
    try std.testing.expectEqualStrings("abc", created.invite_create.code);
    try std.testing.expectEqualStrings("u", created.invite_create.inviter.?.username);
    try std.testing.expect(created.invite_create.temporary);

    const deleted = try parse(
        arena.allocator(),
        "INVITE_DELETE",
        "{\"op\":0,\"t\":\"INVITE_DELETE\",\"d\":{\"channel_id\":\"1\",\"code\":\"abc\"}}",
    );
    try std.testing.expect(deleted == .invite_delete);
    try std.testing.expect(deleted.invite_delete.guild_id == null);
}

test "unknown target type is retained" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const created = try parse(
        arena.allocator(),
        "INVITE_CREATE",
        "{\"op\":0,\"t\":\"INVITE_CREATE\",\"d\":{\"channel_id\":\"1\",\"code\":\"abc\",\"created_at\":\"2024-01-01T00:00:00+00:00\",\"max_age\":0,\"max_uses\":0,\"temporary\":false,\"uses\":0,\"target_type\":9}}",
    );
    try std.testing.expectEqual(@as(?models.TargetType, null), created.invite_create.target_type.?.known());
    try std.testing.expectEqual(@as(i64, 9), created.invite_create.target_type.?.raw.integer);
}

test "unrelated events still fall back to raw" {
    const event = try parse(
        std.testing.allocator,
        "MESSAGE_CREATE",
        "{\"op\":0,\"t\":\"MESSAGE_CREATE\",\"d\":{\"id\":\"1\"}}",
    );
    try std.testing.expect(event == .raw);
}

fn parseWithArena(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try parse(arena.allocator(), "INVITE_CREATE", envelope);
    try std.testing.expect(event == .invite_create);
}

test "allocation failure while decoding is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseWithArena,
        .{"{\"op\":0,\"d\":{\"channel_id\":\"1\",\"code\":\"abc\",\"created_at\":\"2024-01-01T00:00:00+00:00\",\"max_age\":0,\"max_uses\":0,\"temporary\":false,\"uses\":0,\"role_ids\":[\"2\",\"3\"]}}"},
    );
}

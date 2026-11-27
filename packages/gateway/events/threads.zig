//! Typed thread Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.threads;

pub const ThreadCreate = models.ThreadCreate;
pub const ThreadUpdate = models.Channel;
pub const ThreadDelete = models.ThreadDelete;
pub const ThreadListSync = models.ThreadListSync;
pub const ThreadMemberUpdate = models.ThreadMemberUpdate;
pub const ThreadMembersUpdate = models.ThreadMembersUpdate;

pub const Event = union(enum) {
    create: ThreadCreate,
    update: ThreadUpdate,
    delete: ThreadDelete,
    list_sync: ThreadListSync,
    member_update: ThreadMemberUpdate,
    members_update: ThreadMembersUpdate,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "THREAD_CREATE")) {
        return .{ .create = try parseD(ThreadCreate, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "THREAD_UPDATE")) {
        return .{ .update = try parseD(ThreadUpdate, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "THREAD_DELETE")) {
        return .{ .delete = try parseD(ThreadDelete, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "THREAD_LIST_SYNC")) {
        return .{ .list_sync = try parseD(ThreadListSync, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "THREAD_MEMBER_UPDATE")) {
        return .{ .member_update = try parseD(ThreadMemberUpdate, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "THREAD_MEMBERS_UPDATE")) {
        return .{ .members_update = try parseD(ThreadMembersUpdate, allocator, envelope, max_bytes) };
    }
    return null;
}

fn parseD(
    comptime T: type,
    allocator: std.mem.Allocator,
    envelope: []const u8,
    max_bytes: usize,
) !T {
    if (envelope.len > max_bytes) return error.InputTooLarge;
    try protocol.json.checkDepth(envelope, 128);
    const Wire = struct { d: T };
    const wire = try std.json.parseFromSliceLeaky(Wire, allocator, envelope, .{
        .ignore_unknown_fields = true,
    });
    return wire.d;
}

test "thread events decode through the batch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const created = (try decode(
        aa,
        "THREAD_CREATE",
        "{\"op\":0,\"t\":\"THREAD_CREATE\",\"s\":1,\"d\":{\"id\":\"1\",\"type\":11,\"guild_id\":\"2\",\"parent_id\":\"3\",\"name\":\"t\",\"newly_created\":true}}",
        2048,
    )).?;
    try std.testing.expect(created == .create);
    try std.testing.expect(created.create.newly_created.?);

    const deleted = (try decode(
        aa,
        "THREAD_DELETE",
        "{\"op\":0,\"t\":\"THREAD_DELETE\",\"s\":2,\"d\":{\"id\":\"1\",\"guild_id\":\"2\",\"parent_id\":\"3\",\"type\":11}}",
        1024,
    )).?;
    try std.testing.expect(deleted == .delete);
    try std.testing.expectEqual(@as(u64, 2), deleted.delete.guild_id.toU64());
}

fn parseMembers(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "THREAD_MEMBERS_UPDATE", envelope, 2048);
    try std.testing.expect(event != null);
}

test "allocation failure during thread decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseMembers,
        .{"{\"op\":0,\"d\":{\"id\":\"1\",\"guild_id\":\"2\",\"member_count\":1,\"added_members\":[{\"id\":\"1\",\"user_id\":\"3\",\"join_timestamp\":\"2024-01-01T00:00:00+00:00\",\"flags\":0}],\"removed_member_ids\":[\"4\"]}}"},
    );
}

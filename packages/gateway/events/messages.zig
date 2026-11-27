//! Typed message Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.messages;

pub const Message = models.Message;
pub const MessageDelete = models.MessageDelete;
pub const MessageDeleteBulk = models.MessageDeleteBulk;

pub const Event = union(enum) {
    create: Message,
    update: Message,
    delete: MessageDelete,
    delete_bulk: MessageDeleteBulk,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "MESSAGE_CREATE")) {
        return .{ .create = try parseD(Message, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "MESSAGE_UPDATE")) {
        return .{ .update = try parseD(Message, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "MESSAGE_DELETE")) {
        return .{ .delete = try parseD(MessageDelete, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "MESSAGE_DELETE_BULK")) {
        return .{ .delete_bulk = try parseD(MessageDeleteBulk, allocator, envelope, max_bytes) };
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

test "message create, update and deletions decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const created = (try decode(
        aa,
        "MESSAGE_CREATE",
        "{\"op\":0,\"t\":\"MESSAGE_CREATE\",\"d\":{\"id\":\"1\",\"channel_id\":\"2\",\"author\":{\"id\":\"3\",\"username\":\"u\"},\"content\":\"hi\",\"timestamp\":\"2024-01-01T00:00:00+00:00\"}}",
        1024,
    )).?;
    try std.testing.expect(created == .create);
    try std.testing.expectEqualStrings("hi", created.create.content.get().?);

    const updated = (try decode(
        aa,
        "MESSAGE_UPDATE",
        "{\"op\":0,\"t\":\"MESSAGE_UPDATE\",\"d\":{\"id\":\"1\",\"content\":\"edited\"}}",
        1024,
    )).?;
    try std.testing.expect(updated == .update);
    try std.testing.expectEqualStrings("edited", updated.update.content.get().?);

    const deleted = (try decode(
        aa,
        "MESSAGE_DELETE",
        "{\"op\":0,\"t\":\"MESSAGE_DELETE\",\"d\":{\"id\":\"1\",\"channel_id\":\"2\"}}",
        1024,
    )).?;
    try std.testing.expect(deleted == .delete);

    const bulk = (try decode(
        aa,
        "MESSAGE_DELETE_BULK",
        "{\"op\":0,\"t\":\"MESSAGE_DELETE_BULK\",\"d\":{\"ids\":[\"1\",\"4\"],\"channel_id\":\"2\",\"guild_id\":\"3\"}}",
        1024,
    )).?;
    try std.testing.expect(bulk == .delete_bulk);
    try std.testing.expectEqual(@as(usize, 2), bulk.delete_bulk.ids.len);
}

fn parseCreate(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "MESSAGE_CREATE", envelope, 2048);
    try std.testing.expect(event != null);
}

test "allocation failure during message decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseCreate,
        .{"{\"op\":0,\"d\":{\"id\":\"1\",\"channel_id\":\"2\",\"author\":{\"id\":\"3\",\"username\":\"u\"},\"content\":\"hi\",\"timestamp\":\"2024-01-01T00:00:00+00:00\",\"mentions\":[{\"id\":\"4\",\"username\":\"m\"}],\"attachments\":[{\"id\":\"5\",\"filename\":\"a\",\"size\":1,\"url\":\"u\",\"proxy_url\":\"p\"}]}}"},
    );
}

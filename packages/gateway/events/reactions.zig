//! Typed reaction Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.reactions;

pub const ReactionAdd = models.ReactionAdd;
pub const ReactionRemove = models.ReactionRemove;
pub const ReactionRemoveAll = models.ReactionRemoveAll;
pub const ReactionRemoveEmoji = models.ReactionRemoveEmoji;

pub const Event = union(enum) {
    add: ReactionAdd,
    remove: ReactionRemove,
    remove_all: ReactionRemoveAll,
    remove_emoji: ReactionRemoveEmoji,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "MESSAGE_REACTION_ADD")) {
        return .{ .add = try parseD(ReactionAdd, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "MESSAGE_REACTION_REMOVE")) {
        return .{ .remove = try parseD(ReactionRemove, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "MESSAGE_REACTION_REMOVE_ALL")) {
        return .{ .remove_all = try parseD(ReactionRemoveAll, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "MESSAGE_REACTION_REMOVE_EMOJI")) {
        return .{ .remove_emoji = try parseD(ReactionRemoveEmoji, allocator, envelope, max_bytes) };
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

test "reaction events decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const added = (try decode(
        arena.allocator(),
        "MESSAGE_REACTION_ADD",
        "{\"op\":0,\"t\":\"MESSAGE_REACTION_ADD\",\"s\":1,\"d\":{\"user_id\":\"1\",\"channel_id\":\"2\",\"message_id\":\"3\",\"emoji\":{\"name\":\"x\"},\"burst\":false,\"type\":0}}",
        2048,
    )).?;
    try std.testing.expect(added == .add);
    try std.testing.expectEqualStrings("x", added.add.emoji.name.?);

    const removed_all = (try decode(
        arena.allocator(),
        "MESSAGE_REACTION_REMOVE_ALL",
        "{\"op\":0,\"t\":\"MESSAGE_REACTION_REMOVE_ALL\",\"s\":2,\"d\":{\"channel_id\":\"2\",\"message_id\":\"3\"}}",
        1024,
    )).?;
    try std.testing.expect(removed_all == .remove_all);
}

fn parseRemove(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "MESSAGE_REACTION_REMOVE", envelope, 2048);
    try std.testing.expect(event != null);
}

test "allocation failure during reaction decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseRemove,
        .{"{\"op\":0,\"d\":{\"user_id\":\"1\",\"channel_id\":\"2\",\"message_id\":\"3\",\"emoji\":{\"id\":\"4\",\"name\":\"wave\"},\"burst\":false,\"type\":0}}"},
    );
}

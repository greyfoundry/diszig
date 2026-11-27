//! Typed poll Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.polls;

pub const PollVoteAdd = models.PollVoteAdd;
pub const PollVoteRemove = models.PollVoteRemove;

pub const Event = union(enum) {
    vote_add: PollVoteAdd,
    vote_remove: PollVoteRemove,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "MESSAGE_POLL_VOTE_ADD")) {
        return .{ .vote_add = try parseD(PollVoteAdd, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "MESSAGE_POLL_VOTE_REMOVE")) {
        return .{ .vote_remove = try parseD(PollVoteRemove, allocator, envelope, max_bytes) };
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

test "poll vote events decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const added = (try decode(
        arena.allocator(),
        "MESSAGE_POLL_VOTE_ADD",
        "{\"op\":0,\"t\":\"MESSAGE_POLL_VOTE_ADD\",\"s\":1,\"d\":{\"user_id\":\"1\",\"channel_id\":\"2\",\"message_id\":\"3\",\"answer_id\":1}}",
        1024,
    )).?;
    try std.testing.expect(added == .vote_add);
    try std.testing.expectEqual(@as(i64, 1), added.vote_add.answer_id);

    const removed = (try decode(
        arena.allocator(),
        "MESSAGE_POLL_VOTE_REMOVE",
        "{\"op\":0,\"t\":\"MESSAGE_POLL_VOTE_REMOVE\",\"s\":2,\"d\":{\"user_id\":\"1\",\"channel_id\":\"2\",\"message_id\":\"3\",\"answer_id\":1}}",
        1024,
    )).?;
    try std.testing.expect(removed == .vote_remove);
}

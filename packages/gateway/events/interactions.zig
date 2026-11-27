//! Typed interaction Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.interactions;

pub const Interaction = models.Interaction;

pub const Event = union(enum) {
    create: Interaction,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (!std.mem.eql(u8, name, "INTERACTION_CREATE")) return null;
    return .{ .create = try parseD(Interaction, allocator, envelope, max_bytes) };
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

test "interaction create decodes the envelope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const event = (try decode(
        arena.allocator(),
        "INTERACTION_CREATE",
        "{\"op\":0,\"t\":\"INTERACTION_CREATE\",\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"type\":2,\"token\":\"tok\",\"version\":1,\"data\":{\"name\":\"cmd\"}}}",
        1024,
    )).?;
    try std.testing.expect(event == .create);
    try std.testing.expectEqualStrings("tok", event.create.token);
    try std.testing.expectEqual(models.InteractionType.application_command, event.create.type.known().?);
}

test "unknown interaction event falls back to the caller" {
    try std.testing.expect((try decode(
        std.testing.allocator,
        "MESSAGE_CREATE",
        "{\"op\":0,\"t\":\"MESSAGE_CREATE\",\"d\":{}}",
        1024,
    )) == null);
}

fn parseCreate(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "INTERACTION_CREATE", envelope, 2048);
    try std.testing.expect(event != null);
}

test "allocation failure during interaction decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseCreate,
        .{"{\"op\":0,\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"type\":2,\"token\":\"tok\",\"version\":1,\"member\":{\"user\":{\"id\":\"3\",\"username\":\"u\"},\"roles\":[\"4\"],\"joined_at\":\"2024-01-01T00:00:00+00:00\"},\"data\":{\"name\":\"cmd\"}}}"},
    );
}

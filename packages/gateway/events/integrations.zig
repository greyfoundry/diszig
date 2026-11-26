//! Typed integration Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.integrations;

pub const Integration = models.Integration;
pub const IntegrationDelete = models.IntegrationDelete;

pub const Event = union(enum) {
    create: Integration,
    update: Integration,
    delete: IntegrationDelete,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "INTEGRATION_CREATE")) {
        return .{ .create = try parseD(Integration, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "INTEGRATION_UPDATE")) {
        return .{ .update = try parseD(Integration, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "INTEGRATION_DELETE")) {
        return .{ .delete = try parseD(IntegrationDelete, allocator, envelope, max_bytes) };
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

test "integration create, update and delete decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const created = (try decode(
        aa,
        "INTEGRATION_CREATE",
        "{\"op\":0,\"t\":\"INTEGRATION_CREATE\",\"d\":{\"id\":\"1\",\"name\":\"Hook\",\"type\":\"discord\",\"enabled\":true,\"guild_id\":\"2\",\"account\":{\"id\":\"3\",\"name\":\"acct\"}}}",
        1024,
    )).?;
    try std.testing.expect(created == .create);
    try std.testing.expectEqual(@as(u64, 2), created.create.guild_id.?.toU64());
    try std.testing.expect(created.create.user == null);

    const updated = (try decode(
        aa,
        "INTEGRATION_UPDATE",
        "{\"op\":0,\"t\":\"INTEGRATION_UPDATE\",\"d\":{\"id\":\"1\",\"name\":\"Hook2\",\"type\":\"twitch\",\"enabled\":false,\"guild_id\":\"2\",\"account\":{\"id\":\"3\",\"name\":\"acct\"},\"expire_behavior\":1}}",
        1024,
    )).?;
    try std.testing.expect(updated == .update);
    try std.testing.expectEqual(models.ExpireBehavior.kick, updated.update.expire_behavior.?.known().?);

    const deleted = (try decode(
        aa,
        "INTEGRATION_DELETE",
        "{\"op\":0,\"t\":\"INTEGRATION_DELETE\",\"d\":{\"id\":\"1\",\"guild_id\":\"2\"}}",
        1024,
    )).?;
    try std.testing.expect(deleted == .delete);
    try std.testing.expect(deleted.delete.application_id == null);
}

fn parseCreate(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "INTEGRATION_CREATE", envelope, 1024);
    try std.testing.expect(event != null);
}

test "allocation failure during integration decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseCreate,
        .{"{\"op\":0,\"d\":{\"id\":\"1\",\"name\":\"Hook\",\"type\":\"discord\",\"enabled\":true,\"account\":{\"id\":\"2\",\"name\":\"acct\"},\"scopes\":[\"bot\",\"applications.commands\"]}}"},
    );
}

//! Application command permission event contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;
const commands = diszig.protocol.events.commands;

fn parse(allocator: std.mem.Allocator, envelope: []const u8) !events.Event {
    return events.decode(allocator, "APPLICATION_COMMAND_PERMISSIONS_UPDATE", 1, envelope, 16 * 1024);
}

test "minimal permissions update is typed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "{\"op\":0,\"t\":\"APPLICATION_COMMAND_PERMISSIONS_UPDATE\",\"s\":1,\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"guild_id\":\"3\",\"permissions\":[{\"id\":\"4\",\"type\":1,\"permission\":true}]}}",
    );
    try std.testing.expect(event == .application_command_permissions_update);
    const update = event.application_command_permissions_update;
    try std.testing.expectEqual(@as(u64, 1), update.id.toU64());
    try std.testing.expectEqual(@as(usize, 1), update.permissions.len);
    try std.testing.expectEqual(commands.PermissionType.role, update.permissions[0].type.known().?);
    try std.testing.expect(update.permissions[0].permission);
}

test "unknown permission type and unknown fields are tolerated" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "{\"op\":0,\"t\":\"APPLICATION_COMMAND_PERMISSIONS_UPDATE\",\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"guild_id\":\"3\",\"future\":true,\"permissions\":[{\"id\":\"4\",\"type\":99,\"permission\":false,\"extra\":1}]}}",
    );
    const update = event.application_command_permissions_update;
    try std.testing.expectEqual(@as(?commands.PermissionType, null), update.permissions[0].type.known());
    try std.testing.expectEqual(@as(i64, 99), update.permissions[0].type.raw.integer);
    try std.testing.expect(!update.permissions[0].permission);
}

test "more than 100 permissions is rejected locally" {
    var buffer: [16 * 1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writer.writeAll("{\"op\":0,\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"guild_id\":\"3\",\"permissions\":[");
    var i: usize = 0;
    while (i < 101) : (i += 1) {
        if (i > 0) try writer.writeByte(',');
        try writer.writeAll("{\"id\":\"4\",\"type\":1,\"permission\":true}");
    }
    try writer.writeAll("]}}");

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectError(
        error.TooManyPermissions,
        parse(arena.allocator(), writer.buffered()),
    );
}

test "an unrelated event still falls back to raw" {
    const event = try parse(
        std.testing.allocator,
        "{\"op\":0,\"t\":\"APPLICATION_COMMAND_PERMISSIONS_UPDATE\",\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"guild_id\":\"3\",\"permissions\":[]}}",
    );
    try std.testing.expect(event == .application_command_permissions_update);
}

fn parseWithArena(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try parse(arena.allocator(), envelope);
    try std.testing.expect(event == .application_command_permissions_update);
}

test "allocation failure while decoding is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseWithArena,
        .{"{\"op\":0,\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"guild_id\":\"3\",\"permissions\":[{\"id\":\"4\",\"type\":2,\"permission\":true}]}}"},
    );
}

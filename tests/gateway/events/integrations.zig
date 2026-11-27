//! Integration Gateway event contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;
const models = diszig.protocol.events.integrations;

fn parse(allocator: std.mem.Allocator, name: []const u8, envelope: []const u8) !events.Event {
    return events.decode(allocator, name, 1, envelope, 8192);
}

test "integration create and update omit user but carry guild id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const created = try parse(
        arena.allocator(),
        "INTEGRATION_CREATE",
        "{\"op\":0,\"t\":\"INTEGRATION_CREATE\",\"d\":{\"id\":\"1\",\"name\":\"Hook\",\"type\":\"discord\",\"enabled\":true,\"guild_id\":\"2\",\"account\":{\"id\":\"3\",\"name\":\"acct\"},\"application\":{\"id\":\"4\",\"name\":\"app\",\"description\":\"d\",\"icon\":null}}}",
    );
    try std.testing.expect(created == .integration_create);
    try std.testing.expectEqual(models.IntegrationType.discord, created.integration_create.type.known().?);
    try std.testing.expect(created.integration_create.user == null);
    try std.testing.expect(created.integration_create.application.?.icon.isNull());

    const updated = try parse(
        arena.allocator(),
        "INTEGRATION_UPDATE",
        "{\"op\":0,\"t\":\"INTEGRATION_UPDATE\",\"d\":{\"id\":\"1\",\"name\":\"Hook2\",\"type\":\"future\",\"enabled\":false,\"guild_id\":\"2\",\"account\":{\"id\":\"3\",\"name\":\"acct\"},\"role_id\":null}}",
    );
    try std.testing.expect(updated == .integration_update);
    try std.testing.expectEqual(@as(?models.IntegrationType, null), updated.integration_update.type.known());
    try std.testing.expectEqualStrings("future", updated.integration_update.type.raw);
    try std.testing.expect(updated.integration_update.role_id.isNull());
}

test "integration delete carries the optional application id" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "INTEGRATION_DELETE",
        "{\"op\":0,\"t\":\"INTEGRATION_DELETE\",\"d\":{\"id\":\"1\",\"guild_id\":\"2\",\"application_id\":\"3\"}}",
    );
    try std.testing.expect(event == .integration_delete);
    try std.testing.expectEqual(@as(u64, 3), event.integration_delete.application_id.?.toU64());
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
    const event = try parse(arena.allocator(), "INTEGRATION_CREATE", envelope);
    try std.testing.expect(event == .integration_create);
}

test "allocation failure while decoding is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseWithArena,
        .{"{\"op\":0,\"d\":{\"id\":\"1\",\"name\":\"Hook\",\"type\":\"discord\",\"enabled\":true,\"account\":{\"id\":\"2\",\"name\":\"acct\"},\"scopes\":[\"bot\",\"applications.commands\"]}}"},
    );
}

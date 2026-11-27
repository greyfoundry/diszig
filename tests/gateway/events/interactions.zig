//! Interaction Gateway event contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;
const models = diszig.protocol.events.interactions;

fn parse(allocator: std.mem.Allocator, envelope: []const u8) !events.Event {
    return events.decode(allocator, "INTERACTION_CREATE", 1, envelope, 8192);
}

test "guild command interaction is typed with raw data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "{\"op\":0,\"t\":\"INTERACTION_CREATE\",\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"type\":2,\"guild_id\":\"3\",\"channel_id\":\"4\",\"member\":{\"user\":{\"id\":\"5\",\"username\":\"u\"},\"roles\":[\"6\"],\"joined_at\":\"2024-01-01T00:00:00+00:00\",\"permissions\":\"2048\"},\"token\":\"tok\",\"version\":1,\"app_permissions\":\"1024\",\"context\":0,\"locale\":\"en-US\",\"data\":{\"id\":\"7\",\"name\":\"cmd\",\"options\":[]}}}",
    );
    try std.testing.expect(event == .interaction_create);
    const interaction = event.interaction_create;
    try std.testing.expectEqual(models.InteractionType.application_command, interaction.type.known().?);
    try std.testing.expectEqual(@as(u64, 1024), interaction.app_permissions.?.bits);
    try std.testing.expectEqual(@as(u64, 2048), interaction.member.?.permissions.?.bits);
    try std.testing.expectEqual(models.ContextType.guild, interaction.context.?.known().?);
    try std.testing.expectEqualStrings("tok", interaction.token);
    try std.testing.expect(interaction.data != null);
}

test "DM interaction uses user and unknown types are retained" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "{\"op\":0,\"t\":\"INTERACTION_CREATE\",\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"type\":99,\"user\":{\"id\":\"3\",\"username\":\"dm\"},\"token\":\"t\",\"version\":1}}",
    );
    const interaction = event.interaction_create;
    try std.testing.expectEqual(@as(?models.InteractionType, null), interaction.type.known());
    try std.testing.expectEqual(@as(i64, 99), interaction.type.raw.integer);
    try std.testing.expect(interaction.member == null);
    try std.testing.expectEqualStrings("dm", interaction.user.?.username);
}

test "missing interaction token is a local error" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = parse(
        arena.allocator(),
        "{\"op\":0,\"t\":\"INTERACTION_CREATE\",\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"type\":2,\"version\":1}}",
    );
    try std.testing.expectError(error.MissingField, result);
}

test "unrelated events still fall back to raw" {
    const event = try events.decode(
        std.testing.allocator,
        "GUILD_ROLE_FUTURE",
        1,
        "{\"op\":0,\"t\":\"GUILD_ROLE_FUTURE\",\"d\":{\"guild_id\":\"1\"}}",
        1024,
    );
    try std.testing.expect(event == .raw);
}

fn parseWithArena(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try parse(arena.allocator(), envelope);
    try std.testing.expect(event == .interaction_create);
}

test "allocation failure while decoding is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseWithArena,
        .{"{\"op\":0,\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"type\":2,\"token\":\"tok\",\"version\":1,\"member\":{\"user\":{\"id\":\"3\",\"username\":\"u\"},\"roles\":[\"4\"],\"joined_at\":\"2024-01-01T00:00:00+00:00\"},\"data\":{\"name\":\"cmd\"}}}"},
    );
}

//! Guild Gateway event contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;

fn parse(allocator: std.mem.Allocator, name: []const u8, envelope: []const u8) !events.Event {
    return events.decode(allocator, name, 1, envelope, 8192);
}

test "minimal guild create and unavailable delete" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const created = try parse(
        arena.allocator(),
        "GUILD_CREATE",
        "{\"op\":0,\"t\":\"GUILD_CREATE\",\"s\":1,\"d\":{\"id\":\"1\",\"name\":\"Guild\",\"icon\":null,\"features\":[\"COMMUNITY\"]}}",
    );
    try std.testing.expect(created == .guild_create);
    try std.testing.expectEqualStrings("Guild", created.guild_create.name.get().?);
    try std.testing.expect(created.guild_create.icon.isNull());

    const deleted = try parse(
        arena.allocator(),
        "GUILD_DELETE",
        "{\"op\":0,\"t\":\"GUILD_DELETE\",\"d\":{\"id\":\"1\",\"unavailable\":true}}",
    );
    try std.testing.expect(deleted == .guild_delete);
    try std.testing.expect(deleted.guild_delete.unavailable.?);
    try std.testing.expect(deleted.guild_delete.name.isAbsent());
}

test "partial guild update is not a full resource" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const partial = try parse(
        arena.allocator(),
        "GUILD_UPDATE",
        "{\"op\":0,\"t\":\"GUILD_UPDATE\",\"d\":{\"id\":\"1\"}}",
    );
    try std.testing.expect(partial == .guild_update);
    try std.testing.expect(partial.guild_update.name.isAbsent());
    try std.testing.expectEqual(@as(?i64, null), partial.guild_update.member_count);

    const cleared = try parse(
        arena.allocator(),
        "GUILD_UPDATE",
        "{\"op\":0,\"t\":\"GUILD_UPDATE\",\"d\":{\"id\":\"1\",\"banner\":null,\"vanity_url_code\":null}}",
    );
    try std.testing.expect(cleared.guild_update.banner.isNull());
    try std.testing.expect(cleared.guild_update.vanity_url_code.isNull());
}

test "audit log entry keeps action-specific data raw" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try parse(
        arena.allocator(),
        "GUILD_AUDIT_LOG_ENTRY_CREATE",
        "{\"op\":0,\"t\":\"GUILD_AUDIT_LOG_ENTRY_CREATE\",\"d\":{\"id\":\"1\",\"action_type\":20,\"guild_id\":\"2\",\"target_id\":\"3\",\"user_id\":\"4\",\"reason\":\"why\",\"changes\":[{\"key\":\"name\",\"old_value\":\"a\",\"new_value\":\"b\"}],\"options\":{\"channel_id\":\"5\"}}}",
    );
    try std.testing.expect(event == .guild_audit_log_entry_create);
    const entry = event.guild_audit_log_entry_create;
    try std.testing.expectEqual(@as(i64, 20), entry.action_type);
    try std.testing.expectEqual(@as(usize, 1), entry.changes.?.len);
    try std.testing.expectEqualStrings("why", entry.reason.?);
}

test "ban add and remove decode the user subset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const added = try parse(
        arena.allocator(),
        "GUILD_BAN_ADD",
        "{\"op\":0,\"t\":\"GUILD_BAN_ADD\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\",\"bot\":true}}}",
    );
    try std.testing.expect(added == .guild_ban_add);
    try std.testing.expectEqualStrings("u", added.guild_ban_add.user.username);

    const removed = try parse(
        arena.allocator(),
        "GUILD_BAN_REMOVE",
        "{\"op\":0,\"t\":\"GUILD_BAN_REMOVE\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"}}}",
    );
    try std.testing.expect(removed == .guild_ban_remove);
}

test "unrelated events still fall back to raw" {
    const event = try parse(
        std.testing.allocator,
        "GUILD_ROLE_FUTURE",
        "{\"op\":0,\"t\":\"GUILD_ROLE_FUTURE\",\"d\":{\"guild_id\":\"1\"}}",
    );
    try std.testing.expect(event == .raw);
}

fn parseWithArena(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try parse(arena.allocator(), "GUILD_CREATE", envelope);
    try std.testing.expect(event == .guild_create);
}

test "allocation failure while decoding is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseWithArena,
        .{"{\"op\":0,\"t\":\"GUILD_CREATE\",\"d\":{\"id\":\"1\",\"name\":\"Guild\",\"features\":[\"COMMUNITY\",\"NEWS\"],\"icon\":null}}"},
    );
}

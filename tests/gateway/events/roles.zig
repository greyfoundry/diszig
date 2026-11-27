//! Role Gateway event batch contracts.

const std = @import("std");
const diszig = @import("diszig");
const events = diszig.gateway.events;

test "role events decode through the dispatcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const created = try events.decode(
        arena.allocator(),
        "GUILD_ROLE_CREATE",
        1,
        "{\"op\":0,\"t\":\"GUILD_ROLE_CREATE\",\"s\":1,\"d\":{\"guild_id\":\"1\",\"role\":{\"id\":\"2\",\"name\":\"Mod\",\"color\":0,\"colors\":{\"primary_color\":0},\"hoist\":false,\"position\":1,\"permissions\":\"8\",\"managed\":false,\"mentionable\":false,\"flags\":0}}}",
        4096,
    );
    try std.testing.expect(created == .guild_role_create);
    try std.testing.expectEqualStrings("Mod", created.guild_role_create.role.name);

    const updated = try events.decode(
        arena.allocator(),
        "GUILD_ROLE_UPDATE",
        2,
        "{\"op\":0,\"t\":\"GUILD_ROLE_UPDATE\",\"s\":2,\"d\":{\"guild_id\":\"1\",\"role\":{\"id\":\"2\",\"name\":\"Renamed\",\"color\":0,\"colors\":{\"primary_color\":0},\"hoist\":true,\"position\":2,\"permissions\":\"0\",\"managed\":false,\"mentionable\":true,\"flags\":0}}}",
        4096,
    );
    try std.testing.expect(updated == .guild_role_update);
    try std.testing.expect(updated.guild_role_update.role.hoist);

    const deleted = try events.decode(
        arena.allocator(),
        "GUILD_ROLE_DELETE",
        3,
        "{\"op\":0,\"t\":\"GUILD_ROLE_DELETE\",\"s\":3,\"d\":{\"guild_id\":\"1\",\"role_id\":\"2\"}}",
        1024,
    );
    try std.testing.expect(deleted == .guild_role_delete);
    try std.testing.expectEqual(@as(u64, 2), deleted.guild_role_delete.role_id.toU64());
}

test "unknown role-like names stay raw" {
    const event = try events.decode(
        std.testing.allocator,
        "GUILD_ROLE_FUTURE",
        4,
        "{\"op\":0,\"t\":\"GUILD_ROLE_FUTURE\",\"s\":4,\"d\":{}}",
        1024,
    );
    try std.testing.expect(event == .raw);
}

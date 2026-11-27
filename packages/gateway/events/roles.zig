//! Typed role Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.roles;

pub const RoleCreate = models.RoleCreate;
pub const RoleUpdate = models.RoleUpdate;
pub const RoleDelete = models.RoleDelete;

pub const Event = union(enum) {
    create: RoleCreate,
    update: RoleUpdate,
    delete: RoleDelete,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "GUILD_ROLE_CREATE")) {
        return .{ .create = try parseD(RoleCreate, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_ROLE_UPDATE")) {
        return .{ .update = try parseD(RoleUpdate, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_ROLE_DELETE")) {
        return .{ .delete = try parseD(RoleDelete, allocator, envelope, max_bytes) };
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

test "role events decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const created = (try decode(
        aa,
        "GUILD_ROLE_CREATE",
        "{\"op\":0,\"t\":\"GUILD_ROLE_CREATE\",\"s\":1,\"d\":{\"guild_id\":\"1\",\"role\":{\"id\":\"2\",\"name\":\"Mod\",\"color\":0,\"colors\":{\"primary_color\":0},\"hoist\":false,\"position\":1,\"permissions\":\"8\",\"managed\":false,\"mentionable\":false,\"flags\":0}}}",
        4096,
    )).?;
    try std.testing.expect(created == .create);
    try std.testing.expectEqualStrings("Mod", created.create.role.name);

    const deleted = (try decode(
        aa,
        "GUILD_ROLE_DELETE",
        "{\"op\":0,\"t\":\"GUILD_ROLE_DELETE\",\"s\":2,\"d\":{\"guild_id\":\"1\",\"role_id\":\"2\"}}",
        1024,
    )).?;
    try std.testing.expect(deleted == .delete);
    try std.testing.expectEqual(@as(u64, 1), deleted.delete.guild_id.toU64());
}

fn parseUpdate(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "GUILD_ROLE_UPDATE", envelope, 4096);
    try std.testing.expect(event != null);
}

test "allocation failure during role update decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseUpdate,
        .{"{\"op\":0,\"d\":{\"guild_id\":\"1\",\"role\":{\"id\":\"2\",\"name\":\"Mod\",\"color\":0,\"colors\":{\"primary_color\":0},\"hoist\":false,\"position\":1,\"permissions\":\"8\",\"managed\":false,\"mentionable\":false,\"flags\":0,\"icon\":\"hash\",\"unicode_emoji\":null}}}"},
    );
}

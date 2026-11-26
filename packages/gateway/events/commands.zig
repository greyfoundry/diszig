//! Typed application command Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.commands;

pub const GuildApplicationCommandPermissions = models.GuildApplicationCommandPermissions;

pub const Event = union(enum) {
    permissions_update: GuildApplicationCommandPermissions,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (!std.mem.eql(u8, name, "APPLICATION_COMMAND_PERMISSIONS_UPDATE")) return null;
    const permissions = try parseD(GuildApplicationCommandPermissions, allocator, envelope, max_bytes);
    if (permissions.permissions.len > 100) return error.TooManyPermissions;
    return .{ .permissions_update = permissions };
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

test "permissions update decodes with a bounded list" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const event = (try decode(
        arena.allocator(),
        "APPLICATION_COMMAND_PERMISSIONS_UPDATE",
        "{\"op\":0,\"t\":\"APPLICATION_COMMAND_PERMISSIONS_UPDATE\",\"d\":{\"id\":\"1\",\"application_id\":\"2\",\"guild_id\":\"3\",\"permissions\":[{\"id\":\"4\",\"type\":2,\"permission\":false}]}}",
        1024,
    )).?;
    try std.testing.expect(event == .permissions_update);
    try std.testing.expectEqual(@as(u64, 1), event.permissions_update.id.toU64());
    try std.testing.expect(!event.permissions_update.permissions[0].permission);
}

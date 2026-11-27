//! Typed invite Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.invites;

pub const InviteCreate = models.InviteCreate;
pub const InviteDelete = models.InviteDelete;

pub const Event = union(enum) {
    create: InviteCreate,
    delete: InviteDelete,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "INVITE_CREATE")) {
        return .{ .create = try parseD(InviteCreate, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "INVITE_DELETE")) {
        return .{ .delete = try parseD(InviteDelete, allocator, envelope, max_bytes) };
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

test "invite create and delete decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const created = (try decode(
        aa,
        "INVITE_CREATE",
        "{\"op\":0,\"t\":\"INVITE_CREATE\",\"d\":{\"channel_id\":\"1\",\"code\":\"abc\",\"created_at\":\"2024-01-01T00:00:00+00:00\",\"max_age\":3600,\"max_uses\":0,\"temporary\":false,\"uses\":0}}",
        1024,
    )).?;
    try std.testing.expect(created == .create);
    try std.testing.expectEqualStrings("abc", created.create.code);

    const deleted = (try decode(
        aa,
        "INVITE_DELETE",
        "{\"op\":0,\"t\":\"INVITE_DELETE\",\"d\":{\"channel_id\":\"1\",\"guild_id\":\"2\",\"code\":\"abc\"}}",
        1024,
    )).?;
    try std.testing.expect(deleted == .delete);
    try std.testing.expectEqual(@as(u64, 2), deleted.delete.guild_id.?.toU64());
}

fn parseCreate(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "INVITE_CREATE", envelope, 1024);
    try std.testing.expect(event != null);
}

test "allocation failure during invite decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseCreate,
        .{"{\"op\":0,\"d\":{\"channel_id\":\"1\",\"code\":\"abc\",\"created_at\":\"2024-01-01T00:00:00+00:00\",\"max_age\":0,\"max_uses\":0,\"temporary\":false,\"uses\":0,\"role_ids\":[\"2\",\"3\"]}}"},
    );
}

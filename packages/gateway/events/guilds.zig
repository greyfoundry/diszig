//! Typed guild Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.guilds;

pub const Guild = models.Guild;
pub const AuditLogEntry = models.AuditLogEntry;
pub const GuildBan = models.GuildBan;

pub const Event = union(enum) {
    create: Guild,
    update: Guild,
    delete: Guild,
    audit_log_entry_create: AuditLogEntry,
    ban_add: GuildBan,
    ban_remove: GuildBan,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "GUILD_CREATE")) {
        return .{ .create = try parseD(Guild, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_UPDATE")) {
        return .{ .update = try parseD(Guild, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_DELETE")) {
        return .{ .delete = try parseD(Guild, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_AUDIT_LOG_ENTRY_CREATE")) {
        return .{ .audit_log_entry_create = try parseD(AuditLogEntry, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_BAN_ADD")) {
        return .{ .ban_add = try parseD(GuildBan, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_BAN_REMOVE")) {
        return .{ .ban_remove = try parseD(GuildBan, allocator, envelope, max_bytes) };
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

test "guild create, update and unavailable delete decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const created = (try decode(
        aa,
        "GUILD_CREATE",
        "{\"op\":0,\"t\":\"GUILD_CREATE\",\"d\":{\"id\":\"1\",\"name\":\"Guild\",\"member_count\":3}}",
        1024,
    )).?;
    try std.testing.expect(created == .create);
    try std.testing.expectEqualStrings("Guild", created.create.name.get().?);

    const updated = (try decode(
        aa,
        "GUILD_UPDATE",
        "{\"op\":0,\"t\":\"GUILD_UPDATE\",\"d\":{\"id\":\"1\"}}",
        1024,
    )).?;
    try std.testing.expect(updated.update.name.isAbsent());

    const deleted = (try decode(
        aa,
        "GUILD_DELETE",
        "{\"op\":0,\"t\":\"GUILD_DELETE\",\"d\":{\"id\":\"1\",\"unavailable\":true}}",
        1024,
    )).?;
    try std.testing.expect(deleted.delete.unavailable.?);
}

test "audit log and ban events decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const audit = (try decode(
        aa,
        "GUILD_AUDIT_LOG_ENTRY_CREATE",
        "{\"op\":0,\"t\":\"GUILD_AUDIT_LOG_ENTRY_CREATE\",\"d\":{\"id\":\"1\",\"action_type\":20,\"guild_id\":\"2\",\"changes\":[{\"key\":\"name\",\"new_value\":\"x\"}]}}",
        1024,
    )).?;
    try std.testing.expect(audit == .audit_log_entry_create);
    try std.testing.expectEqual(@as(u64, 2), audit.audit_log_entry_create.guild_id.?.toU64());

    const banned = (try decode(
        aa,
        "GUILD_BAN_ADD",
        "{\"op\":0,\"t\":\"GUILD_BAN_ADD\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"}}}",
        1024,
    )).?;
    try std.testing.expect(banned == .ban_add);
    try std.testing.expectEqualStrings("u", banned.ban_add.user.username);
}

fn parseCreate(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "GUILD_CREATE", envelope, 1024);
    try std.testing.expect(event != null);
}

test "allocation failure during guild decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseCreate,
        .{"{\"op\":0,\"t\":\"GUILD_CREATE\",\"d\":{\"id\":\"1\",\"name\":\"Guild\",\"features\":[\"COMMUNITY\"],\"icon\":null}}"},
    );
}

//! Typed guild member Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.members;
const shared = protocol.events.shared;

pub const MemberEvent = models.MemberEvent;
pub const MemberRemove = models.MemberRemove;
pub const MembersChunk = models.MembersChunk;

pub const Event = union(enum) {
    add: MemberEvent,
    update: MemberEvent,
    remove: MemberRemove,
    chunk: MembersChunk,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "GUILD_MEMBER_ADD")) {
        return .{ .add = try decodeMemberEvent(allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_MEMBER_UPDATE")) {
        return .{ .update = try decodeMemberEvent(allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_MEMBER_REMOVE")) {
        return .{ .remove = try parseD(MemberRemove, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "GUILD_MEMBERS_CHUNK")) {
        return .{ .chunk = try parseD(MembersChunk, allocator, envelope, max_bytes) };
    }
    return null;
}

fn decodeMemberEvent(
    allocator: std.mem.Allocator,
    envelope: []const u8,
    max_bytes: usize,
) !MemberEvent {
    const GuildWire = struct { guild_id: protocol.Snowflake };
    const guild = try parseD(GuildWire, allocator, envelope, max_bytes);
    const member = try parseD(shared.Member, allocator, envelope, max_bytes);
    return .{ .guild_id = guild.guild_id, .member = member };
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

test "member add, update, remove and chunk decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const added = (try decode(
        aa,
        "GUILD_MEMBER_ADD",
        "{\"op\":0,\"t\":\"GUILD_MEMBER_ADD\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"},\"roles\":[\"3\"],\"joined_at\":\"2024-01-01T00:00:00+00:00\",\"deaf\":false,\"mute\":false,\"flags\":0}}",
        1024,
    )).?;
    try std.testing.expect(added == .add);
    try std.testing.expectEqual(@as(u64, 1), added.add.guild_id.toU64());
    try std.testing.expectEqual(@as(usize, 1), added.add.member.roles.len);

    const updated = (try decode(
        aa,
        "GUILD_MEMBER_UPDATE",
        "{\"op\":0,\"t\":\"GUILD_MEMBER_UPDATE\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"},\"roles\":[],\"nick\":\"nick\",\"joined_at\":null,\"deaf\":false,\"mute\":false,\"flags\":0}}",
        1024,
    )).?;
    try std.testing.expect(updated == .update);
    try std.testing.expectEqualStrings("nick", updated.update.member.nick.get().?);
    try std.testing.expect(updated.update.member.joined_at.isNull());

    const removed = (try decode(
        aa,
        "GUILD_MEMBER_REMOVE",
        "{\"op\":0,\"t\":\"GUILD_MEMBER_REMOVE\",\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"}}}",
        1024,
    )).?;
    try std.testing.expect(removed == .remove);

    const chunk = (try decode(
        aa,
        "GUILD_MEMBERS_CHUNK",
        "{\"op\":0,\"t\":\"GUILD_MEMBERS_CHUNK\",\"d\":{\"guild_id\":\"1\",\"members\":[],\"chunk_index\":0,\"chunk_count\":1}}",
        1024,
    )).?;
    try std.testing.expect(chunk == .chunk);
}

fn parseAdd(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "GUILD_MEMBER_ADD", envelope, 1024);
    try std.testing.expect(event != null);
}

test "allocation failure during member decode is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseAdd,
        .{"{\"op\":0,\"d\":{\"guild_id\":\"1\",\"user\":{\"id\":\"2\",\"username\":\"u\"},\"roles\":[\"3\"],\"joined_at\":\"2024-01-01T00:00:00+00:00\",\"deaf\":false,\"mute\":false,\"flags\":0}}"},
    );
}

//! Typed user/presence Gateway event decoding.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.users;

pub const PresenceUpdate = models.PresenceUpdate;
pub const TypingStart = models.TypingStart;
pub const UserUpdate = models.UserUpdate;

pub const Event = union(enum) {
    presence: PresenceUpdate,
    typing: TypingStart,
    user_update: UserUpdate,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "PRESENCE_UPDATE")) {
        return .{ .presence = try parseD(PresenceUpdate, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "TYPING_START")) {
        return .{ .typing = try parseD(TypingStart, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "USER_UPDATE")) {
        return .{ .user_update = try parseD(UserUpdate, allocator, envelope, max_bytes) };
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

test "presence, typing and user update decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const presence = (try decode(
        aa,
        "PRESENCE_UPDATE",
        "{\"op\":0,\"t\":\"PRESENCE_UPDATE\",\"s\":1,\"d\":{\"user\":{\"id\":\"1\"},\"guild_id\":\"2\",\"status\":\"idle\",\"activities\":[],\"client_status\":{}}}",
        2048,
    )).?;
    try std.testing.expect(presence == .presence);
    try std.testing.expectEqualStrings("idle", presence.presence.status);

    const typing = (try decode(
        aa,
        "TYPING_START",
        "{\"op\":0,\"t\":\"TYPING_START\",\"s\":2,\"d\":{\"channel_id\":\"1\",\"user_id\":\"2\",\"timestamp\":1}}",
        1024,
    )).?;
    try std.testing.expect(typing == .typing);

    const updated = (try decode(
        aa,
        "USER_UPDATE",
        "{\"op\":0,\"t\":\"USER_UPDATE\",\"s\":3,\"d\":{\"id\":\"1\",\"username\":\"name\"}}",
        1024,
    )).?;
    try std.testing.expect(updated == .user_update);
}

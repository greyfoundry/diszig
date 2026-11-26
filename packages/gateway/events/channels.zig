//! Typed channel Gateway event decoding.
//!
//! The typed payloads borrow the caller's per-callback arena. `d` is parsed
//! directly from the gateway envelope; unknown names return null so the caller
//! can fall back to the raw dispatch queue.

const std = @import("std");
const protocol = @import("protocol");
const models = protocol.events.channels;

pub const Channel = models.Channel;
pub const ChannelInfo = models.ChannelInfo;
pub const ChannelPinsUpdate = models.ChannelPinsUpdate;

pub const Event = union(enum) {
    create: Channel,
    update: Channel,
    delete: Channel,
    info: ChannelInfo,
    pins_update: ChannelPinsUpdate,
};

pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    envelope: []const u8,
    max_bytes: usize,
) !?Event {
    if (std.mem.eql(u8, name, "CHANNEL_CREATE")) {
        return .{ .create = try parseD(Channel, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "CHANNEL_UPDATE")) {
        return .{ .update = try parseD(Channel, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "CHANNEL_DELETE")) {
        return .{ .delete = try parseD(Channel, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "CHANNEL_INFO")) {
        return .{ .info = try parseD(ChannelInfo, allocator, envelope, max_bytes) };
    }
    if (std.mem.eql(u8, name, "CHANNEL_PINS_UPDATE")) {
        return .{ .pins_update = try parseD(ChannelPinsUpdate, allocator, envelope, max_bytes) };
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

test "create and partial update keep absent and null distinct" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const created = (try decode(
        aa,
        "CHANNEL_CREATE",
        "{\"op\":0,\"t\":\"CHANNEL_CREATE\",\"s\":1,\"d\":{\"id\":\"1\",\"type\":0,\"guild_id\":\"2\",\"name\":\"general\",\"position\":3}}",
        1024,
    )).?;
    try std.testing.expect(created == .create);
    try std.testing.expectEqualStrings("general", created.create.name.get().?);

    const updated = (try decode(
        aa,
        "CHANNEL_UPDATE",
        "{\"op\":0,\"t\":\"CHANNEL_UPDATE\",\"s\":2,\"d\":{\"id\":\"1\",\"type\":0}}",
        1024,
    )).?;
    try std.testing.expect(updated == .update);
    try std.testing.expect(updated.update.name.isAbsent());
    try std.testing.expect(updated.update.topic.isAbsent());

    const cleared = (try decode(
        aa,
        "CHANNEL_UPDATE",
        "{\"op\":0,\"t\":\"CHANNEL_UPDATE\",\"s\":3,\"d\":{\"id\":\"1\",\"type\":0,\"topic\":null}}",
        1024,
    )).?;
    try std.testing.expect(cleared.update.topic.isNull());
}

test "channel info and pins update decode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const aa = arena.allocator();

    const info = (try decode(
        aa,
        "CHANNEL_INFO",
        "{\"op\":0,\"t\":\"CHANNEL_INFO\",\"s\":4,\"d\":{\"guild_id\":\"2\",\"channels\":[{\"id\":\"1\",\"status\":\"live\",\"voice_start_time\":1700000000}]}}",
        1024,
    )).?;
    try std.testing.expect(info == .info);
    try std.testing.expectEqualStrings("live", info.info.channels[0].status.get().?);
    try std.testing.expectEqual(@as(?i64, 1_700_000_000), info.info.channels[0].voice_start_time.get());

    const pins = (try decode(
        aa,
        "CHANNEL_PINS_UPDATE",
        "{\"op\":0,\"t\":\"CHANNEL_PINS_UPDATE\",\"s\":5,\"d\":{\"guild_id\":\"2\",\"channel_id\":\"1\",\"last_pin_timestamp\":\"2024-01-01T00:00:00+00:00\"}}",
        1024,
    )).?;
    try std.testing.expect(pins == .pins_update);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00+00:00", pins.pins_update.last_pin_timestamp.get().?);
}

test "unknown channel event falls back to the caller" {
    try std.testing.expect((try decode(
        std.testing.allocator,
        "VOICE_STATE_UPDATE",
        "{\"op\":0,\"t\":\"VOICE_STATE_UPDATE\",\"d\":{}}",
        1024,
    )) == null);
}

fn parseCreate(allocator: std.mem.Allocator, envelope: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const event = try decode(arena.allocator(), "CHANNEL_CREATE", envelope, 1024);
    try std.testing.expect(event != null);
}

test "allocation failure during dispatch is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseCreate,
        .{"{\"op\":0,\"t\":\"CHANNEL_CREATE\",\"d\":{\"id\":\"1\",\"type\":0,\"guild_id\":\"2\",\"name\":\"general\",\"permission_overwrites\":[{\"id\":\"3\",\"type\":0,\"allow\":\"1\",\"deny\":\"2\"}]}}"},
    );
}

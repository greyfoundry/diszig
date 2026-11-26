//! Gateway dispatch event surface.
//!
//! READY, RESUMED and the channel event batch are typed. Every other event is
//! delivered as `Raw` with the original gateway envelope. EVENT-* packages add
//! typed payloads without changing the queue or ordering contract.
//!
//! `decode` takes an arena allocator: typed slices borrow from that arena and
//! remain valid until the dispatcher ends the callback. `Raw` slices borrow the
//! dispatcher's payload copy for the same duration.

const std = @import("std");
const protocol = @import("protocol");

pub const channels = @import("channels.zig");
pub const commands = @import("commands.zig");
pub const guilds = @import("guilds.zig");
pub const integrations = @import("integrations.zig");

pub const Ready = struct {
    session_id: []const u8,
    resume_gateway_url: []const u8,
    sequence: ?i64,
};

pub const Raw = struct {
    name: []const u8,
    sequence: ?i64,
    /// The complete gateway payload, including `op`, `t`, `s` and `d`.
    payload: []const u8,
};

pub const Event = union(enum) {
    ready: Ready,
    resumed: void,
    channel_create: channels.Channel,
    channel_update: channels.Channel,
    channel_delete: channels.Channel,
    channel_info: channels.ChannelInfo,
    channel_pins_update: channels.ChannelPinsUpdate,
    application_command_permissions_update: commands.GuildApplicationCommandPermissions,
    guild_create: guilds.Guild,
    guild_update: guilds.Guild,
    guild_delete: guilds.Guild,
    guild_audit_log_entry_create: guilds.AuditLogEntry,
    guild_ban_add: guilds.GuildBan,
    guild_ban_remove: guilds.GuildBan,
    integration_create: integrations.Integration,
    integration_update: integrations.Integration,
    integration_delete: integrations.IntegrationDelete,
    raw: Raw,
};

/// Classifies one dispatch. `allocator` should be an arena that the caller
/// resets after the callback. An unknown or not-yet-typed event never fails:
/// it becomes `.raw`.
pub fn decode(
    allocator: std.mem.Allocator,
    name: []const u8,
    sequence: ?i64,
    payload: []const u8,
    max_bytes: usize,
) !Event {
    if (std.mem.eql(u8, name, "RESUMED")) return .resumed;
    if (!std.mem.eql(u8, name, "READY")) {
        if (try channels.decode(allocator, name, payload, max_bytes)) |event| {
            return switch (event) {
                .create => |channel| .{ .channel_create = channel },
                .update => |channel| .{ .channel_update = channel },
                .delete => |channel| .{ .channel_delete = channel },
                .info => |info| .{ .channel_info = info },
                .pins_update => |pins| .{ .channel_pins_update = pins },
            };
        }
        if (try commands.decode(allocator, name, payload, max_bytes)) |event| {
            return switch (event) {
                .permissions_update => |permissions| .{
                    .application_command_permissions_update = permissions,
                },
            };
        }
        if (try guilds.decode(allocator, name, payload, max_bytes)) |event| {
            return switch (event) {
                .create => |guild| .{ .guild_create = guild },
                .update => |guild| .{ .guild_update = guild },
                .delete => |guild| .{ .guild_delete = guild },
                .audit_log_entry_create => |entry| .{ .guild_audit_log_entry_create = entry },
                .ban_add => |ban| .{ .guild_ban_add = ban },
                .ban_remove => |ban| .{ .guild_ban_remove = ban },
            };
        }
        if (try integrations.decode(allocator, name, payload, max_bytes)) |event| {
            return switch (event) {
                .create => |integration| .{ .integration_create = integration },
                .update => |integration| .{ .integration_update = integration },
                .delete => |deleted| .{ .integration_delete = deleted },
            };
        }
        return .{ .raw = .{ .name = name, .sequence = sequence, .payload = payload } };
    }

    if (payload.len > max_bytes) return error.InputTooLarge;
    try protocol.json.checkDepth(payload, 128);
    const Wire = struct {
        d: struct {
            session_id: []const u8,
            resume_gateway_url: []const u8,
        },
    };
    const wire = try std.json.parseFromSliceLeaky(Wire, allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    return .{ .ready = .{
        .session_id = wire.d.session_id,
        .resume_gateway_url = wire.d.resume_gateway_url,
        .sequence = sequence,
    } };
}

test "channel events are typed through the shared dispatcher" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const event = try decode(
        arena.allocator(),
        "CHANNEL_CREATE",
        1,
        "{\"op\":0,\"t\":\"CHANNEL_CREATE\",\"s\":1,\"d\":{\"id\":\"1\",\"type\":0}}",
        1024,
    );
    try std.testing.expect(event == .channel_create);
    try std.testing.expectEqual(@as(u64, 1), event.channel_create.id.toU64());
}

test "ready is typed and borrows from the arena" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const event = try decode(
        arena.allocator(),
        "READY",
        3,
        "{\"op\":0,\"t\":\"READY\",\"s\":3,\"d\":{\"session_id\":\"s-1\",\"resume_gateway_url\":\"wss://r\"}}",
        1024,
    );
    try std.testing.expect(event == .ready);
    try std.testing.expectEqualStrings("s-1", event.ready.session_id);
    try std.testing.expectEqualStrings("wss://r", event.ready.resume_gateway_url);
    try std.testing.expectEqual(@as(?i64, 3), event.ready.sequence);
}

test "unknown events fall back to raw without parsing d" {
    const payload = "{\"op\":0,\"t\":\"FUTURE_EVENT\",\"s\":9,\"d\":{\"x\":[1,2,3]}}";
    const event = try decode(std.testing.allocator, "FUTURE_EVENT", 9, payload, 1024);
    try std.testing.expect(event == .raw);
    try std.testing.expectEqualStrings("FUTURE_EVENT", event.raw.name);
    try std.testing.expectEqualStrings(payload, event.raw.payload);
    try std.testing.expectEqual(@as(?i64, 9), event.raw.sequence);
}

test "resumed is typed" {
    const event = try decode(std.testing.allocator, "RESUMED", 10, "{\"op\":0,\"t\":\"RESUMED\"}", 1024);
    try std.testing.expect(event == .resumed);
}

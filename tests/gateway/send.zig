//! Gateway send contracts: intent safety, local validation, Rate Limited
//! metadata and the bounded per-connection send scheduler.

const std = @import("std");
const diszig = @import("diszig");
const send = diszig.gateway.send;
const intents = diszig.intents;

test "unapproved privileged intents fail locally with an explicit error" {
    var buffer: [512]u8 = undefined;
    try std.testing.expectError(
        error.PrivilegedIntentNotAcknowledged,
        send.identify(&buffer, .{
            .token = "bot.token",
            .intents = intents.guild_presences,
        }),
    );
    try std.testing.expectError(
        error.PrivilegedIntentNotAcknowledged,
        send.identify(&buffer, .{
            .token = "bot.token",
            .intents = intents.message_content,
        }),
    );
    const ok = try send.identify(&buffer, .{
        .token = "bot.token",
        .intents = intents.guild_presences | intents.guilds,
        .allow_privileged = true,
    });
    try std.testing.expect(std.mem.indexOf(u8, ok, "\"intents\":257") != null);
}

test "oversized member query and invalid nonce are local errors" {
    var buffer: [512]u8 = undefined;
    try std.testing.expectError(
        error.LimitTooLarge,
        send.writeGuildMembers(&buffer, .{ .guild_id = 1, .query = "prefix", .limit = 101 }),
    );
    try std.testing.expectError(
        error.NonceTooLong,
        send.writeGuildMembers(&buffer, .{
            .guild_id = 1,
            .query = "",
            .nonce = "012345678901234567890123456789012",
        }),
    );
    try std.testing.expectError(
        error.MissingSelector,
        send.writeGuildMembers(&buffer, .{ .guild_id = 1 }),
    );
    var too_many: [101]u64 = @splat(0);
    try std.testing.expectError(
        error.TooManyUserIds,
        send.writeGuildMembers(&buffer, .{
            .guild_id = 1,
            .user_ids = &too_many,
        }),
    );
}

test "rate limited metadata names the opcode and nonce, not an HTTP status" {
    const payload =
        \\{"op":0,"t":"RATE_LIMITED","s":81,"d":{"opcode":8,"retry_after":2.25,"meta":{"guild_id":"41771983444115456","nonce":"req-9"}}}
    ;
    const limited = try send.parseRateLimited(std.testing.allocator, payload, 1024);
    try std.testing.expectEqual(@as(u8, 8), limited.opcode);
    try std.testing.expectEqual(@as(u64, 2250), limited.retry_after_ms);
    try std.testing.expectEqual(@as(?u64, 41771983444115456), limited.guild_id);
    try std.testing.expectEqualStrings("req-9", limited.nonceValue());
    // No HTTP status or global flag is part of this type.
    try std.testing.expect(!@hasField(send.RateLimited, "status"));
    try std.testing.expect(!@hasField(send.RateLimited, "global"));
}

test "presence flood is bounded while critical liveness continues" {
    var limiter = send.SendLimiter.init(1000);
    var i: u32 = 0;
    while (i < 120) : (i += 1) try limiter.trySend(1000, false);
    try std.testing.expectError(error.RateLimited, limiter.trySend(1000, false));
    try std.testing.expectEqual(@as(u64, 60_000), limiter.retryAfterMs(1000));
    // Heartbeat/Identify/Resume are critical.
    try limiter.trySend(1000, true);
    try limiter.trySend(60_999, true);
    try std.testing.expectError(error.RateLimited, limiter.trySend(60_999, false));
    try limiter.trySend(61_000, false);
    try std.testing.expectEqual(@as(u32, 119), limiter.remaining(61_000));
}

test "all documented send builders produce their opcodes" {
    var buffer: [1024]u8 = undefined;

    const soundboard = try send.writeSoundboardSounds(&buffer, &.{ 1, 2 });
    try std.testing.expect(std.mem.indexOf(u8, soundboard, "\"op\":31") != null);

    const info = try send.writeChannelInfo(&buffer, 3, &.{.status});
    try std.testing.expect(std.mem.indexOf(u8, info, "\"op\":43") != null);

    const voice = try send.writeVoiceState(&buffer, .{
        .guild_id = 3,
        .channel_id = 4,
        .self_mute = false,
        .self_deaf = true,
    });
    try std.testing.expect(std.mem.indexOf(u8, voice, "\"op\":4") != null);
    try std.testing.expect(std.mem.indexOf(u8, voice, "\"channel_id\":\"4\"") != null);

    const presence = try send.writePresence(&buffer, .{
        .activities = &.{.{ .name = "testing", .kind = .watching }},
        .status = .idle,
    });
    try std.testing.expect(std.mem.indexOf(u8, presence, "\"op\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, presence, "\"type\":3") != null);

    const heartbeat = try send.writeHeartbeat(&buffer, null);
    try std.testing.expectEqualStrings("{\"op\":1,\"d\":null}", heartbeat);

    const resume_payload = try send.resume_session(&buffer, "bot.token", "session-1", 9);
    try std.testing.expect(std.mem.indexOf(u8, resume_payload, "\"op\":6") != null);
}

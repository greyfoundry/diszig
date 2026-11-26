//! Gateway send payloads, intent-safe validation and the connection send budget.
//!
//! Every builder writes into a caller-owned buffer; the caller sends it through
//! the transport, which copies and masks it. Credentials are validated as
//! token-safe characters, so a token cannot inject JSON. Identify and Resume
//! remain in `recovery.zig` and are re-exported here so all documented send
//! rows are reachable from one module.

const std = @import("std");
const protocol = @import("protocol");
const recovery = @import("recovery.zig");

pub const BuildError = error{
    NoSpaceLeft,
    MissingSelector,
    ConflictingSelector,
    QueryTooLong,
    LimitTooLarge,
    TooManyUserIds,
    TooManyGuildIds,
    NoGuildIds,
    NonceTooLong,
    InvalidNonce,
    NoFields,
    DuplicateField,
    TooManyActivities,
    ActivityTextTooLong,
    InvalidRetryAfter,
    InvalidSnowflake,
    OutOfMemory,
    InputTooLarge,
};

pub const identify = recovery.writeIdentify;
pub const resume_session = recovery.writeResume;

/// Discord allows 120 gateway events per connection per 60 seconds. Heartbeats
/// and other liveness frames may still be sent when non-critical capacity is
/// exhausted; they are counted but never blocked.
pub const SendLimiter = struct {
    limit: u32,
    window_ms: u64,
    used: u32,
    window_start_ms: u64,

    pub fn init(now_ms: u64) SendLimiter {
        return .{ .limit = 120, .window_ms = 60_000, .used = 0, .window_start_ms = now_ms };
    }

    pub fn trySend(self: *SendLimiter, now_ms: u64, critical: bool) error{RateLimited}!void {
        self.roll(now_ms);
        if (self.used >= self.limit and !critical) return error.RateLimited;
        self.used +|= 1;
    }

    pub fn retryAfterMs(self: *SendLimiter, now_ms: u64) u64 {
        self.roll(now_ms);
        if (self.used < self.limit) return 0;
        return (self.window_start_ms + self.window_ms) -| now_ms;
    }

    pub fn remaining(self: *SendLimiter, now_ms: u64) u32 {
        self.roll(now_ms);
        return self.limit -| self.used;
    }

    fn roll(self: *SendLimiter, now_ms: u64) void {
        if (now_ms < self.window_start_ms or now_ms - self.window_start_ms >= self.window_ms) {
            self.window_start_ms = now_ms;
            self.used = 0;
        }
    }
};

/// The server's Rate Limited dispatch (`t = "RATE_LIMITED"`) is not an HTTP 429.
/// It names the offending Gateway opcode, a retry delay and optional metadata.
pub const RateLimited = struct {
    opcode: u8,
    retry_after_ms: u64,
    guild_id: ?u64 = null,
    nonce: [32]u8 = undefined,
    nonce_len: usize = 0,

    pub fn nonceValue(self: *const RateLimited) []const u8 {
        return self.nonce[0..self.nonce_len];
    }
};

pub fn parseRateLimited(
    allocator: std.mem.Allocator,
    payload: []const u8,
    max_bytes: usize,
) !RateLimited {
    const Wire = struct {
        d: struct {
            opcode: i64,
            retry_after: f64,
            meta: ?struct {
                guild_id: ?[]const u8 = null,
                nonce: ?[]const u8 = null,
            } = null,
        },
    };
    var parsed = try protocol.json.parseBounded(Wire, allocator, payload, max_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    const d = parsed.value.d;
    if (d.opcode < 0 or d.opcode > 255) return error.InvalidRetryAfter;
    if (!(d.retry_after >= 0.0) or d.retry_after > 86_400.0) return error.InvalidRetryAfter;
    const retry_after_ms: u64 = @intFromFloat(@ceil(d.retry_after * 1000.0));

    var result = RateLimited{
        .opcode = @intCast(d.opcode),
        .retry_after_ms = retry_after_ms,
    };
    if (d.meta) |meta| {
        if (meta.guild_id) |guild_id| {
            result.guild_id = std.fmt.parseInt(u64, guild_id, 10) catch
                return error.InvalidSnowflake;
        }
        if (meta.nonce) |nonce| {
            if (nonce.len > result.nonce.len) return error.NonceTooLong;
            @memcpy(result.nonce[0..nonce.len], nonce);
            result.nonce_len = nonce.len;
        }
    }
    return result;
}

pub const Field = enum {
    status,
    voice_start_time,

    fn text(self: Field) []const u8 {
        return switch (self) {
            .status => "status",
            .voice_start_time => "voice_start_time",
        };
    }
};

pub const GuildMembers = struct {
    guild_id: u64,
    query: ?[]const u8 = null,
    limit: u32 = 0,
    presences: bool = false,
    user_ids: []const u64 = &.{},
    nonce: ?[]const u8 = null,
};

pub const VoiceState = struct {
    guild_id: u64,
    channel_id: ?u64 = null,
    self_mute: bool = false,
    self_deaf: bool = false,
};

pub const PresenceStatus = enum {
    online,
    dnd,
    idle,
    invisible,
    offline,

    fn text(self: PresenceStatus) []const u8 {
        return @tagName(self);
    }
};

pub const ActivityKind = enum(u8) {
    playing = 0,
    streaming = 1,
    listening = 2,
    watching = 3,
    custom = 4,
    competing = 5,
};

pub const Activity = struct {
    name: []const u8,
    kind: ActivityKind = .playing,
    url: ?[]const u8 = null,
    state: ?[]const u8 = null,
    details: ?[]const u8 = null,
};

pub const Presence = struct {
    since: ?i64 = null,
    activities: []const Activity = &.{},
    status: PresenceStatus = .online,
    afk: bool = false,
};

fn validateNonce(nonce: []const u8) BuildError!void {
    if (nonce.len > 32) return error.NonceTooLong;
    for (nonce) |c| {
        if (c < 0x20 or c == 0x7f or c == '"' or c == '\\') return error.InvalidNonce;
    }
}

fn wAll(writer: *std.Io.Writer, bytes: []const u8) BuildError!void {
    writer.writeAll(bytes) catch return error.NoSpaceLeft;
}

fn wPrint(writer: *std.Io.Writer, comptime fmt: []const u8, args: anytype) BuildError!void {
    writer.print(fmt, args) catch return error.NoSpaceLeft;
}

fn wByte(writer: *std.Io.Writer, byte: u8) BuildError!void {
    writer.writeByte(byte) catch return error.NoSpaceLeft;
}

fn wString(writer: *std.Io.Writer, value: []const u8) BuildError!void {
    try wByte(writer, '"');
    for (value) |c| switch (c) {
        '"' => try wAll(writer, "\\\""),
        '\\' => try wAll(writer, "\\\\"),
        0x08 => try wAll(writer, "\\b"),
        0x0c => try wAll(writer, "\\f"),
        '\n' => try wAll(writer, "\\n"),
        '\r' => try wAll(writer, "\\r"),
        '\t' => try wAll(writer, "\\t"),
        0...0x07, 0x0b, 0x0e...0x1f => try wPrint(writer, "\\u{X:0>4}", .{c}),
        else => try wByte(writer, c),
    };
    try wByte(writer, '"');
}

pub fn writeGuildMembers(buffer: []u8, request: GuildMembers) BuildError![]const u8 {
    const has_query = request.query != null;
    const has_ids = request.user_ids.len > 0;
    if (!has_query and !has_ids) return error.MissingSelector;
    if (has_query and has_ids) return error.ConflictingSelector;
    if (request.query) |query| {
        if (query.len > 100) return error.QueryTooLong;
        if (request.limit > 1000) return error.LimitTooLarge;
        if (query.len > 0 and request.limit > 100) return error.LimitTooLarge;
    }
    if (request.user_ids.len > 100) return error.TooManyUserIds;
    if (request.nonce) |nonce| try validateNonce(nonce);

    var writer = std.Io.Writer.fixed(buffer);
    try wPrint(&writer, "{{\"op\":8,\"d\":{{\"guild_id\":\"{d}\"", .{request.guild_id});
    if (request.query) |query| {
        try wAll(&writer, ",\"query\":");
        try wString(&writer, query);
        try wPrint(&writer, ",\"limit\":{d}", .{request.limit});
    }
    if (has_ids) {
        try wAll(&writer, ",\"user_ids\":[");
        for (request.user_ids, 0..) |id, index| {
            if (index > 0) try wByte(&writer, ',');
            try wPrint(&writer, "\"{d}\"", .{id});
        }
        try wByte(&writer, ']');
    }
    if (request.presences) try wAll(&writer, ",\"presences\":true");
    if (request.nonce) |nonce| {
        try wAll(&writer, ",\"nonce\":");
        try wString(&writer, nonce);
    }
    try wAll(&writer, "}}");
    return writer.buffered();
}

pub fn writeSoundboardSounds(buffer: []u8, guild_ids: []const u64) BuildError![]const u8 {
    if (guild_ids.len == 0) return error.NoGuildIds;
    if (guild_ids.len > 100) return error.TooManyGuildIds;
    var writer = std.Io.Writer.fixed(buffer);
    try wAll(&writer, "{\"op\":31,\"d\":{\"guild_ids\":[");
    for (guild_ids, 0..) |id, index| {
        if (index > 0) try wByte(&writer, ',');
        try wPrint(&writer, "\"{d}\"", .{id});
    }
    try wAll(&writer, "]}}");
    return writer.buffered();
}

pub fn writeChannelInfo(buffer: []u8, guild_id: u64, fields: []const Field) BuildError![]const u8 {
    if (fields.len == 0) return error.NoFields;
    for (fields, 0..) |field, index| {
        for (fields[0..index]) |earlier| {
            if (earlier == field) return error.DuplicateField;
        }
    }
    var writer = std.Io.Writer.fixed(buffer);
    try wPrint(&writer, "{{\"op\":43,\"d\":{{\"guild_id\":\"{d}\",\"fields\":[", .{guild_id});
    for (fields, 0..) |field, index| {
        if (index > 0) try wByte(&writer, ',');
        try wString(&writer, field.text());
    }
    try wAll(&writer, "]}}");
    return writer.buffered();
}

pub fn writeVoiceState(buffer: []u8, state: VoiceState) BuildError![]const u8 {
    var writer = std.Io.Writer.fixed(buffer);
    try wPrint(&writer, "{{\"op\":4,\"d\":{{\"guild_id\":\"{d}\",", .{state.guild_id});
    if (state.channel_id) |channel_id| {
        try wPrint(&writer, "\"channel_id\":\"{d}\",", .{channel_id});
    } else {
        try wAll(&writer, "\"channel_id\":null,");
    }
    try wPrint(&writer, "\"self_mute\":{s},\"self_deaf\":{s}}}}}", .{
        if (state.self_mute) "true" else "false",
        if (state.self_deaf) "true" else "false",
    });
    return writer.buffered();
}

pub fn writePresence(buffer: []u8, presence: Presence) BuildError![]const u8 {
    if (presence.activities.len > 10) return error.TooManyActivities;
    var writer = std.Io.Writer.fixed(buffer);
    try wAll(&writer, "{\"op\":3,\"d\":{\"since\":");
    if (presence.since) |since| {
        try wPrint(&writer, "{d}", .{since});
    } else {
        try wAll(&writer, "null");
    }
    try wAll(&writer, ",\"activities\":[");
    for (presence.activities, 0..) |activity, index| {
        if (index > 0) try wByte(&writer, ',');
        try writeActivity(&writer, activity);
    }
    try wAll(&writer, "],\"status\":");
    try wString(&writer, presence.status.text());
    try wPrint(&writer, ",\"afk\":{s}}}}}", .{if (presence.afk) "true" else "false"});
    return writer.buffered();
}

fn writeActivity(writer: *std.Io.Writer, activity: Activity) BuildError!void {
    if (activity.name.len == 0 or activity.name.len > 128) return error.ActivityTextTooLong;
    try wAll(writer, "{\"name\":");
    try wString(writer, activity.name);
    try wPrint(writer, ",\"type\":{d}", .{@backingInt(activity.kind)});
    if (activity.url) |url| {
        if (url.len > 256) return error.ActivityTextTooLong;
        try wAll(writer, ",\"url\":");
        try wString(writer, url);
    }
    if (activity.state) |state| {
        if (state.len > 128) return error.ActivityTextTooLong;
        try wAll(writer, ",\"state\":");
        try wString(writer, state);
    }
    if (activity.details) |details| {
        if (details.len > 128) return error.ActivityTextTooLong;
        try wAll(writer, ",\"details\":");
        try wString(writer, details);
    }
    try wByte(writer, '}');
}

pub fn writeHeartbeat(buffer: []u8, sequence: ?i64) BuildError![]const u8 {
    return std.fmt.bufPrint(buffer, "{{\"op\":1,\"d\":{?d}}}", .{sequence}) catch
        error.NoSpaceLeft;
}

test "intents are validated and privileged intents need acknowledgement" {
    var buffer: [512]u8 = undefined;
    try std.testing.expectError(
        error.PrivilegedIntentNotAcknowledged,
        recovery.writeIdentify(&buffer, .{
            .token = "bot.token",
            .intents = protocol.intents.guild_members,
        }),
    );
    const payload = try recovery.writeIdentify(&buffer, .{
        .token = "bot.token",
        .intents = protocol.intents.guild_members,
        .allow_privileged = true,
    });
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"intents\":2") != null);
    try std.testing.expectError(
        error.UnknownIntentBits,
        recovery.writeIdentify(&buffer, .{ .token = "bot.token", .intents = 1 << 63 }),
    );
}

test "guild member request validates selectors and nonce" {
    var buffer: [512]u8 = undefined;
    try std.testing.expectError(
        error.ConflictingSelector,
        writeGuildMembers(&buffer, .{ .guild_id = 1 }),
    );
    try std.testing.expectError(
        error.ConflictingSelector,
        writeGuildMembers(&buffer, .{ .guild_id = 1, .query = "a", .user_ids = &.{2} }),
    );
    try std.testing.expectError(
        error.LimitTooLarge,
        writeGuildMembers(&buffer, .{ .guild_id = 1, .query = "a", .limit = 101 }),
    );
    try std.testing.expectError(
        error.InvalidNonce,
        writeGuildMembers(&buffer, .{ .guild_id = 1, .query = "", .nonce = "bad\"nonce" }),
    );

    const request = try writeGuildMembers(&buffer, .{
        .guild_id = 41771983444115456,
        .query = "",
        .limit = 0,
        .presences = true,
        .nonce = "req-1",
    });
    try std.testing.expect(std.mem.indexOf(u8, request, "\"op\":8") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"guild_id\":\"41771983444115456\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"presences\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, request, "\"nonce\":\"req-1\"") != null);

    const by_ids = try writeGuildMembers(&buffer, .{ .guild_id = 1, .user_ids = &.{ 2, 3 } });
    try std.testing.expect(std.mem.indexOf(u8, by_ids, "\"user_ids\":[\"2\",\"3\"]") != null);
}

test "soundboard and channel info payloads" {
    var buffer: [512]u8 = undefined;
    const soundboard = try writeSoundboardSounds(&buffer, &.{ 1, 2 });
    try std.testing.expect(std.mem.indexOf(u8, soundboard, "\"op\":31") != null);
    try std.testing.expect(std.mem.indexOf(u8, soundboard, "\"guild_ids\":[\"1\",\"2\"]") != null);
    try std.testing.expectError(error.NoGuildIds, writeSoundboardSounds(&buffer, &.{}));

    const info = try writeChannelInfo(&buffer, 9, &.{ .status, .voice_start_time });
    try std.testing.expect(std.mem.indexOf(u8, info, "\"op\":43") != null);
    try std.testing.expect(std.mem.indexOf(u8, info, "\"fields\":[\"status\",\"voice_start_time\"]") != null);
    try std.testing.expectError(error.NoFields, writeChannelInfo(&buffer, 9, &.{}));
    try std.testing.expectError(
        error.DuplicateField,
        writeChannelInfo(&buffer, 9, &.{ .status, .status }),
    );
}

test "voice state and presence payloads" {
    var buffer: [1024]u8 = undefined;
    const voice = try writeVoiceState(&buffer, .{
        .guild_id = 1,
        .channel_id = null,
        .self_mute = true,
        .self_deaf = false,
    });
    try std.testing.expect(std.mem.indexOf(u8, voice, "\"channel_id\":null") != null);
    try std.testing.expect(std.mem.indexOf(u8, voice, "\"self_mute\":true") != null);

    const presence = try writePresence(&buffer, .{
        .since = 91879201,
        .status = .dnd,
        .afk = false,
        .activities = &.{.{
            .name = "Cards \"Against\" Humanity",
            .kind = .playing,
            .state = "in a lobby",
        }},
    });
    try std.testing.expect(std.mem.indexOf(u8, presence, "\"op\":3") != null);
    try std.testing.expect(std.mem.indexOf(u8, presence, "\"status\":\"dnd\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, presence, "Cards \\\"Against\\\" Humanity") != null);
    try std.testing.expect(std.mem.indexOf(u8, presence, "\"afk\":false") != null);
}

test "rate limited dispatch is parsed distinctly from REST 429" {
    const payload =
        \\{"op":0,"t":"RATE_LIMITED","d":{"opcode":8,"retry_after":1.5,"meta":{"guild_id":"42","nonce":"abc"}}}
    ;
    const limited = try parseRateLimited(std.testing.allocator, payload, 1024);
    try std.testing.expectEqual(@as(u8, 8), limited.opcode);
    try std.testing.expectEqual(@as(u64, 1500), limited.retry_after_ms);
    try std.testing.expectEqual(@as(?u64, 42), limited.guild_id);
    try std.testing.expectEqualStrings("abc", limited.nonceValue());
}

test "connection send budget is bounded but critical sends continue" {
    var limiter = SendLimiter.init(0);
    var i: u32 = 0;
    while (i < 120) : (i += 1) try limiter.trySend(0, false);
    try std.testing.expectError(error.RateLimited, limiter.trySend(0, false));
    try std.testing.expectEqual(@as(u32, 0), limiter.remaining(0));
    try std.testing.expectEqual(@as(u64, 60_000), limiter.retryAfterMs(0));
    // A heartbeat may still go out.
    try limiter.trySend(0, true);
    // A new window restores the budget.
    try limiter.trySend(60_000, false);
    try std.testing.expectEqual(@as(u32, 119), limiter.remaining(60_000));
}

test "heartbeat payload carries null or the last sequence" {
    var buffer: [64]u8 = undefined;
    try std.testing.expectEqualStrings("{\"op\":1,\"d\":null}", try writeHeartbeat(&buffer, null));
    try std.testing.expectEqualStrings("{\"op\":1,\"d\":7}", try writeHeartbeat(&buffer, 7));
}

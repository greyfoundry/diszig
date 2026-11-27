//! Voice gateway control and negotiation (transport-agnostic).
//!
//! Covers the documented voice opcode inventory, close classification, state/
//! server correlation, transport-encryption negotiation and the control payload
//! builders/parsers. It does not open a socket, send UDP or process audio; the
//! DAVE binary opcodes are framed and passed through for a later libdave phase.

const std = @import("std");
const protocol = @import("protocol");
const json = protocol.json;
const Snowflake = protocol.Snowflake;

pub const Error = error{
    InvalidUpdate,
    MissingSession,
    InvalidEndpoint,
    InvalidCredential,
    InvalidPort,
    InvalidSpeaking,
    InvalidSinkValue,
    DuplicateSsrc,
    TooManySsrc,
    NoSupportedEncryptionMode,
    BufferTooSmall,
    UnsupportedOpcode,
    MissingSeq,
};

/// Every documented voice opcode, including the DAVE range.
pub const Opcode = enum(u8) {
    identify = 0,
    select_protocol = 1,
    ready = 2,
    heartbeat = 3,
    session_description = 4,
    speaking = 5,
    heartbeat_ack = 6,
    resume_session = 7,
    hello = 8,
    resumed = 9,
    clients_connect = 11,
    client_disconnect = 13,
    media_sink_wants = 15,
    dave_prepare_transition = 21,
    dave_execute_transition = 22,
    dave_transition_ready = 23,
    dave_prepare_epoch = 24,
    dave_mls_external_sender = 25,
    dave_mls_key_package = 26,
    dave_mls_proposals = 27,
    dave_mls_commit_welcome = 28,
    dave_mls_announce_commit_transition = 29,
    dave_mls_welcome = 30,
    dave_mls_invalid_commit_welcome = 31,

    /// Binary WebSocket payload instead of JSON text.
    pub fn isBinary(self: Opcode) bool {
        return switch (self) {
            .dave_mls_external_sender,
            .dave_mls_key_package,
            .dave_mls_proposals,
            .dave_mls_commit_welcome,
            .dave_mls_announce_commit_transition,
            .dave_mls_welcome,
            => true,
            else => false,
        };
    }

    /// Opcodes a client may send. Server-only opcodes are rejected by the
    /// builders so a caller cannot emit an invalid direction.
    pub fn clientMaySend(self: Opcode) bool {
        return switch (self) {
            .identify,
            .select_protocol,
            .heartbeat,
            .speaking,
            .resume_session,
            .media_sink_wants,
            .dave_transition_ready,
            .dave_mls_key_package,
            .dave_mls_commit_welcome,
            .dave_mls_invalid_commit_welcome,
            => true,
            else => false,
        };
    }

    pub fn fromInt(value: u8) ?Opcode {
        return switch (value) {
            0 => .identify,
            1 => .select_protocol,
            2 => .ready,
            3 => .heartbeat,
            4 => .session_description,
            5 => .speaking,
            6 => .heartbeat_ack,
            7 => .resume_session,
            8 => .hello,
            9 => .resumed,
            11 => .clients_connect,
            13 => .client_disconnect,
            15 => .media_sink_wants,
            21 => .dave_prepare_transition,
            22 => .dave_execute_transition,
            23 => .dave_transition_ready,
            24 => .dave_prepare_epoch,
            25 => .dave_mls_external_sender,
            26 => .dave_mls_key_package,
            27 => .dave_mls_proposals,
            28 => .dave_mls_commit_welcome,
            29 => .dave_mls_announce_commit_transition,
            30 => .dave_mls_welcome,
            31 => .dave_mls_invalid_commit_welcome,
            else => null,
        };
    }
};

pub const CloseAction = enum {
    /// Do not reconnect; the session or credentials are invalid.
    stop,
    /// Reconnect and attempt Opcode 7 Resume.
    resume_session,
    /// Start a new session; resume is not usable.
    reconnect,
};

/// Documented voice close codes. Unknown codes are handled conservatively by
/// the caller as a bounded reconnect, never as a silent success.
pub fn classifyClose(code: u16) CloseAction {
    return switch (code) {
        1000, 4001, 4002, 4003, 4004, 4005, 4011, 4012, 4014, 4016, 4017, 4020, 4021, 4022 => .stop,
        4015 => .resume_session,
        4006, 4009 => .reconnect,
        else => .reconnect,
    };
}

pub const EncryptionMode = enum {
    aead_xchacha20_poly1305_rtpsize,
    aead_aes256_gcm_rtpsize,

    pub fn wire(self: EncryptionMode) []const u8 {
        return @tagName(self);
    }

    pub fn parse(text: []const u8) ?EncryptionMode {
        if (std.mem.eql(u8, text, "aead_xchacha20_poly1305_rtpsize")) return .aead_xchacha20_poly1305_rtpsize;
        if (std.mem.eql(u8, text, "aead_aes256_gcm_rtpsize")) return .aead_aes256_gcm_rtpsize;
        return null;
    }
};

/// Picks a documented AEAD mode from the server list. The docs prefer
/// AES-256-GCM when available and require XChaCha20-Poly1305 otherwise.
/// Unknown or empty lists fail explicitly; there is no plaintext or
/// deprecated-mode fallback.
pub fn selectEncryption(server_modes: []const []const u8) Error!EncryptionMode {
    var has_xchacha = false;
    for (server_modes) |mode| {
        if (EncryptionMode.parse(mode)) |known| {
            if (known == .aead_aes256_gcm_rtpsize) return known;
            has_xchacha = true;
        }
    }
    if (has_xchacha) return .aead_xchacha20_poly1305_rtpsize;
    return error.NoSupportedEncryptionMode;
}

/// Main-gateway VOICE_STATE_UPDATE fields used for correlation.
pub const StateUpdate = struct {
    guild_id: Snowflake,
    channel_id: ?Snowflake,
    session_id: []const u8,
    user_id: Snowflake,
};

/// Main-gateway VOICE_SERVER_UPDATE fields used for correlation.
pub const ServerUpdate = struct {
    guild_id: ?Snowflake,
    token: []const u8,
    endpoint: []const u8,
};

pub const Join = struct {
    guild_id: Snowflake,
    channel_id: ?Snowflake,
    user_id: Snowflake,
    session_id: []const u8,
    /// Borrowed from the server update; never log or persist it.
    token: []const u8,
    endpoint: []const u8,
};

/// Correlates the two main-gateway events, which may arrive in either order.
/// Only the tracked guild and local user are accepted; a null channel means the
/// user is leaving and clears pending state.
pub const Correlator = struct {
    guild_id: Snowflake,
    user_id: Snowflake,
    state: ?StateUpdate = null,
    server: ?ServerUpdate = null,

    pub fn init(guild_id: Snowflake, user_id: Snowflake) Correlator {
        return .{ .guild_id = guild_id, .user_id = user_id };
    }

    pub fn reset(self: *Correlator) void {
        self.state = null;
        self.server = null;
    }

    pub fn onState(self: *Correlator, update: StateUpdate) Error!?Join {
        if (!sameId(update.guild_id, self.guild_id) or !sameId(update.user_id, self.user_id)) {
            return null;
        }
        if (update.channel_id == null) {
            self.reset();
            return null;
        }
        if (!validOpaque(update.session_id)) return error.MissingSession;
        self.state = update;
        return self.tryJoin();
    }

    pub fn onServer(self: *Correlator, update: ServerUpdate) Error!?Join {
        if (update.guild_id) |guild_id| {
            if (!sameId(guild_id, self.guild_id)) return null;
        }
        if (!validOpaque(update.token)) return error.InvalidCredential;
        if (!validEndpoint(update.endpoint)) return error.InvalidEndpoint;
        self.server = update;
        return self.tryJoin();
    }

    fn tryJoin(self: *Correlator) ?Join {
        const state = self.state orelse return null;
        const server = self.server orelse return null;
        if (!validOpaque(state.session_id)) return null;
        return .{
            .guild_id = state.guild_id,
            .channel_id = state.channel_id,
            .user_id = state.user_id,
            .session_id = state.session_id,
            .token = server.token,
            .endpoint = server.endpoint,
        };
    }
};

/// Normalizes a voice server endpoint into `wss://host/?v=8`. Endpoints arrive
/// without a scheme and may already contain a query.
pub fn webSocketUrl(endpoint: []const u8, buffer: []u8) Error![]const u8 {
    if (!validEndpoint(endpoint)) return error.InvalidEndpoint;
    const host = if (std.mem.startsWith(u8, endpoint, "wss://"))
        endpoint
    else if (std.mem.startsWith(u8, endpoint, "ws://"))
        endpoint
    else
        null;
    const separator: []const u8 = if (std.mem.indexOfScalar(u8, endpoint, '?') != null) "&" else "?";
    if (host) |full| {
        return std.fmt.bufPrint(buffer, "{s}{s}v=8", .{ full, separator }) catch return error.BufferTooSmall;
    }
    return std.fmt.bufPrint(buffer, "wss://{s}{s}v=8", .{ endpoint, separator }) catch return error.BufferTooSmall;
}

pub const Identify = struct {
    server_id: Snowflake,
    user_id: Snowflake,
    session_id: []const u8,
    /// Borrowed callback credential; never log it.
    token: []const u8,
    /// Zero or null omits the field, which means no DAVE support.
    max_dave_protocol_version: ?u16 = null,
};

pub fn writeIdentify(buffer: []u8, identify: Identify) Error![]const u8 {
    if (!validOpaque(identify.session_id) or !validOpaque(identify.token)) return error.InvalidCredential;
    if (identify.max_dave_protocol_version) |version| {
        if (version == 0) {
            return std.fmt.bufPrint(
                buffer,
                "{{\"op\":0,\"d\":{{\"server_id\":\"{d}\",\"user_id\":\"{d}\",\"session_id\":\"{s}\",\"token\":\"{s}\"}}}}",
                .{ identify.server_id.toU64(), identify.user_id.toU64(), identify.session_id, identify.token },
            ) catch return error.BufferTooSmall;
        }
        return std.fmt.bufPrint(
            buffer,
            "{{\"op\":0,\"d\":{{\"server_id\":\"{d}\",\"user_id\":\"{d}\",\"session_id\":\"{s}\",\"token\":\"{s}\",\"max_dave_protocol_version\":{d}}}}}",
            .{
                identify.server_id.toU64(),
                identify.user_id.toU64(),
                identify.session_id,
                identify.token,
                version,
            },
        ) catch return error.BufferTooSmall;
    }
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":0,\"d\":{{\"server_id\":\"{d}\",\"user_id\":\"{d}\",\"session_id\":\"{s}\",\"token\":\"{s}\"}}}}",
        .{ identify.server_id.toU64(), identify.user_id.toU64(), identify.session_id, identify.token },
    ) catch return error.BufferTooSmall;
}

pub const SelectProtocol = struct {
    address: []const u8,
    port: u16,
    mode: EncryptionMode,
};

pub fn writeSelectProtocol(buffer: []u8, select: SelectProtocol) Error![]const u8 {
    if (select.port == 0) return error.InvalidPort;
    if (!validEndpoint(select.address)) return error.InvalidEndpoint;
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":1,\"d\":{{\"protocol\":\"udp\",\"data\":{{\"address\":\"{s}\",\"port\":{d},\"mode\":\"{s}\"}}}}}}",
        .{ select.address, select.port, select.mode.wire() },
    ) catch return error.BufferTooSmall;
}

pub const Heartbeat = struct {
    version: u8,
    nonce: i64,
    /// Last received sequence; omitted (-1) when none was seen. Required from
    /// voice gateway version 8.
    seq_ack: ?i64 = null,
};

pub fn writeHeartbeat(buffer: []u8, heartbeat: Heartbeat) Error![]const u8 {
    if (heartbeat.version >= 8) {
        const seq_ack = heartbeat.seq_ack orelse -1;
        return std.fmt.bufPrint(
            buffer,
            "{{\"op\":3,\"d\":{{\"t\":{d},\"seq_ack\":{d}}}}}",
            .{ heartbeat.nonce, seq_ack },
        ) catch return error.BufferTooSmall;
    }
    return std.fmt.bufPrint(buffer, "{{\"op\":3,\"d\":{d}}}", .{heartbeat.nonce}) catch return error.BufferTooSmall;
}

pub const Resume = struct {
    version: u8,
    server_id: Snowflake,
    session_id: []const u8,
    token: []const u8,
    seq_ack: ?i64 = null,
};

pub fn writeResume(buffer: []u8, request: Resume) Error![]const u8 {
    if (!validOpaque(request.session_id) or !validOpaque(request.token)) return error.InvalidCredential;
    if (request.version >= 8) {
        const seq_ack = request.seq_ack orelse -1;
        return std.fmt.bufPrint(
            buffer,
            "{{\"op\":7,\"d\":{{\"server_id\":\"{d}\",\"session_id\":\"{s}\",\"token\":\"{s}\",\"seq_ack\":{d}}}}}",
            .{ request.server_id.toU64(), request.session_id, request.token, seq_ack },
        ) catch return error.BufferTooSmall;
    }
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":7,\"d\":{{\"server_id\":\"{d}\",\"session_id\":\"{s}\",\"token\":\"{s}\"}}}}",
        .{ request.server_id.toU64(), request.session_id, request.token },
    ) catch return error.BufferTooSmall;
}

pub const Speaking = struct {
    speaking: u8,
    delay: u32 = 0,
    ssrc: u32,
};

pub fn writeSpeaking(buffer: []u8, speaking: Speaking) Error![]const u8 {
    // 0 means "not speaking"; the client must send a non-zero mode before
    // sending audio, but 0 is valid for stopping.
    if (speaking.speaking & ~@as(u8, 0b111) != 0) return error.InvalidSpeaking;
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":5,\"d\":{{\"speaking\":{d},\"delay\":{d},\"ssrc\":{d}}}}}",
        .{ speaking.speaking, speaking.delay, speaking.ssrc },
    ) catch return error.BufferTooSmall;
}

pub const SsrcWant = struct {
    ssrc: u32,
    /// 0-100; 0 stops that SSRC, 100 keeps it.
    value: u8,
};

pub fn writeMediaSinkWants(buffer: []u8, any: u8, wants: []const SsrcWant) Error![]const u8 {
    if (any > 100) return error.InvalidSinkValue;
    var writer = std.Io.Writer.fixed(buffer);
    writer.writeAll("{\"op\":15,\"d\":{\"any\":") catch return error.BufferTooSmall;
    writer.print("{d}", .{any}) catch return error.BufferTooSmall;
    for (wants, 0..) |want, index| {
        if (want.value > 100) return error.InvalidSinkValue;
        for (wants[0..index]) |earlier| {
            if (earlier.ssrc == want.ssrc) return error.DuplicateSsrc;
        }
        writer.print(",\"{d}\":{d}", .{ want.ssrc, want.value }) catch return error.BufferTooSmall;
    }
    writer.writeAll("}}") catch return error.BufferTooSmall;
    return writer.buffered();
}

/// Frames a client-to-server binary payload. Client messages have no leading
/// sequence number; only the server adds one.
pub fn writeBinaryMessage(buffer: []u8, opcode: Opcode, payload: []const u8) Error![]const u8 {
    if (!opcode.isBinary() or !opcode.clientMaySend()) return error.UnsupportedOpcode;
    if (payload.len + 1 > buffer.len) return error.BufferTooSmall;
    buffer[0] = @backingInt(opcode);
    @memcpy(buffer[1 .. payload.len + 1], payload);
    return buffer[0 .. payload.len + 1];
}

pub const BinaryHeader = struct {
    sequence: ?u16,
    opcode: Opcode,
    payload: []const u8,
};

/// Parses a server-to-client binary frame: uint16 sequence then opcode.
pub fn parseBinaryHeader(frame: []const u8) Error!BinaryHeader {
    if (frame.len < 3) return error.MissingSeq;
    const sequence: u16 = (@as(u16, frame[0]) << 8) | frame[1];
    const opcode = Opcode.fromInt(frame[2]) orelse return error.UnsupportedOpcode;
    if (!opcode.isBinary()) return error.UnsupportedOpcode;
    return .{ .sequence = sequence, .opcode = opcode, .payload = frame[3..] };
}

pub const Hello = struct {
    heartbeat_interval: u32,
    version: u8,
};

pub const Ready = struct {
    ssrc: u32,
    ip: []const u8,
    port: u16,
    modes: []const []const u8,
};

pub const SessionDescription = struct {
    mode: EncryptionMode,
    /// 32-byte transport key. Treat as a credential: never log it.
    secret_key: []const u8,
    dave_protocol_version: ?u16 = null,
};

pub const HeartbeatAck = struct {
    nonce: i64,
};

pub const SpeakingUpdate = struct {
    speaking: u8,
    delay: u32,
    ssrc: u32,
};

/// Parses a JSON voice payload `{op, d, seq?}` into `T` using a caller-owned
/// arena. Slices in the result borrow that arena.
pub fn parsePayload(
    comptime T: type,
    allocator: std.mem.Allocator,
    envelope: []const u8,
    expected: Opcode,
    max_bytes: usize,
) !T {
    if (envelope.len > max_bytes) return error.InputTooLarge;
    try json.checkDepth(envelope, 128);
    const Wire = struct {
        op: u8,
        d: T,
        seq: ?i64 = null,
    };
    const wire = try std.json.parseFromSliceLeaky(Wire, allocator, envelope, .{
        .ignore_unknown_fields = true,
    });
    if (wire.op != @backingInt(expected)) return error.UnexpectedOpcode;
    return wire.d;
}

fn sameId(a: Snowflake, b: Snowflake) bool {
    return a.toU64() == b.toU64();
}

fn validOpaque(value: []const u8) bool {
    if (value.len == 0 or value.len > 512) return false;
    for (value) |c| {
        if (c == 0 or c == '\r' or c == '\n' or c == '"' or c == '\\') return false;
    }
    return true;
}

fn validEndpoint(value: []const u8) bool {
    if (value.len == 0 or value.len > 512) return false;
    for (value) |c| {
        if (c == 0 or c == '\r' or c == '\n' or c == '"' or c == '\\') return false;
    }
    return true;
}

test "voice opcode inventory and binary flags" {
    try std.testing.expectEqual(@as(u8, 31), @backingInt(Opcode.dave_mls_invalid_commit_welcome));
    try std.testing.expect(Opcode.dave_mls_external_sender.isBinary());
    try std.testing.expect(Opcode.dave_mls_welcome.isBinary());
    try std.testing.expect(!Opcode.select_protocol.isBinary());
    try std.testing.expect(Opcode.media_sink_wants.clientMaySend());
    try std.testing.expect(!Opcode.ready.clientMaySend());
}

test "close classification never resumes a fatal session" {
    try std.testing.expectEqual(CloseAction.stop, classifyClose(4014));
    try std.testing.expectEqual(CloseAction.stop, classifyClose(4022));
    try std.testing.expectEqual(CloseAction.resume_session, classifyClose(4015));
    try std.testing.expectEqual(CloseAction.reconnect, classifyClose(4006));
    try std.testing.expectEqual(CloseAction.reconnect, classifyClose(9999));
}

test "encryption negotiation prefers AES and never falls back to plaintext" {
    try std.testing.expectEqual(
        EncryptionMode.aead_aes256_gcm_rtpsize,
        try selectEncryption(&.{ "aead_xchacha20_poly1305_rtpsize", "aead_aes256_gcm_rtpsize" }),
    );
    try std.testing.expectEqual(
        EncryptionMode.aead_xchacha20_poly1305_rtpsize,
        try selectEncryption(&.{"aead_xchacha20_poly1305_rtpsize"}),
    );
    try std.testing.expectError(error.NoSupportedEncryptionMode, selectEncryption(&.{"xsalsa20_poly1305"}));
    try std.testing.expectError(error.NoSupportedEncryptionMode, selectEncryption(&.{}));
}

test "correlation accepts either order and rejects other guilds" {
    const guild = try Snowflake.parse("1");
    const other = try Snowflake.parse("2");
    const user = try Snowflake.parse("3");
    var correlator = Correlator.init(guild, user);

    const state = StateUpdate{
        .guild_id = guild,
        .channel_id = guild,
        .session_id = "session",
        .user_id = user,
    };
    try std.testing.expectEqual(@as(?Join, null), try correlator.onState(state));
    const join = (try correlator.onServer(.{
        .guild_id = guild,
        .token = "voice-token",
        .endpoint = "voice.example",
    })).?;
    try std.testing.expectEqualStrings("session", join.session_id);

    var reverse = Correlator.init(guild, user);
    try std.testing.expectEqual(@as(?Join, null), try reverse.onServer(.{
        .guild_id = guild,
        .token = "voice-token",
        .endpoint = "voice.example",
    }));
    try std.testing.expect((try reverse.onState(state)) != null);

    var mismatch = Correlator.init(guild, user);
    try std.testing.expectEqual(@as(?Join, null), try mismatch.onState(.{
        .guild_id = other,
        .channel_id = other,
        .session_id = "session",
        .user_id = user,
    }));

    var leaving = Correlator.init(guild, user);
    _ = try leaving.onState(state);
    _ = try leaving.onServer(.{ .guild_id = guild, .token = "t", .endpoint = "e" });
    try std.testing.expectEqual(@as(?Join, null), try leaving.onState(.{
        .guild_id = guild,
        .channel_id = null,
        .session_id = "",
        .user_id = user,
    }));
}

test "control payloads match the documented shapes" {
    var buffer: [1024]u8 = undefined;
    const guild = try Snowflake.parse("41771983423143937");
    const user = try Snowflake.parse("104694319306248192");

    const identify = try writeIdentify(&buffer, .{
        .server_id = guild,
        .user_id = user,
        .session_id = "my_session_id",
        .token = "my_token",
        .max_dave_protocol_version = 1,
    });
    try std.testing.expectEqualStrings(
        "{\"op\":0,\"d\":{\"server_id\":\"41771983423143937\",\"user_id\":\"104694319306248192\"," ++
            "\"session_id\":\"my_session_id\",\"token\":\"my_token\",\"max_dave_protocol_version\":1}}",
        identify,
    );

    const heartbeat = try writeHeartbeat(&buffer, .{ .version = 8, .nonce = 1501184119561, .seq_ack = 10 });
    try std.testing.expectEqualStrings("{\"op\":3,\"d\":{\"t\":1501184119561,\"seq_ack\":10}}", heartbeat);

    const resume_body = try writeResume(&buffer, .{
        .version = 8,
        .server_id = guild,
        .session_id = "my_session_id",
        .token = "my_token",
        .seq_ack = 10,
    });
    try std.testing.expect(std.mem.indexOf(u8, resume_body, "\"seq_ack\":10") != null);

    const sink = try writeMediaSinkWants(&buffer, 100, &.{.{ .ssrc = 2, .value = 0 }});
    try std.testing.expectEqualStrings("{\"op\":15,\"d\":{\"any\":100,\"2\":0}}", sink);
}

test "endpoint normalization and URL safety" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "wss://voice.example/?v=8",
        try webSocketUrl("voice.example", &buffer),
    );
    try std.testing.expectEqualStrings(
        "wss://voice.example/?x=1&v=8",
        try webSocketUrl("voice.example?x=1", &buffer),
    );
    try std.testing.expectError(error.InvalidEndpoint, webSocketUrl("voice\r\nX: y", &buffer));
}

test "binary framing uses a sequence for server frames" {
    var buffer: [32]u8 = undefined;
    const framed = try writeBinaryMessage(&buffer, .dave_mls_key_package, &.{ 1, 2, 3 });
    try std.testing.expectEqual(@as(usize, 4), framed.len);
    try std.testing.expectEqual(@as(u8, 26), framed[0]);

    const server_frame = [_]u8{ 0, 7, 30, 9, 9 };
    const header = try parseBinaryHeader(&server_frame);
    try std.testing.expectEqual(@as(?u16, 7), header.sequence);
    try std.testing.expectEqual(Opcode.dave_mls_welcome, header.opcode);
    try std.testing.expectEqual(@as(usize, 2), header.payload.len);

    const wrong_form = [_]u8{ 0, 7, 5, 0 };
    try std.testing.expectError(error.UnsupportedOpcode, parseBinaryHeader(&wrong_form));
}

test "payload parser enforces the opcode and bounds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const hello = try parsePayload(Hello, arena.allocator(),
        \\{"op":8,"d":{"heartbeat_interval":41250,"v":8}}
    , .hello, 1024);
    try std.testing.expectEqual(@as(u32, 41250), hello.heartbeat_interval);
    try std.testing.expectEqual(@as(u8, 8), hello.version);

    try std.testing.expectError(
        error.UnexpectedOpcode,
        parsePayload(Hello, arena.allocator(),
            \\{"op":2,"d":{"heartbeat_interval":1,"v":8}}
        , .hello, 1024),
    );
}

//! Voice gateway session orchestration (transport-agnostic).
//!
//! The caller owns the WebSocket, UDP socket and payload buffers. This module
//! enforces the documented handshake order, selects an AEAD mode, keeps the
//! heartbeat interval, copies the 32-byte session key into owned storage and
//! delegates DAVE control transitions. It fails closed on unknown modes,
//! malformed keys or out-of-order frames.

const std = @import("std");
const gateway = @import("gateway.zig");
const transitions = @import("transitions.zig");

pub const Error = error{
    InvalidState,
    InvalidSecretKey,
    NoSupportedEncryptionMode,
    UnsupportedVersion,
    SessionClosed,
};

pub const Phase = enum {
    awaiting_hello,
    awaiting_ready,
    awaiting_session_description,
    established,
    resuming,
    closed,
};

pub const Action = union(enum) {
    none,
    send_identify,
    send_select_protocol: struct {
        mode: gateway.EncryptionMode,
        address: []const u8,
        port: u16,
    },
    send_heartbeat: struct {
        nonce: i64,
        seq_ack: ?i64,
    },
    send_resume,
    dave: transitions.Action,
    ready: struct {
        ssrc: u32,
        ip: []const u8,
        port: u16,
    },
    established: gateway.EncryptionMode,
    resumed,
    closed: gateway.CloseAction,
};

pub const Session = struct {
    phase: Phase = .awaiting_hello,
    version: u8 = 8,
    heartbeat_interval_ms: u32 = 0,
    next_heartbeat_ms: u64 = 0,
    seq_ack: ?i64 = null,
    ssrc: u32 = 0,
    udp_port: u16 = 0,
    mode: ?gateway.EncryptionMode = null,
    secret_key: [32]u8 = @splat(0),
    has_key: bool = false,
    dave: ?transitions.Session = null,

    pub fn init(max_dave_version: u16) Error!Session {
        var session = Session{};
        if (max_dave_version > 0) {
            session.dave = transitions.Session.init(max_dave_version) catch return error.UnsupportedVersion;
        }
        return session;
    }

    pub fn onHello(self: *Session, hello: gateway.Hello) Error!Action {
        if (self.phase != .awaiting_hello and self.phase != .resuming) return error.InvalidState;
        self.version = hello.version;
        self.heartbeat_interval_ms = hello.heartbeat_interval;
        if (self.phase == .resuming) return .send_resume;
        self.phase = .awaiting_ready;
        return .send_identify;
    }

    pub fn onReady(self: *Session, ready: gateway.Ready) Error!Action {
        if (self.phase != .awaiting_ready) return error.InvalidState;
        const mode = gateway.selectEncryption(ready.modes) catch return error.NoSupportedEncryptionMode;
        self.ssrc = ready.ssrc;
        self.udp_port = ready.port;
        self.mode = mode;
        self.phase = .awaiting_session_description;
        return .{ .ready = .{ .ssrc = ready.ssrc, .ip = ready.ip, .port = ready.port } };
    }

    /// Builds the select-protocol action; the caller sends it with
    /// `gateway.writeSelectProtocol`.
    pub fn selectProtocol(self: *Session, address: []const u8) Error!Action {
        if (self.phase != .awaiting_session_description) return error.InvalidState;
        const mode = self.mode orelse return error.NoSupportedEncryptionMode;
        return .{ .send_select_protocol = .{ .mode = mode, .address = address, .port = self.udp_port } };
    }

    pub fn onSessionDescription(self: *Session, description: gateway.SessionDescription) Error!Action {
        if (self.phase != .awaiting_session_description) return error.InvalidState;
        if (description.secret_key.len != self.secret_key.len) return error.InvalidSecretKey;
        if (self.mode) |expected| {
            if (description.mode != expected) return error.NoSupportedEncryptionMode;
        }
        @memset(&self.secret_key, 0);
        @memcpy(&self.secret_key, description.secret_key);
        self.has_key = true;
        self.phase = .established;
        if (self.dave) |*dave| {
            if (description.dave_protocol_version) |version| {
                dave.onExternalSender(version) catch return error.UnsupportedVersion;
            }
        }
        return .{ .established = description.mode };
    }

    pub fn onHeartbeatAck(self: *Session, _: gateway.HeartbeatAck) Action {
        _ = self;
        return .none;
    }

    pub fn onResumed(self: *Session) Error!Action {
        if (self.phase != .resuming) return error.InvalidState;
        self.phase = .established;
        return .resumed;
    }

    /// Returns the next heartbeat payload when the interval has elapsed; the
    /// caller supplies the nonce and sends `gateway.writeHeartbeat`.
    pub fn heartbeatDue(self: *Session, now_ms: u64) ?Action {
        if (self.phase != .established and self.phase != .resuming) return null;
        if (now_ms < self.next_heartbeat_ms) return null;
        self.next_heartbeat_ms = now_ms + self.heartbeat_interval_ms;
        return .{ .send_heartbeat = .{ .nonce = @intCast(now_ms), .seq_ack = self.seq_ack } };
    }

    pub fn onSequence(self: *Session, sequence: u16) void {
        self.seq_ack = sequence;
    }

    /// DAVE control delegation. Binary opcodes are handled by the caller with
    /// libdave; this covers the JSON transition state machine.
    pub fn onPrepareEpoch(self: *Session, epoch: u64, version: u16) Error!Action {
        var dave = self.dave orelse return error.UnsupportedVersion;
        const action = dave.onPrepareEpoch(epoch, version) catch return error.UnsupportedVersion;
        self.dave = dave;
        return .{ .dave = action };
    }

    pub fn onPrepareTransition(self: *Session, transition_id: u16, version: u16) Error!Action {
        var dave = self.dave orelse return error.UnsupportedVersion;
        const action = dave.onPrepareTransition(transition_id, version) catch return error.InvalidState;
        self.dave = dave;
        return .{ .dave = action };
    }

    pub fn onExecuteTransition(self: *Session, transition_id: u16) Error!Action {
        var dave = self.dave orelse return error.UnsupportedVersion;
        const action = dave.onExecuteTransition(transition_id) catch return error.InvalidState;
        self.dave = dave;
        return .{ .dave = action };
    }

    pub fn onClose(self: *Session, code: u16) Action {
        self.close();
        return .{ .closed = gateway.classifyClose(code) };
    }

    pub fn close(self: *Session) void {
        self.phase = .closed;
        self.has_key = false;
        @memset(&self.secret_key, 0);
        self.mode = null;
    }

    /// The caller may inspect the key only for the cipher; it must never log it.
    pub fn secretKey(self: *const Session) ?[]const u8 {
        if (!self.has_key) return null;
        return &self.secret_key;
    }
};

test "handshake order produces identify, select protocol and established" {
    var session = try Session.init(1);
    try std.testing.expectEqual(Action.send_identify, try session.onHello(.{ .heartbeat_interval = 40, .version = 8 }));
    const ready_action = try session.onReady(.{
        .ssrc = 5,
        .ip = "127.0.0.1",
        .port = 1234,
        .modes = &.{ "aead_xchacha20_poly1305_rtpsize", "aead_aes256_gcm_rtpsize" },
    });
    try std.testing.expectEqual(@as(u32, 5), ready_action.ready.ssrc);
    const select = try session.selectProtocol("203.0.113.1");
    try std.testing.expectEqual(gateway.EncryptionMode.aead_aes256_gcm_rtpsize, select.send_select_protocol.mode);

    const key: [32]u8 = @splat(7);
    const established = try session.onSessionDescription(.{
        .mode = .aead_aes256_gcm_rtpsize,
        .secret_key = &key,
        .dave_protocol_version = 1,
    });
    try std.testing.expectEqual(gateway.EncryptionMode.aead_aes256_gcm_rtpsize, established.established);
    try std.testing.expectEqualSlices(u8, &key, session.secretKey().?);
}

test "out-of-order frames and bad keys fail closed" {
    var session = try Session.init(0);
    try std.testing.expectError(error.InvalidState, session.onReady(.{
        .ssrc = 1,
        .ip = "x",
        .port = 1,
        .modes = &.{"aead_xchacha20_poly1305_rtpsize"},
    }));
    _ = try session.onHello(.{ .heartbeat_interval = 1, .version = 8 });
    _ = try session.onReady(.{
        .ssrc = 1,
        .ip = "x",
        .port = 1,
        .modes = &.{"xsalsa20_poly1305"},
    }) catch |err| {
        try std.testing.expectEqual(error.NoSupportedEncryptionMode, err);
    };
}

test "unsupported encryption has no fallback" {
    var session = try Session.init(0);
    _ = try session.onHello(.{ .heartbeat_interval = 1, .version = 8 });
    try std.testing.expectError(error.NoSupportedEncryptionMode, session.onReady(.{
        .ssrc = 1,
        .ip = "x",
        .port = 1,
        .modes = &.{"xsalsa20_poly1305"},
    }));
}

test "session description rejects a non-32-byte key" {
    var session = try Session.init(0);
    _ = try session.onHello(.{ .heartbeat_interval = 1, .version = 8 });
    _ = try session.onReady(.{
        .ssrc = 1,
        .ip = "x",
        .port = 1,
        .modes = &.{"aead_xchacha20_poly1305_rtpsize"},
    });
    try std.testing.expectError(error.InvalidSecretKey, session.onSessionDescription(.{
        .mode = .aead_xchacha20_poly1305_rtpsize,
        .secret_key = "short",
    }));
}

test "heartbeat interval and close classification" {
    var session = try Session.init(0);
    _ = try session.onHello(.{ .heartbeat_interval = 40, .version = 8 });
    _ = try session.onReady(.{
        .ssrc = 1,
        .ip = "x",
        .port = 1,
        .modes = &.{"aead_xchacha20_poly1305_rtpsize"},
    });
    const key: [32]u8 = @splat(0);
    _ = try session.onSessionDescription(.{
        .mode = .aead_xchacha20_poly1305_rtpsize,
        .secret_key = &key,
    });
    try std.testing.expect(session.heartbeatDue(0) == null);
    const due = session.heartbeatDue(40).?;
    try std.testing.expectEqual(@as(i64, 40), due.send_heartbeat.nonce);
    try std.testing.expectEqual(Action{ .closed = .stop }, session.onClose(4014));
    try std.testing.expectEqual(Phase.closed, session.phase);
}

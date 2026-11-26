//! Gateway recovery policy: close classification, session state, budgets and
//! bounded backoff.
//!
//! This module is pure. It decides what the orchestrator should do after a
//! close, invalid session, reconnect request or network loss; it does not own a
//! socket or sleep. The session loop supplies monotonic milliseconds and drives
//! the actual reconnect.

const std = @import("std");

pub const CloseAction = enum {
    /// The session may be resumed with the stored ID and sequence.
    resume_session,
    /// Start a new session with Identify.
    reidentify,
    /// Normal closure; do not reconnect automatically.
    stop,
    /// Authentication, intents, API version, shard or similar error. Never loop.
    fatal,
};

/// Classifies documented Gateway close codes. Unknown 4xxx application codes
/// are treated as retryable but are still bounded by the caller's budgets and
/// backoff; anything else unknown fails closed.
pub fn classifyClose(code: ?u16) CloseAction {
    const value = code orelse return .resume_session; // abnormal closure, no frame
    return switch (value) {
        1000, 1001 => .stop,
        1006, 1012, 1013, 1014 => .resume_session,
        4000, 4001, 4002, 4008 => .resume_session,
        4003, 4005, 4007, 4009 => .reidentify,
        4004, 4010, 4011, 4012, 4013, 4014 => .fatal,
        else => if (value >= 4000 and value <= 4999) .resume_session else .fatal,
    };
}

pub const max_session_id = 128;
pub const max_resume_url = 256;

pub const StateError = error{
    SessionIdTooLong,
    ResumeUrlTooLong,
};

/// Only the fields needed to resume are retained. The token is never stored;
/// it is passed to the send helper and wiped from the scratch buffer.
pub const SessionState = struct {
    session_id: [max_session_id]u8,
    session_id_len: usize,
    resume_url: [max_resume_url]u8,
    resume_url_len: usize,
    sequence: ?i64,

    pub fn init() SessionState {
        return .{
            .session_id = undefined,
            .session_id_len = 0,
            .resume_url = undefined,
            .resume_url_len = 0,
            .sequence = null,
        };
    }

    pub fn setReady(
        self: *SessionState,
        session_id: []const u8,
        resume_url: []const u8,
        sequence: ?i64,
    ) StateError!void {
        if (session_id.len > self.session_id.len) return error.SessionIdTooLong;
        if (resume_url.len > self.resume_url.len) return error.ResumeUrlTooLong;
        @memset(self.session_id[0..self.session_id_len], 0);
        @memset(self.resume_url[0..self.resume_url_len], 0);
        @memcpy(self.session_id[0..session_id.len], session_id);
        @memcpy(self.resume_url[0..resume_url.len], resume_url);
        self.session_id_len = session_id.len;
        self.resume_url_len = resume_url.len;
        self.sequence = sequence;
    }

    pub fn setSequence(self: *SessionState, sequence: ?i64) void {
        if (sequence) |value| self.sequence = value;
    }

    pub fn id(self: *const SessionState) []const u8 {
        return self.session_id[0..self.session_id_len];
    }

    pub fn url(self: *const SessionState) []const u8 {
        return self.resume_url[0..self.resume_url_len];
    }

    pub fn hasSession(self: *const SessionState) bool {
        return self.session_id_len > 0 and self.resume_url_len > 0;
    }

    pub fn canResume(self: *const SessionState) bool {
        return self.hasSession() and self.sequence != null;
    }

    pub fn clear(self: *SessionState) void {
        @memset(&self.session_id, 0);
        @memset(&self.resume_url, 0);
        self.session_id_len = 0;
        self.resume_url_len = 0;
        self.sequence = null;
    }
};

/// Fixed-window allowance. Discord's identify limit is 1000 per 24 hours and is
/// global across shards; resume calls are not part of it. The resume budget here
/// is a Diszig loop guard, not a Discord limit.
pub const Budget = struct {
    limit: u32,
    window_ms: u64,
    used: u32,
    window_start_ms: u64,

    pub fn init(limit: u32, window_ms: u64, now_ms: u64) Budget {
        return .{ .limit = limit, .window_ms = window_ms, .used = 0, .window_start_ms = now_ms };
    }

    pub fn tryConsume(self: *Budget, now_ms: u64) bool {
        self.roll(now_ms);
        if (self.used >= self.limit) return false;
        self.used += 1;
        return true;
    }

    pub fn remaining(self: *Budget, now_ms: u64) u32 {
        self.roll(now_ms);
        return self.limit -| self.used;
    }

    fn roll(self: *Budget, now_ms: u64) void {
        if (now_ms < self.window_start_ms or now_ms - self.window_start_ms >= self.window_ms) {
            self.window_start_ms = now_ms;
            self.used = 0;
        }
    }
};

pub const Backoff = struct {
    base_ms: u64,
    max_ms: u64,
    max_attempts: u32,
    attempt: u32,

    pub fn init(base_ms: u64, max_ms: u64, max_attempts: u32) Backoff {
        return .{
            .base_ms = base_ms,
            .max_ms = max_ms,
            .max_attempts = max_attempts,
            .attempt = 0,
        };
    }

    /// Returns the next delay, or null when the attempt budget is exhausted.
    pub fn next(self: *Backoff) ?u64 {
        if (self.attempt >= self.max_attempts) return null;
        const shift: u6 = @intCast(@min(self.attempt, 16));
        const factor = @as(u64, 1) << shift;
        const raw = self.base_ms *| factor;
        self.attempt += 1;
        return @min(raw, self.max_ms);
    }

    pub fn reset(self: *Backoff) void {
        self.attempt = 0;
    }
};

pub const Config = struct {
    identify_limit: u32 = 1000,
    identify_window_ms: u64 = 24 * 60 * 60 * 1000,
    resume_limit: u32 = 50,
    resume_window_ms: u64 = 5 * 60 * 1000,
    backoff_base_ms: u64 = 1000,
    backoff_max_ms: u64 = 60_000,
    max_attempts: u32 = 8,
};

pub const Decision = enum {
    resume_session,
    reidentify,
    stop,
    fatal,
    /// Both the resume path and the identify budget are exhausted. Stop.
    exhausted,
};

pub const Recovery = struct {
    state: SessionState,
    identify: Budget,
    resume_budget: Budget,
    backoff: Backoff,

    pub fn init(now_ms: u64, config: Config) Recovery {
        return .{
            .state = SessionState.init(),
            .identify = Budget.init(config.identify_limit, config.identify_window_ms, now_ms),
            .resume_budget = Budget.init(config.resume_limit, config.resume_window_ms, now_ms),
            .backoff = Backoff.init(config.backoff_base_ms, config.backoff_max_ms, config.max_attempts),
        };
    }

    pub fn onReady(
        self: *Recovery,
        session_id: []const u8,
        resume_url: []const u8,
        sequence: ?i64,
    ) StateError!void {
        try self.state.setReady(session_id, resume_url, sequence);
        self.backoff.reset();
    }

    pub fn onDispatch(self: *Recovery, sequence: ?i64) void {
        self.state.setSequence(sequence);
    }

    pub fn canResume(self: *const Recovery) bool {
        return self.state.canResume();
    }

    /// Reconnect (op 7): resume when possible, otherwise Identify within the
    /// separate budgets.
    pub fn onReconnect(self: *Recovery, now_ms: u64) Decision {
        if (self.state.canResume() and self.resume_budget.tryConsume(now_ms)) return .resume_session;
        self.state.clear();
        if (self.identify.tryConsume(now_ms)) return .reidentify;
        return .exhausted;
    }

    /// `resumable` is the `d` boolean of Invalid Session (op 9).
    pub fn onInvalidSession(self: *Recovery, resumable: bool, now_ms: u64) Decision {
        if (resumable and self.state.canResume() and self.resume_budget.tryConsume(now_ms)) {
            return .resume_session;
        }
        // Invalid Session explicitly invalidates the stored session unless
        // `d` is true, so the next attempt must Identify.
        self.state.clear();
        if (self.identify.tryConsume(now_ms)) return .reidentify;
        return .exhausted;
    }

    pub fn onClose(self: *Recovery, code: ?u16, now_ms: u64) Decision {
        return switch (classifyClose(code)) {
            .stop => .stop,
            .fatal => .fatal,
            .resume_session => {
                if (self.state.canResume() and self.resume_budget.tryConsume(now_ms)) return .resume_session;
                // The session cannot be resumed. A new Identify is the only
                // forward path, and it has its own budget.
                self.state.clear();
                if (self.identify.tryConsume(now_ms)) return .reidentify;
                return .exhausted;
            },
            .reidentify => {
                self.state.clear();
                if (self.identify.tryConsume(now_ms)) return .reidentify;
                return .exhausted;
            },
        };
    }

    /// Next reconnect delay, or null when attempts are exhausted. The caller
    /// sleeps this long, cancellably, before opening a new connection.
    pub fn nextDelay(self: *Recovery) ?u64 {
        return self.backoff.next();
    }
};

pub fn validateCredential(value: []const u8) error{InvalidCredential}!void {
    if (value.len == 0) return error.InvalidCredential;
    for (value) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == '.' or c == '_' or c == '-')) {
            return error.InvalidCredential;
        }
    }
}

fn validateProperty(value: []const u8) error{InvalidProperty}!void {
    if (value.len == 0) return error.InvalidProperty;
    for (value) |c| {
        if (!(std.ascii.isAlphanumeric(c) or c == ' ' or c == '.' or c == '_' or c == '-')) {
            return error.InvalidProperty;
        }
    }
}

pub const Properties = struct {
    os: []const u8 = "unknown",
    browser: []const u8 = "diszig",
    device: []const u8 = "diszig",
};

pub const Identify = struct {
    token: []const u8,
    intents: u64,
    shard: ?[2]u16 = null,
    properties: Properties = .{},
    /// Payload compression. Transport compression (`zlib-stream`) is separate;
    /// leave this false when transport compression is enabled.
    compress: bool = false,
};

pub const BuildError = error{
    InvalidCredential,
    InvalidProperty,
    NoSpaceLeft,
    InvalidShard,
};

/// Writes the Identify payload into a caller-owned scratch buffer. The caller
/// must wipe that buffer after sending; `Session.sendIdentify` does.
pub fn writeIdentify(buffer: []u8, identify: Identify) BuildError![]const u8 {
    try validateCredential(identify.token);
    try validateProperty(identify.properties.os);
    try validateProperty(identify.properties.browser);
    try validateProperty(identify.properties.device);

    var shard_buffer: [48]u8 = undefined;
    const shard: []const u8 = if (identify.shard) |values| blk: {
        if (values[1] == 0 or values[0] >= values[1]) return error.InvalidShard;
        break :blk std.fmt.bufPrint(
            &shard_buffer,
            ",\"shard\":[{d},{d}]",
            .{ values[0], values[1] },
        ) catch return error.NoSpaceLeft;
    } else "";

    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":2,\"d\":{{\"token\":\"{s}\",\"intents\":{d},\"properties\":{{\"os\":\"{s}\",\"browser\":\"{s}\",\"device\":\"{s}\"}},\"compress\":{s}{s}}}}}",
        .{
            identify.token,
            identify.intents,
            identify.properties.os,
            identify.properties.browser,
            identify.properties.device,
            if (identify.compress) "true" else "false",
            shard,
        },
    ) catch return error.NoSpaceLeft;
}

/// Writes the Resume payload. `session_id` must come from a validated Ready.
pub fn writeResume(
    buffer: []u8,
    token: []const u8,
    session_id: []const u8,
    sequence: i64,
) BuildError![]const u8 {
    try validateCredential(token);
    try validateCredential(session_id);
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":6,\"d\":{{\"token\":\"{s}\",\"session_id\":\"{s}\",\"seq\":{d}}}}}",
        .{ token, session_id, sequence },
    ) catch return error.NoSpaceLeft;
}

test "documented close codes classify conservatively" {
    try std.testing.expectEqual(CloseAction.stop, classifyClose(1000));
    try std.testing.expectEqual(CloseAction.stop, classifyClose(1001));
    try std.testing.expectEqual(CloseAction.resume_session, classifyClose(null));
    try std.testing.expectEqual(CloseAction.resume_session, classifyClose(1006));
    try std.testing.expectEqual(CloseAction.resume_session, classifyClose(4000));
    try std.testing.expectEqual(CloseAction.resume_session, classifyClose(4008));
    try std.testing.expectEqual(CloseAction.reidentify, classifyClose(4007));
    try std.testing.expectEqual(CloseAction.reidentify, classifyClose(4009));
    try std.testing.expectEqual(CloseAction.fatal, classifyClose(4004));
    try std.testing.expectEqual(CloseAction.fatal, classifyClose(4014));
    // Unknown 4xxx is retryable but still bounded by budgets/backoff.
    try std.testing.expectEqual(CloseAction.resume_session, classifyClose(4099));
    // Unknown outside the application range fails closed.
    try std.testing.expectEqual(CloseAction.fatal, classifyClose(3000));
}

test "identify payload only contains validated credential characters" {
    var buffer: [512]u8 = undefined;
    const payload = try writeIdentify(&buffer, .{ .token = "abc.DEF_123-4", .intents = 5 });
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"op\":2") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"token\":\"abc.DEF_123-4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"intents\":5") != null);
    try std.testing.expectError(
        error.InvalidCredential,
        writeIdentify(&buffer, .{ .token = "abc\"},\"op\":2", .intents = 5 }),
    );
}

test "resume payload carries id and sequence" {
    var buffer: [512]u8 = undefined;
    const payload = try writeResume(&buffer, "bot.token", "sess-1", 1337);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"op\":6") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"session_id\":\"sess-1\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, payload, "\"seq\":1337") != null);
}

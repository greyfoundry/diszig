//! Gateway session control: Hello, Identify/Resume payloads, recovery state,
//! envelope parsing and heartbeat driving.
//!
//! This is not a complete Gateway client. The recovery policy and payloads are
//! implemented, but the automatic reconnect loop and typed dispatch are later
//! packages. The session owns one transport and one heartbeat deadline. Its I/O
//! loop must call `next` from a single owner; user handlers belong on worker
//! capacity (GW-04) and must never run on this path. The optional heartbeat
//! thread only writes heartbeats.

const std = @import("std");
const protocol = @import("protocol");
const transport = @import("transport.zig");
const heartbeat_mod = @import("heartbeat.zig");
const recovery_mod = @import("recovery.zig");

pub const Heartbeat = heartbeat_mod.Heartbeat;
pub const Action = heartbeat_mod.Action;
pub const Message = transport.Message;
pub const Recovery = recovery_mod.Recovery;
pub const Decision = recovery_mod.Decision;
pub const SessionState = recovery_mod.SessionState;
pub const Identify = recovery_mod.Identify;

pub const Kind = enum {
    dispatch,
    heartbeat,
    heartbeat_ack,
    reconnect,
    invalid_session,
    hello,
    other,
};

pub const EventKind = enum { other, ready, resumed };

pub const max_event_name = 64;

pub const Parsed = struct {
    op: i64,
    kind: Kind,
    sequence: ?i64 = null,
    event: EventKind = .other,
    event_name: [max_event_name]u8 = undefined,
    event_name_len: usize = 0,

    /// Dispatch name (`t`) when present, otherwise an empty slice.
    pub fn name(self: *const Parsed) []const u8 {
        return self.event_name[0..self.event_name_len];
    }
};

pub const Detailed = struct {
    message: Message,
    /// Present for text payloads; null for binary and close frames.
    parsed: ?Parsed = null,
};

pub const Hello = struct {
    heartbeat_interval_ms: u64,
};

/// Parses only the top-level `op`, `s` and the dispatch name. Unknown fields,
/// including a large `d`, are skipped without building a value tree.
pub fn parseEnvelope(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    max_bytes: usize,
) !Parsed {
    const Wire = struct {
        op: i64,
        s: ?i64 = null,
        t: ?[]const u8 = null,
    };
    var parsed = try protocol.json.parseBounded(Wire, allocator, bytes, max_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();

    var event: EventKind = .other;
    var event_name: [max_event_name]u8 = undefined;
    var event_name_len: usize = 0;
    if (parsed.value.t) |name| {
        if (name.len > max_event_name) return error.EventNameTooLong;
        @memcpy(event_name[0..name.len], name);
        event_name_len = name.len;
        if (std.mem.eql(u8, name, "READY")) {
            event = .ready;
        } else if (std.mem.eql(u8, name, "RESUMED")) {
            event = .resumed;
        }
    }
    return .{
        .op = parsed.value.op,
        .kind = classify(parsed.value.op),
        .sequence = parsed.value.s,
        .event = event,
        .event_name = event_name,
        .event_name_len = event_name_len,
    };
}

/// Hello is the only payload whose `d` this phase interprets.
pub fn parseHello(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    max_bytes: usize,
) !Hello {
    const Wire = struct {
        op: i64,
        d: struct {
            heartbeat_interval: i64,
        },
    };
    var parsed = try protocol.json.parseBounded(Wire, allocator, bytes, max_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    if (parsed.value.op != 10) return error.NotHello;
    if (parsed.value.d.heartbeat_interval <= 0) return error.InvalidHello;
    return .{ .heartbeat_interval_ms = @intCast(parsed.value.d.heartbeat_interval) };
}

/// Copies the Ready fields needed for Resume into the recovery state.
pub fn parseReadyInto(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    max_bytes: usize,
    recovery: *recovery_mod.Recovery,
    sequence: ?i64,
) !void {
    const Wire = struct {
        op: i64,
        d: struct {
            session_id: []const u8,
            resume_gateway_url: []const u8,
        },
    };
    var parsed = try protocol.json.parseBounded(Wire, allocator, bytes, max_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    if (parsed.value.op != 0) return error.NotReady;
    try recovery.onReady(
        parsed.value.d.session_id,
        parsed.value.d.resume_gateway_url,
        sequence,
    );
}

/// Invalid Session's `d` is the only payload boolean this phase interprets.
pub fn parseInvalidSession(
    allocator: std.mem.Allocator,
    bytes: []const u8,
    max_bytes: usize,
) !bool {
    const Wire = struct {
        op: i64,
        d: bool,
    };
    var parsed = try protocol.json.parseBounded(Wire, allocator, bytes, max_bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    if (parsed.value.op != 9) return error.NotInvalidSession;
    return parsed.value.d;
}

fn classify(op: i64) Kind {
    return switch (op) {
        0 => .dispatch,
        1 => .heartbeat,
        7 => .reconnect,
        9 => .invalid_session,
        10 => .hello,
        11 => .heartbeat_ack,
        else => .other,
    };
}

pub const Options = struct {
    transport: transport.Options,
    /// Initial jitter in [0, 1). Null draws a random value from the I/O source.
    initial_jitter: ?f64 = null,
    max_payload_bytes: usize = 16 * 1024 * 1024,
};

pub const Session = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    connection: transport.Connection,
    heartbeat: Heartbeat,
    heartbeat_lock: std.Io.Mutex,
    driver: ?std.Thread,
    driver_stop: std.atomic.Value(bool),
    driver_failed: std.atomic.Value(bool),
    zombie: std.atomic.Value(bool),
    recovery: Recovery,
    last_decision: ?Decision,
    max_payload_bytes: usize,

    /// Connects the transport, requires Hello as the first payload and arms the
    /// heartbeat. It does not Identify or Resume; call `sendIdentify` or
    /// `sendResume` after this returns.
    pub fn connect(allocator: std.mem.Allocator, io: std.Io, options: Options) !Session {
        var connection = try transport.Connection.connect(allocator, io, options.transport);
        errdefer connection.deinit();

        const first = try readHello(&connection, io, options.transport.handshake_timeout_ms);
        if (first.kind != .text) return error.InvalidHello;
        const hello = try parseHello(allocator, first.data, options.max_payload_bytes);

        const unit = options.initial_jitter orelse try randomUnit(io);
        const now = nowMs(io);
        var heartbeat = Heartbeat.init(
            hello.heartbeat_interval_ms,
            now,
            Heartbeat.jitteredDelay(hello.heartbeat_interval_ms, unit),
        );
        heartbeat.setSequence(null);

        return .{
            .allocator = allocator,
            .io = io,
            .connection = connection,
            .heartbeat = heartbeat,
            .heartbeat_lock = .init,
            .driver = null,
            .driver_stop = .init(false),
            .driver_failed = .init(false),
            .zombie = .init(false),
            .recovery = Recovery.init(now, .{}),
            .last_decision = null,
            .max_payload_bytes = options.max_payload_bytes,
        };
    }

    /// The session must not move after this call. The thread owns only the
    /// heartbeat deadline and outbound writes; reads stay on the caller's I/O
    /// owner, and user handlers must run elsewhere.
    pub fn startHeartbeat(self: *Session) !void {
        if (self.driver != null) return error.AlreadyStarted;
        self.driver_stop.store(false, .release);
        self.driver = try std.Thread.spawn(.{}, driverMain, .{self});
    }

    pub fn stopHeartbeat(self: *Session) void {
        self.driver_stop.store(true, .release);
        if (self.driver) |thread| {
            thread.join();
            self.driver = null;
        }
    }

    pub fn deinit(self: *Session) void {
        self.stopHeartbeat();
        // The driver is joined and no reader may run concurrently with deinit.
        self.heartbeat.stop();
        self.recovery.state.clear();
        self.connection.deinit();
        self.* = undefined;
    }

    /// Sends Identify. The token is copied into a scratch buffer, sent through
    /// the transport (which copies and masks), then the scratch is wiped.
    pub fn sendIdentify(self: *Session, identify: Identify) !void {
        var buffer: [1024]u8 = undefined;
        defer @memset(&buffer, 0);
        const payload = try recovery_mod.writeIdentify(&buffer, identify);
        try self.connection.sendText(payload);
    }

    /// Sends Resume for the stored session. Requires a Ready-derived session ID
    /// and a sequence. The token is never stored by the session.
    pub fn sendResume(self: *Session, token: []const u8) !void {
        const session_id = self.recovery.state.id();
        if (session_id.len == 0) return error.NoSession;
        const sequence = self.recovery.state.sequence orelse return error.NoSequence;
        var buffer: [1024]u8 = undefined;
        defer @memset(&buffer, 0);
        const payload = try recovery_mod.writeResume(&buffer, token, session_id, sequence);
        try self.connection.sendText(payload);
    }

    /// Decision produced by the last close, reconnect or invalid-session
    /// payload. The caller drives the reconnect and backoff delay.
    pub fn lastDecision(self: *const Session) ?Decision {
        return self.last_decision;
    }

    /// Records a transport loss that arrived without a close frame (abnormal
    /// closure). Treated as resumable, bounded by the recovery budgets.
    pub fn onTransportLost(self: *Session) Decision {
        const decision = self.recovery.onClose(null, nowMs(self.io));
        self.last_decision = decision;
        return decision;
    }

    /// Sends a heartbeat if one is due or the server requested one. Safe to
    /// call directly when no driver thread is running. Returns the action so
    /// the caller can stop after `.zombie`.
    pub fn tick(self: *Session) !Action {
        var buffer: [64]u8 = undefined;
        var payload_len: usize = 0;
        const action = action: {
            try self.heartbeat_lock.lock(self.io);
            defer self.heartbeat_lock.unlock(self.io);

            const current = self.heartbeat.poll(nowMs(self.io));
            if (current == .send) {
                // `{?d}` renders `null` or the last sequence.
                const payload = try std.fmt.bufPrint(
                    &buffer,
                    "{{\"op\":1,\"d\":{?d}}}",
                    .{self.heartbeat.last_sequence},
                );
                payload_len = payload.len;
            }
            break :action current;
        };

        switch (action) {
            .send => try self.connection.sendText(buffer[0..payload_len]),
            .zombie => {
                self.zombie.store(true, .release);
                self.connection.close(4000, "zombie connection");
            },
            .none => {},
        }
        return action;
    }

    /// Reads one payload. Heartbeat ACK and server heartbeat requests are
    /// consumed and update the scheduler; dispatch, reconnect, invalid-session
    /// and unknown payloads are returned to the caller. A close frame is
    /// returned as-is. Reads block; close from another owner to cancel.
    ///
    /// Close, Reconnect and Invalid Session also update `recovery` and set
    /// `last_decision`. A READY payload populates the resumable session state.
    pub fn nextDetailed(self: *Session) !Detailed {
        while (true) {
            const message = self.connection.next() catch |err| {
                switch (err) {
                    error.Closed, error.ConnectionResetByPeer, error.Unexpected => _ = self.onTransportLost(),
                    else => {},
                }
                return err;
            };
            switch (message.kind) {
                .close => {
                    self.last_decision = self.recovery.onClose(message.close_code, nowMs(self.io));
                    return .{ .message = message };
                },
                .binary => return .{ .message = message },
                .text => {
                    const parsed = try parseEnvelope(
                        self.allocator,
                        message.data,
                        self.max_payload_bytes,
                    );
                    switch (parsed.kind) {
                        .heartbeat_ack => {
                            try self.heartbeat_lock.lock(self.io);
                            self.heartbeat.ack();
                            self.heartbeat_lock.unlock(self.io);
                        },
                        .heartbeat => {
                            try self.heartbeat_lock.lock(self.io);
                            self.heartbeat.request();
                            self.heartbeat_lock.unlock(self.io);
                        },
                        .hello => return error.UnexpectedHello,
                        .invalid_session => {
                            const resumable = parseInvalidSession(
                                self.allocator,
                                message.data,
                                self.max_payload_bytes,
                            ) catch false;
                            self.last_decision = self.recovery.onInvalidSession(
                                resumable,
                                nowMs(self.io),
                            );
                            return .{ .message = message, .parsed = parsed };
                        },
                        .reconnect => {
                            self.last_decision = self.recovery.onReconnect(nowMs(self.io));
                            return .{ .message = message, .parsed = parsed };
                        },
                        .dispatch => {
                            if (parsed.sequence) |sequence| {
                                try self.heartbeat_lock.lock(self.io);
                                self.heartbeat.setSequence(sequence);
                                self.heartbeat_lock.unlock(self.io);
                                self.recovery.onDispatch(sequence);
                            }
                            switch (parsed.event) {
                                .ready => try parseReadyInto(
                                    self.allocator,
                                    message.data,
                                    self.max_payload_bytes,
                                    &self.recovery,
                                    parsed.sequence,
                                ),
                                .resumed => self.recovery.backoff.reset(),
                                .other => {},
                            }
                            self.last_decision = null;
                            return .{ .message = message, .parsed = parsed };
                        },
                        .other => {
                            if (parsed.sequence) |sequence| {
                                try self.heartbeat_lock.lock(self.io);
                                self.heartbeat.setSequence(sequence);
                                self.heartbeat_lock.unlock(self.io);
                                self.recovery.onDispatch(sequence);
                            }
                            return .{ .message = message, .parsed = parsed };
                        },
                    }
                },
            }
        }
    }

    /// Convenience wrapper for callers that do not need the parsed envelope.
    pub fn next(self: *Session) !Message {
        return (try self.nextDetailed()).message;
    }

    pub fn lastSequence(self: *Session) !?i64 {
        try self.heartbeat_lock.lock(self.io);
        defer self.heartbeat_lock.unlock(self.io);
        return self.heartbeat.last_sequence;
    }

    pub fn isZombie(self: *const Session) bool {
        return self.zombie.load(.acquire);
    }

    pub fn driverFailed(self: *const Session) bool {
        return self.driver_failed.load(.acquire);
    }

    pub fn heartbeatCount(self: *Session) !u64 {
        try self.heartbeat_lock.lock(self.io);
        defer self.heartbeat_lock.unlock(self.io);
        return self.heartbeat.sent_count;
    }

    fn driverMain(self: *Session) void {
        while (!self.driver_stop.load(.acquire)) {
            const action = self.tick() catch {
                self.driver_failed.store(true, .release);
                return;
            };
            if (action == .zombie) return;
            const wait = self.waitMs() catch {
                self.driver_failed.store(true, .release);
                return;
            };
            const duration: std.Io.Clock.Duration = .{
                .raw = .fromNanoseconds(@intCast(wait * std.time.ns_per_ms)),
                .clock = .awake,
            };
            duration.sleep(self.io) catch {
                self.driver_failed.store(true, .release);
                return;
            };
        }
    }

    /// Sleeps in short slices so cancellation and server requests are observed
    /// promptly even when the next deadline is far away.
    fn waitMs(self: *Session) !u64 {
        try self.heartbeat_lock.lock(self.io);
        const due = self.heartbeat.next_due_ms;
        self.heartbeat_lock.unlock(self.io);
        const remaining = due -| nowMs(self.io);
        return std.math.clamp(remaining, 10, 200);
    }

    fn nowMs(io: std.Io) u64 {
        const ns = std.Io.Clock.awake.now(io).nanoseconds;
        if (ns <= 0) return 0;
        return @intCast(@divTrunc(ns, std.time.ns_per_ms));
    }

    fn randomUnit(io: std.Io) !f64 {
        var bytes: [8]u8 = undefined;
        io.random(&bytes);
        const value = std.mem.readInt(u64, &bytes, .little);
        return @as(f64, @floatFromInt(value)) / 18446744073709551616.0;
    }
};

/// Bounds the initial Hello wait without `SO_RCVTIMEO`: a watchdog closes the
/// socket at the deadline, which unblocks the reader on every platform.
fn readHello(
    connection: *transport.Connection,
    io: std.Io,
    timeout_ms: u32,
) !transport.Message {
    var watchdog = Watchdog{
        .connection = connection,
        .io = io,
        .deadline_ms = Session.nowMs(io) +| @as(u64, timeout_ms),
        .cancelled = .init(false),
        .fired = .init(false),
    };
    const thread = try std.Thread.spawn(.{}, Watchdog.run, .{&watchdog});

    const result = connection.next();
    watchdog.cancelled.store(true, .release);
    thread.join();
    if (watchdog.fired.load(.acquire)) return error.HelloTimeout;
    return result;
}

const Watchdog = struct {
    connection: *transport.Connection,
    io: std.Io,
    deadline_ms: u64,
    cancelled: std.atomic.Value(bool),
    fired: std.atomic.Value(bool),

    fn run(self: *Watchdog) void {
        while (!self.cancelled.load(.acquire)) {
            const now = Session.nowMs(self.io);
            if (now >= self.deadline_ms) {
                self.fired.store(true, .release);
                self.connection.close(4000, "hello deadline");
                return;
            }
            const remaining = self.deadline_ms - now;
            const wait = std.math.clamp(remaining, 10, 100);
            const duration: std.Io.Clock.Duration = .{
                .raw = .fromNanoseconds(@intCast(wait * std.time.ns_per_ms)),
                .clock = .awake,
            };
            duration.sleep(self.io) catch return;
        }
    }
};

test "envelope extracts op and sequence and skips a nested d" {
    const payload =
        \\{"op":0,"t":"READY","s":42,"d":{"unknown":{"nested":[1,2,3]},"blob":"ignored"}}
    ;
    const parsed = try parseEnvelope(std.testing.allocator, payload, 1024);
    try std.testing.expectEqual(@as(i64, 0), parsed.op);
    try std.testing.expectEqual(Kind.dispatch, parsed.kind);
    try std.testing.expectEqual(@as(?i64, 42), parsed.sequence);
}

test "hello requires a positive interval" {
    const hello = try parseHello(
        std.testing.allocator,
        "{\"op\":10,\"d\":{\"heartbeat_interval\":45000}}",
        1024,
    );
    try std.testing.expectEqual(@as(u64, 45_000), hello.heartbeat_interval_ms);

    try std.testing.expectError(
        error.InvalidHello,
        parseHello(std.testing.allocator, "{\"op\":10,\"d\":{\"heartbeat_interval\":0}}", 1024),
    );
    try std.testing.expectError(
        error.NotHello,
        parseHello(std.testing.allocator, "{\"op\":11,\"d\":{}}", 1024),
    );
}

test "unknown op is retained as other" {
    const parsed = try parseEnvelope(std.testing.allocator, "{\"op\":99}", 64);
    try std.testing.expectEqual(Kind.other, parsed.kind);
    try std.testing.expectEqual(@as(?i64, null), parsed.sequence);
}

test "ready and resumed are distinguished without materialising d" {
    const ready = try parseEnvelope(
        std.testing.allocator,
        "{\"op\":0,\"t\":\"READY\",\"s\":3,\"d\":{\"session_id\":\"s\",\"resume_gateway_url\":\"wss://r\"}}",
        1024,
    );
    try std.testing.expectEqual(EventKind.ready, ready.event);
    try std.testing.expectEqual(@as(?i64, 3), ready.sequence);

    const resumed = try parseEnvelope(
        std.testing.allocator,
        "{\"op\":0,\"t\":\"RESUMED\",\"s\":9,\"d\":{}}",
        1024,
    );
    try std.testing.expectEqual(EventKind.resumed, resumed.event);
    try std.testing.expectEqual(EventKind.other, (try parseEnvelope(
        std.testing.allocator,
        "{\"op\":0,\"t\":\"MESSAGE_CREATE\",\"s\":10,\"d\":{}}",
        1024,
    )).event);
}

test "envelope keeps the dispatch name for the queue" {
    const parsed = try parseEnvelope(
        std.testing.allocator,
        "{\"op\":0,\"t\":\"MESSAGE_CREATE\",\"s\":4,\"d\":{\"id\":\"1\"}}",
        1024,
    );
    try std.testing.expectEqualStrings("MESSAGE_CREATE", parsed.name());
    try std.testing.expectEqual(@as(?i64, 4), parsed.sequence);
}

test "ready populates the resumable state" {
    var rec = Recovery.init(0, .{});
    try parseReadyInto(
        std.testing.allocator,
        "{\"op\":0,\"t\":\"READY\",\"s\":3,\"d\":{\"session_id\":\"sid-1\",\"resume_gateway_url\":\"wss://resume\"}}",
        1024,
        &rec,
        3,
    );
    try std.testing.expectEqualStrings("sid-1", rec.state.id());
    try std.testing.expectEqualStrings("wss://resume", rec.state.url());
    try std.testing.expectEqual(@as(?i64, 3), rec.state.sequence);
    try std.testing.expect(rec.canResume());
}

test "invalid session boolean drives the recovery decision" {
    try std.testing.expect(try parseInvalidSession(
        std.testing.allocator,
        "{\"op\":9,\"d\":true}",
        64,
    ));
    try std.testing.expect(!try parseInvalidSession(
        std.testing.allocator,
        "{\"op\":9,\"d\":false}",
        64,
    ));
    try std.testing.expectError(
        error.NotInvalidSession,
        parseInvalidSession(std.testing.allocator, "{\"op\":10,\"d\":true}", 64),
    );
}

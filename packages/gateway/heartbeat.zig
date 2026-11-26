//! Gateway heartbeat deadline state machine.
//!
//! Discord's contract: after Hello, wait `heartbeat_interval * jitter` where
//! `jitter` is in [0, 1), then send a Heartbeat every interval. Each Heartbeat
//! carries the last received sequence (or null). Discord replies with Heartbeat
//! ACK; if no ACK arrives before the next attempt, the connection is a zombie
//! and must be terminated with a non-1000/1001 close code and resumed.
//!
//! This module is pure: the caller supplies monotonic milliseconds. The session
//! loop owns the socket and must call `poll` from its I/O owner, never from a
//! user handler.

const std = @import("std");

pub const Action = enum { none, send, zombie };

pub const Heartbeat = struct {
    interval_ms: u64,
    next_due_ms: u64,
    awaiting_ack: bool,
    last_sequence: ?i64,
    armed: bool,
    stopped: bool,
    requested: bool,
    sent_count: u64,

    /// `now_ms` and `initial_delay_ms` are monotonic milliseconds. The caller
    /// derives `initial_delay_ms` from Hello with `jitteredDelay`.
    pub fn init(interval_ms: u64, now_ms: u64, initial_delay_ms: u64) Heartbeat {
        return .{
            .interval_ms = interval_ms,
            .next_due_ms = std.math.add(u64, now_ms, initial_delay_ms) catch std.math.maxInt(u64),
            .awaiting_ack = false,
            .last_sequence = null,
            .armed = true,
            .stopped = false,
            .requested = false,
            .sent_count = 0,
        };
    }

    /// `unit` must be a random value in [0, 1). Out-of-range input is clamped
    /// to a full interval rather than producing a zero-delay heartbeat storm.
    pub fn jitteredDelay(interval_ms: u64, unit: f64) u64 {
        if (!(unit >= 0.0) or !(unit < 1.0)) return interval_ms;
        const interval: f64 = @floatFromInt(interval_ms);
        const delay = interval * unit;
        if (delay < 0.0) return 0;
        return @intFromFloat(@floor(delay));
    }

    pub fn setSequence(self: *Heartbeat, sequence: ?i64) void {
        self.last_sequence = sequence;
    }

    /// Heartbeat ACK (op 11).
    pub fn ack(self: *Heartbeat) void {
        self.awaiting_ack = false;
    }

    /// Server-requested heartbeat (op 1). The next poll sends immediately.
    pub fn request(self: *Heartbeat) void {
        if (!self.stopped) self.requested = true;
    }

    pub fn stop(self: *Heartbeat) void {
        self.stopped = true;
    }

    /// Returns at most one action per call. A delayed call sends one heartbeat
    /// and schedules the next full interval later; it never emits a burst.
    pub fn poll(self: *Heartbeat, now_ms: u64) Action {
        if (!self.armed or self.stopped) return .none;

        if (self.requested) {
            self.requested = false;
            return self.send(now_ms);
        }

        if (now_ms < self.next_due_ms) return .none;

        if (self.awaiting_ack) {
            self.stopped = true;
            return .zombie;
        }

        return self.send(now_ms);
    }

    fn send(self: *Heartbeat, now_ms: u64) Action {
        self.awaiting_ack = true;
        self.sent_count +|= 1;
        // Keep the cadence anchored to the previous deadline when the poll is
        // at most one interval late. If the loop was stalled for longer, reset
        // from now so the next call does not emit a burst.
        const late = now_ms -| self.next_due_ms;
        const base = if (late <= self.interval_ms) self.next_due_ms else now_ms;
        self.next_due_ms = std.math.add(u64, base, self.interval_ms) catch std.math.maxInt(u64);
        return .send;
    }
};

test "jitter stays inside the documented interval" {
    try std.testing.expectEqual(@as(u64, 0), Heartbeat.jitteredDelay(45_000, 0.0));
    try std.testing.expectEqual(@as(u64, 22_500), Heartbeat.jitteredDelay(45_000, 0.5));
    try std.testing.expectEqual(@as(u64, 44_999), Heartbeat.jitteredDelay(45_000, 0.999999));
    // Out-of-range input is clamped to the full interval, not zero.
    try std.testing.expectEqual(@as(u64, 45_000), Heartbeat.jitteredDelay(45_000, 1.0));
    try std.testing.expectEqual(@as(u64, 45_000), Heartbeat.jitteredDelay(45_000, -0.1));
}

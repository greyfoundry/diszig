//! Bounded retry and ambiguity policy.
//!
//! Method names are not enough: a create whose body may have been delivered
//! must not be replayed automatically. The policy separates safe/idempotent
//! retries from ambiguous non-idempotent writes.

const std = @import("std");

pub const Idempotency = enum {
    /// No side effects; safe to repeat.
    safe,
    /// Side effects are naturally idempotent (for example replace-by-id).
    idempotent,
    /// May create a duplicate if repeated.
    non_idempotent,
};

pub const Policy = struct {
    max_attempts: u8 = 3,
    base_delay_ms: u64 = 250,
    max_delay_ms: u64 = 10_000,
    total_deadline_ms: u64 = 30_000,
};

pub const Outcome = union(enum) {
    success,
    retry_after_ms: u64,
    fail,
    ambiguous,
    canceled,
};

pub const Retry = struct {
    policy: Policy,
    started_ms: i64,
    attempts: u8 = 0,
    canceled: bool = false,

    pub fn init(policy: Policy, now_ms: i64) Retry {
        return .{ .policy = policy, .started_ms = now_ms };
    }

    pub fn cancel(self: *Retry) void {
        self.canceled = true;
    }

    fn remainingMs(self: *const Retry, now_ms: i64) ?u64 {
        const elapsed = now_ms - self.started_ms;
        if (elapsed < 0) return 0;
        const used: u64 = @intCast(elapsed);
        if (used >= self.policy.total_deadline_ms) return null;
        return self.policy.total_deadline_ms - used;
    }

    fn backoffMs(self: *const Retry) u64 {
        const shift: u6 = @intCast(@min(self.attempts, 10));
        const base = self.policy.base_delay_ms << shift;
        return @min(base, self.policy.max_delay_ms);
    }

    pub fn afterTransportError(
        self: *Retry,
        idempotency: Idempotency,
        body_sent: bool,
        now_ms: i64,
    ) Outcome {
        if (self.canceled) return .canceled;
        if (self.attempts >= self.policy.max_attempts) return .fail;
        if (idempotency == .non_idempotent and body_sent) return .ambiguous;

        const delay = self.backoffMs();
        const remaining = self.remainingMs(now_ms) orelse return .fail;
        if (delay > remaining) return .fail;
        self.attempts += 1;
        return .{ .retry_after_ms = delay };
    }

    /// Handles a received HTTP response. 429 uses the server-provided wait when
    /// available; transient 5xx uses bounded backoff.
    pub fn afterResponse(
        self: *Retry,
        status: u16,
        idempotency: Idempotency,
        server_wait_ms: ?u64,
        now_ms: i64,
    ) Outcome {
        if (self.canceled) return .canceled;
        if (status >= 200 and status < 300) return .success;
        if (idempotency == .non_idempotent and status >= 500) return .ambiguous;
        if (status != 429 and !(status >= 500 and status < 600)) return .fail;
        if (self.attempts >= self.policy.max_attempts) return .fail;

        const delay = if (status == 429)
            (server_wait_ms orelse self.backoffMs())
        else
            self.backoffMs();

        const remaining = self.remainingMs(now_ms) orelse return .fail;
        if (delay > remaining) return .fail;
        self.attempts += 1;
        return .{ .retry_after_ms = delay };
    }
};

test "non-idempotent body delivery is ambiguous, not replayed" {
    var state = Retry.init(.{}, 0);
    try std.testing.expect(state.afterTransportError(.non_idempotent, true, 0) == .ambiguous);
    try std.testing.expectEqual(@as(u8, 0), state.attempts);
}

test "connect failure before body can retry a create" {
    var state = Retry.init(.{}, 0);
    const outcome = state.afterTransportError(.non_idempotent, false, 0);
    try std.testing.expect(outcome == .retry_after_ms);
}

test "safe read retries transient 5xx finitely" {
    var state = Retry.init(.{ .max_attempts = 2 }, 0);
    try std.testing.expect(state.afterResponse(500, .safe, null, 0) == .retry_after_ms);
    try std.testing.expect(state.afterResponse(500, .safe, null, 10) == .retry_after_ms);
    try std.testing.expect(state.afterResponse(500, .safe, null, 20) == .fail);
}

test "429 wait beyond the deadline fails closed" {
    var state = Retry.init(.{ .total_deadline_ms = 1000 }, 0);
    try std.testing.expect(state.afterResponse(429, .safe, 2000, 0) == .fail);
}

test "cancellation prevents any later retry" {
    var state = Retry.init(.{}, 0);
    state.cancel();
    try std.testing.expect(state.afterResponse(500, .safe, null, 0) == .canceled);
    try std.testing.expect(state.afterTransportError(.safe, false, 0) == .canceled);
}

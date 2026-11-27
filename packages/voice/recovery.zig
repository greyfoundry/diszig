//! Bounded voice connection recovery policy.
//!
//! Voice close codes decide resume, reconnect or stop (see `gateway.zig`). This
//! module turns those decisions into a finite budget with capped exponential
//! backoff. It never resumes a fatal session and never loops forever.

const std = @import("std");
const gateway = @import("gateway.zig");

pub const Decision = union(enum) {
    resume_session: u32,
    reconnect: u32,
    stop,
};

pub const Policy = struct {
    max_resume_attempts: u8 = 5,
    max_reconnects: u8 = 5,
    base_delay_ms: u32 = 500,
    max_delay_ms: u32 = 30_000,
};

pub const Recovery = struct {
    policy: Policy,
    resume_attempts: u8 = 0,
    reconnect_attempts: u8 = 0,
    stopped: bool = false,

    pub fn init(policy: Policy) Recovery {
        return .{ .policy = policy };
    }

    /// Called with the parsed close code. The returned delay is the wait before
    /// the next attempt; `stop` means do not reconnect.
    pub fn onClose(self: *Recovery, code: u16) Decision {
        if (self.stopped) return .stop;
        const action = gateway.classifyClose(code);
        switch (action) {
            .stop => {
                self.stopped = true;
                return .stop;
            },
            .resume_session => {
                if (self.resume_attempts < self.policy.max_resume_attempts) {
                    self.resume_attempts += 1;
                    return .{ .resume_session = self.delayMs(self.resume_attempts) };
                }
                // Resume budget exhausted: start a new session instead.
                return self.reconnectOrStop();
            },
            .reconnect => {
                self.resume_attempts = 0;
                return self.reconnectOrStop();
            },
        }
    }

    fn reconnectOrStop(self: *Recovery) Decision {
        if (self.reconnect_attempts >= self.policy.max_reconnects) {
            self.stopped = true;
            return .stop;
        }
        self.reconnect_attempts += 1;
        return .{ .reconnect = self.delayMs(self.reconnect_attempts) };
    }

    /// A successful Ready or Resumed clears both budgets.
    pub fn onSessionUp(self: *Recovery) void {
        self.resume_attempts = 0;
        self.reconnect_attempts = 0;
    }

    pub fn delayMs(self: Recovery, attempt: u8) u32 {
        var delay = self.policy.base_delay_ms;
        var index: u8 = 1;
        while (index < attempt) : (index += 1) {
            delay = delay *| 2;
            if (delay >= self.policy.max_delay_ms) return self.policy.max_delay_ms;
        }
        return @min(delay, self.policy.max_delay_ms);
    }
};

test "fatal close stops immediately" {
    var recovery = Recovery.init(.{});
    try std.testing.expectEqual(Decision.stop, recovery.onClose(4014));
    try std.testing.expectEqual(Decision.stop, recovery.onClose(4015));
}

test "resume budget falls back to bounded reconnect" {
    var recovery = Recovery.init(.{ .max_resume_attempts = 2, .max_reconnects = 2 });
    const first = recovery.onClose(4015);
    try std.testing.expect(first == .resume_session);
    const second = recovery.onClose(4015);
    try std.testing.expect(second == .resume_session);
    const third = recovery.onClose(4015);
    try std.testing.expect(third == .reconnect);
    try std.testing.expectEqual(@as(u8, 1), recovery.reconnect_attempts);
    const fourth = recovery.onClose(4015);
    try std.testing.expect(fourth == .reconnect);
    try std.testing.expectEqual(Decision.stop, recovery.onClose(4015));
}

test "reconnect delay grows and is capped" {
    var recovery = Recovery.init(.{ .base_delay_ms = 100, .max_delay_ms = 250, .max_reconnects = 8 });
    try std.testing.expectEqual(@as(u32, 100), recovery.delayMs(1));
    try std.testing.expectEqual(@as(u32, 200), recovery.delayMs(2));
    try std.testing.expectEqual(@as(u32, 250), recovery.delayMs(3));
    try std.testing.expectEqual(@as(u32, 250), recovery.delayMs(255));
}

test "session up clears budgets and reconnect resets resume count" {
    var recovery = Recovery.init(.{});
    _ = recovery.onClose(4015);
    _ = recovery.onClose(4006);
    recovery.onSessionUp();
    try std.testing.expectEqual(@as(u8, 0), recovery.resume_attempts);
    try std.testing.expectEqual(@as(u8, 0), recovery.reconnect_attempts);

    _ = recovery.onClose(4015);
    _ = recovery.onClose(4015);
    _ = recovery.onClose(4006); // reconnect resets resume attempts
    try std.testing.expectEqual(@as(u8, 0), recovery.resume_attempts);
}

test "unknown close is a bounded reconnect, never a silent success" {
    var recovery = Recovery.init(.{ .max_reconnects = 1 });
    try std.testing.expect(recovery.onClose(9999) == .reconnect);
    try std.testing.expectEqual(Decision.stop, recovery.onClose(9999));
}

test "stopped recovery ignores later closes" {
    var recovery = Recovery.init(.{});
    try std.testing.expectEqual(Decision.stop, recovery.onClose(4004));
    try std.testing.expectEqual(Decision.stop, recovery.onClose(4015));
}

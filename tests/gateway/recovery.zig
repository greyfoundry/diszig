//! Recovery policy contracts: close classification, session state, separate
//! identify/resume budgets, bounded backoff and payload safety.

const std = @import("std");
const diszig = @import("diszig");
const recovery = diszig.gateway.recovery;

const Recovery = recovery.Recovery;
const Decision = recovery.Decision;
const CloseAction = recovery.CloseAction;

fn make(now: u64, config: recovery.Config) Recovery {
    return Recovery.init(now, config);
}

fn ready(rec: *Recovery) !void {
    try rec.onReady("session-1", "wss://resume.example", 7);
}

test "resumable loss keeps the session and sequence for Resume" {
    var rec = make(0, .{});
    try ready(&rec);
    try std.testing.expect(rec.canResume());
    try std.testing.expectEqualStrings("session-1", rec.state.id());
    try std.testing.expectEqualStrings("wss://resume.example", rec.state.url());
    try std.testing.expectEqual(@as(?i64, 7), rec.state.sequence);

    rec.onDispatch(9);
    try std.testing.expectEqual(@as(?i64, 9), rec.state.sequence);

    try std.testing.expectEqual(Decision.resume_session, rec.onClose(1006, 10));
    try std.testing.expect(rec.canResume());
}

test "invalid nonresumable session clears the session and identifies" {
    var rec = make(0, .{});
    try ready(&rec);
    try std.testing.expectEqual(Decision.reidentify, rec.onInvalidSession(false, 10));
    try std.testing.expect(!rec.canResume());
    try std.testing.expectEqual(@as(usize, 0), rec.state.id().len);
}

test "invalid resumable session asks for Resume" {
    var rec = make(0, .{});
    try ready(&rec);
    try std.testing.expectEqual(Decision.resume_session, rec.onInvalidSession(true, 10));
    try std.testing.expect(rec.canResume());
}

test "fatal close codes stop instead of looping" {
    var rec = make(0, .{});
    try ready(&rec);
    try std.testing.expectEqual(Decision.fatal, rec.onClose(4004, 10));
    try std.testing.expectEqual(Decision.fatal, rec.onClose(4013, 10));
    try std.testing.expectEqual(Decision.fatal, rec.onClose(4014, 10));
    try std.testing.expectEqual(Decision.fatal, rec.onClose(4010, 10));
}

test "normal close stops" {
    var rec = make(0, .{});
    try ready(&rec);
    try std.testing.expectEqual(Decision.stop, rec.onClose(1000, 10));
    try std.testing.expectEqual(Decision.stop, rec.onClose(1001, 10));
}

test "invalid seq and session timeout reidentify" {
    var rec = make(0, .{});
    try ready(&rec);
    try std.testing.expectEqual(Decision.reidentify, rec.onClose(4007, 10));
    try ready(&rec);
    try std.testing.expectEqual(Decision.reidentify, rec.onClose(4009, 20));
}

test "identify and resume budgets are separate and bounded" {
    var rec = make(0, .{
        .resume_limit = 2,
        .resume_window_ms = 10_000,
        .identify_limit = 1,
        .identify_window_ms = 10_000,
    });
    try ready(&rec);
    try std.testing.expectEqual(Decision.resume_session, rec.onClose(1006, 0));
    try std.testing.expectEqual(Decision.resume_session, rec.onClose(1006, 1));
    // Resume budget exhausted: fall back to the still-available Identify.
    try std.testing.expectEqual(Decision.reidentify, rec.onClose(1006, 2));
    // Identify budget now exhausted too.
    try std.testing.expectEqual(Decision.exhausted, rec.onClose(1006, 3));
    // A new window restores capacity.
    try std.testing.expectEqual(Decision.reidentify, rec.onClose(1006, 10_001));
}

test "reconnect event resumes when possible otherwise identifies" {
    var rec = make(0, .{});
    try std.testing.expectEqual(Decision.reidentify, rec.onReconnect(0));
    try ready(&rec);
    try std.testing.expectEqual(Decision.resume_session, rec.onReconnect(10));
}

test "backoff is bounded and exhausts attempts" {
    var rec = make(0, .{
        .backoff_base_ms = 1000,
        .backoff_max_ms = 5000,
        .max_attempts = 4,
    });
    try std.testing.expectEqual(@as(?u64, 1000), rec.nextDelay());
    try std.testing.expectEqual(@as(?u64, 2000), rec.nextDelay());
    try std.testing.expectEqual(@as(?u64, 4000), rec.nextDelay());
    try std.testing.expectEqual(@as(?u64, 5000), rec.nextDelay());
    try std.testing.expectEqual(@as(?u64, null), rec.nextDelay());
    rec.backoff.reset();
    try std.testing.expectEqual(@as(?u64, 1000), rec.nextDelay());
}

test "a successful ready resets the backoff attempt counter" {
    var rec = make(0, .{ .backoff_base_ms = 1000, .backoff_max_ms = 60_000, .max_attempts = 3 });
    _ = rec.nextDelay();
    _ = rec.nextDelay();
    try ready(&rec);
    try std.testing.expectEqual(@as(?u64, 1000), rec.nextDelay());
}

test "session state rejects oversized identifiers and wipes on clear" {
    var state = recovery.SessionState.init();
    var big: [recovery.max_session_id + 1]u8 = @splat('a');
    try std.testing.expectError(
        error.SessionIdTooLong,
        state.setReady(&big, "wss://resume", 1),
    );
    try state.setReady("session", "wss://resume", 2);
    state.clear();
    try std.testing.expectEqual(@as(usize, 0), state.id().len);
    try std.testing.expectEqual(@as(?i64, null), state.sequence);
}

test "identify and resume payloads are escaped by validation" {
    var buffer: [512]u8 = undefined;
    const identify = try recovery.writeIdentify(&buffer, .{
        .token = "abc.def-123",
        .intents = 5,
        .shard = .{ 0, 1 },
    });
    try std.testing.expect(std.mem.indexOf(u8, identify, "\"shard\":[0,1]") != null);

    try std.testing.expectError(
        error.InvalidCredential,
        recovery.writeIdentify(&buffer, .{ .token = "bad\"token", .intents = 5 }),
    );
    try std.testing.expectError(
        error.InvalidCredential,
        recovery.writeResume(&buffer, "bot", "session\"id", 1),
    );
    try std.testing.expectError(
        error.InvalidShard,
        recovery.writeIdentify(&buffer, .{ .token = "bot", .intents = 5, .shard = .{ 1, 1 } }),
    );

    const resume_payload = try recovery.writeResume(&buffer, "bot.token", "session-1", 42);
    try std.testing.expect(std.mem.indexOf(u8, resume_payload, "\"seq\":42") != null);
}

test "close classification matrix" {
    try std.testing.expectEqual(CloseAction.resume_session, recovery.classifyClose(null));
    try std.testing.expectEqual(CloseAction.resume_session, recovery.classifyClose(1006));
    try std.testing.expectEqual(CloseAction.resume_session, recovery.classifyClose(4000));
    try std.testing.expectEqual(CloseAction.resume_session, recovery.classifyClose(4099));
    try std.testing.expectEqual(CloseAction.reidentify, recovery.classifyClose(4003));
    try std.testing.expectEqual(CloseAction.reidentify, recovery.classifyClose(4005));
    try std.testing.expectEqual(CloseAction.reidentify, recovery.classifyClose(4007));
    try std.testing.expectEqual(CloseAction.reidentify, recovery.classifyClose(4009));
    try std.testing.expectEqual(CloseAction.fatal, recovery.classifyClose(4004));
    try std.testing.expectEqual(CloseAction.fatal, recovery.classifyClose(4011));
    try std.testing.expectEqual(CloseAction.fatal, recovery.classifyClose(4012));
    try std.testing.expectEqual(CloseAction.fatal, recovery.classifyClose(5000));
}

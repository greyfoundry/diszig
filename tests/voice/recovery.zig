//! Voice recovery policy contracts.

const std = @import("std");
const diszig = @import("diszig");
const recovery = diszig.voice.recovery;

test "recovery module is exported and fatal closes stop" {
    var state = recovery.Recovery.init(.{});
    try std.testing.expectEqual(recovery.Decision.stop, state.onClose(4022));
}

test "resume then bounded reconnect" {
    var state = recovery.Recovery.init(.{ .max_resume_attempts = 1, .max_reconnects = 1 });
    try std.testing.expect(state.onClose(4015) == .resume_session);
    try std.testing.expect(state.onClose(4015) == .reconnect);
    try std.testing.expectEqual(recovery.Decision.stop, state.onClose(4015));
}

test "backoff is capped and session-up resets" {
    var state = recovery.Recovery.init(.{ .base_delay_ms = 50, .max_delay_ms = 120, .max_reconnects = 4 });
    try std.testing.expectEqual(@as(u32, 50), state.delayMs(1));
    try std.testing.expectEqual(@as(u32, 120), state.delayMs(4));
    _ = state.onClose(4015);
    state.onSessionUp();
    try std.testing.expectEqual(@as(u8, 0), state.resume_attempts);
}

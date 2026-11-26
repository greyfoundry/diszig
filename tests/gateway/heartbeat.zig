//! Heartbeat deadline contracts. The scheduler is pure, so every case is
//! deterministic and does not need a real clock or socket.

const std = @import("std");
const diszig = @import("diszig");
const heartbeat = diszig.gateway.heartbeat;

const Heartbeat = heartbeat.Heartbeat;
const Action = heartbeat.Action;

fn make(interval: u64, delay: u64) Heartbeat {
    return Heartbeat.init(interval, 10_000, delay);
}

test "first heartbeat waits for the jittered delay" {
    var hb = make(1000, 250);
    try std.testing.expectEqual(Action.none, hb.poll(10_249));
    try std.testing.expectEqual(Action.send, hb.poll(10_250));
    try std.testing.expect(hb.awaiting_ack);
    try std.testing.expectEqual(@as(u64, 1), hb.sent_count);
}

test "heartbeat repeats every interval after an ack" {
    var hb = make(1000, 0);
    try std.testing.expectEqual(Action.send, hb.poll(10_000));
    hb.ack();
    try std.testing.expectEqual(Action.none, hb.poll(10_999));
    try std.testing.expectEqual(Action.send, hb.poll(11_000));
    try std.testing.expectEqual(Action.none, hb.poll(11_001));
    try std.testing.expectEqual(@as(u64, 2), hb.sent_count);
}

test "a missing ack marks the connection as a zombie" {
    var hb = make(1000, 0);
    try std.testing.expectEqual(Action.send, hb.poll(10_000));
    // No ack before the next deadline.
    try std.testing.expectEqual(Action.zombie, hb.poll(11_000));
    try std.testing.expect(hb.stopped);
    try std.testing.expectEqual(Action.none, hb.poll(12_000));
    try std.testing.expectEqual(Action.none, hb.poll(20_000));
}

test "a server heartbeat request sends before the deadline" {
    var hb = make(1000, 5_000);
    try std.testing.expectEqual(Action.none, hb.poll(10_000));
    hb.request();
    try std.testing.expectEqual(Action.send, hb.poll(10_001));
    try std.testing.expect(hb.awaiting_ack);
}

test "a delayed loop sends once and does not burst" {
    var hb = make(1000, 0);
    try std.testing.expectEqual(Action.send, hb.poll(10_000));
    hb.ack();
    // The loop was blocked for 3.5 intervals.
    try std.testing.expectEqual(Action.send, hb.poll(13_500));
    try std.testing.expectEqual(Action.none, hb.poll(13_501));
    try std.testing.expectEqual(Action.none, hb.poll(14_499));
    try std.testing.expectEqual(@as(u64, 2), hb.sent_count);
}

test "cancel before the first timer leaves no scheduled work" {
    var hb = make(1000, 500);
    hb.stop();
    try std.testing.expectEqual(Action.none, hb.poll(10_500));
    try std.testing.expectEqual(@as(u64, 0), hb.sent_count);
}

test "the last sequence is retained for the heartbeat payload" {
    var hb = make(1000, 0);
    hb.setSequence(7);
    try std.testing.expectEqual(@as(?i64, 7), hb.last_sequence);
    hb.setSequence(null);
    try std.testing.expectEqual(@as(?i64, null), hb.last_sequence);
}

test "jitter boundaries and out-of-range values" {
    try std.testing.expectEqual(@as(u64, 0), Heartbeat.jitteredDelay(45_000, 0.0));
    try std.testing.expectEqual(@as(u64, 22_500), Heartbeat.jitteredDelay(45_000, 0.5));
    try std.testing.expectEqual(@as(u64, 45_000), Heartbeat.jitteredDelay(45_000, 1.0));
    try std.testing.expectEqual(@as(u64, 45_000), Heartbeat.jitteredDelay(45_000, -0.5));
}

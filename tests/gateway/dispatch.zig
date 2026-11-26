//! Dispatch contracts: bounded FIFO, raw fallback, explicit overload,
//! duplicate replay semantics and the handler copy path.

const std = @import("std");
const diszig = @import("diszig");
const dispatch = diszig.gateway.dispatch;
const events = diszig.gateway.events;
const Heartbeat = diszig.gateway.Heartbeat;

test "unknown event with extra data is delivered raw" {
    const payload =
        \\{"op":0,"t":"FUTURE_EVENT","s":12,"d":{"nested":{"future":[1,2,3]},"unknown":true}}
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();

    const event = try events.decode(arena.allocator(), "FUTURE_EVENT", 12, payload, 1024);
    try std.testing.expect(event == .raw);
    try std.testing.expectEqualStrings("FUTURE_EVENT", event.raw.name);
    try std.testing.expectEqualStrings(payload, event.raw.payload);
    try std.testing.expectEqual(@as(?i64, 12), event.raw.sequence);
}

test "slow consumer hits the queue limit and the heartbeat still advances" {
    var queue = try dispatch.Queue.init(std.testing.allocator, .{ .capacity = 2 });
    defer queue.deinit();

    try queue.tryPush("A", 1, "a");
    try queue.tryPush("B", 2, "b");
    try std.testing.expectError(error.QueueFull, queue.tryPush("C", 3, "c"));
    try std.testing.expectEqual(@as(u64, 1), queue.droppedCount());
    try std.testing.expectEqual(@as(usize, 2), queue.pending());

    // The queue never blocks or couples to the scheduler.
    var heartbeat = Heartbeat.init(1000, 0, 0);
    try std.testing.expectEqual(diszig.gateway.heartbeat.Action.send, heartbeat.poll(0));
    heartbeat.ack();
    try std.testing.expectEqual(diszig.gateway.heartbeat.Action.send, heartbeat.poll(1000));
}

test "resume replay duplicates are delivered, not silently deduplicated" {
    var queue = try dispatch.Queue.init(std.testing.allocator, .{ .capacity = 2 });
    defer queue.deinit();
    try queue.tryPush("MESSAGE_CREATE", 7, "{\"id\":\"1\"}");
    try queue.tryPush("MESSAGE_CREATE", 7, "{\"id\":\"1\"}");

    var delivered: usize = 0;
    while (queue.pop()) |event| {
        try std.testing.expectEqual(@as(?i64, 7), event.sequence);
        delivered += 1;
        queue.release();
    }
    try std.testing.expectEqual(@as(usize, 2), delivered);
}

test "a handler copies a borrowed event before releasing it" {
    var queue = try dispatch.Queue.init(std.testing.allocator, .{ .capacity = 1 });
    defer queue.deinit();
    try queue.tryPush("MESSAGE_CREATE", 3, "{\"id\":\"42\"}");

    const borrowed = queue.pop().?;
    var retained = try borrowed.copy(std.testing.allocator);
    defer retained.deinit();
    queue.release();

    try queue.tryPush("MESSAGE_DELETE", 4, "{\"id\":\"42\"}");
    try std.testing.expectEqualStrings("MESSAGE_CREATE", retained.name);
    try std.testing.expectEqualStrings("{\"id\":\"42\"}", retained.payload);
}

test "session envelope feeds the bounded queue without re-parsing" {
    const payload =
        \\{"op":0,"t":"MESSAGE_CREATE","s":8,"d":{"id":"99","content":"hi"}}
    ;
    const parsed = try diszig.gateway.session.parseEnvelope(
        std.testing.allocator,
        payload,
        1024,
    );
    var queue = try dispatch.Queue.init(std.testing.allocator, .{ .capacity = 1 });
    defer queue.deinit();
    try queue.tryPush(parsed.name(), parsed.sequence, payload);

    const event = queue.pop().?;
    try std.testing.expectEqualStrings("MESSAGE_CREATE", event.name);
    try std.testing.expectEqual(@as(?i64, 8), event.sequence);
    try std.testing.expectEqualStrings(payload, event.payload);
    queue.release();
}

test "queue bounds produce explicit errors" {
    var queue = try dispatch.Queue.init(std.testing.allocator, .{
        .capacity = 1,
        .max_event_bytes = 4,
        .max_name = 8,
    });
    defer queue.deinit();
    try std.testing.expectError(error.NameTooLong, queue.tryPush("TOO_LONG_NAME", null, "x"));
    try std.testing.expectError(error.EventTooLarge, queue.tryPush("OK", null, "12345"));
    try std.testing.expectError(error.CapacityZero, dispatch.Queue.init(std.testing.allocator, .{ .capacity = 0 }));
}

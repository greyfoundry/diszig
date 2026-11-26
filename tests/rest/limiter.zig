const std = @import("std");
const diszig = @import("diszig");

fn isGranted(admission: diszig.rest.limiter.Admission) bool {
    return switch (admission) {
        .granted => true,
        .wait_ms => false,
    };
}

test "shared learned bucket serializes two routes" {
    var limiter = diszig.rest.limiter.Limiter.init(4);
    try limiter.learn("GET /a guild=1", .{ .bucket_id = "shared", .limit = 1, .remaining = 1, .reset_after_ms = 1000 }, 0);
    try limiter.learn("GET /b guild=1", .{ .bucket_id = "shared" }, 0);
    try std.testing.expect(isGranted(try limiter.acquire("GET /a guild=1", 0)));
    const second = try limiter.acquire("GET /b guild=1", 0);
    try std.testing.expect(!isGranted(second));
}

test "global 429 pauses all routes" {
    var limiter = diszig.rest.limiter.Limiter.init(4);
    try limiter.learn("GET /a", .{ .status = 429, .global = true, .retry_after_ms = 1000 }, 0);
    const admission = try limiter.acquire("GET /b", 10);
    try std.testing.expect(!isGranted(admission));
}

test "queue capacity and cancellation are explicit" {
    var limiter = diszig.rest.limiter.Limiter.init(1);
    _ = try limiter.acquire("GET /a", 0);
    try std.testing.expectError(error.QueueFull, limiter.acquire("GET /b", 0));
    limiter.cancelPending();
    try std.testing.expectError(error.Canceled, limiter.acquire("GET /a", 0));
}

test "fractional retry-after rounds up" {
    try std.testing.expectEqual(@as(?u64, 1500), diszig.rest.limiter.parseSecondsToMs("1.5"));
    try std.testing.expectEqual(@as(?u64, null), diszig.rest.limiter.parseSecondsToMs("-1"));
}

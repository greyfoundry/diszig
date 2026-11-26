const std = @import("std");
const diszig = @import("diszig");

test "public retry policy refuses to replay ambiguous creates" {
    var state = diszig.rest.retry.Retry.init(.{}, 0);
    const outcome = state.afterTransportError(.non_idempotent, true, 0);
    try std.testing.expect(outcome == .ambiguous);
}

test "public retry policy bounds 429 waits" {
    var state = diszig.rest.retry.Retry.init(.{ .total_deadline_ms = 500 }, 0);
    const outcome = state.afterResponse(429, .safe, 1000, 0);
    try std.testing.expect(outcome == .fail);
}

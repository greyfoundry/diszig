const std = @import("std");

pub fn run(io: std.Io, timeout_ns: u64, comptime operation: anytype, args: anytype) !void {
    const Task = struct {
        fn execute(owner: std.Io, arguments: @TypeOf(args), done: *std.Io.Event) !void {
            defer done.set(owner);
            return @call(.auto, operation, arguments);
        }
    };
    const deadline = std.Io.Clock.awake.now(io).nanoseconds + @as(i128, timeout_ns);
    if (timeout_ns == 0) return error.CloseTimeout;
    var done: std.Io.Event = .unset;
    var future = try io.concurrent(Task.execute, .{ io, args, &done });
    errdefer future.cancel(io) catch {};
    while (!done.isSet()) {
        const remaining = deadline - std.Io.Clock.awake.now(io).nanoseconds;
        if (remaining <= 0) return error.CloseTimeout;
        done.waitTimeout(io, .{ .duration = .{ .raw = .fromNanoseconds(@intCast(remaining)), .clock = .awake } }) catch |err| switch (err) {
            error.Timeout => {},
            error.Canceled => return err,
        };
    }
    try io.checkCancel();
    if (std.Io.Clock.awake.now(io).nanoseconds >= deadline) return error.CloseTimeout;
    try future.await(io);
}

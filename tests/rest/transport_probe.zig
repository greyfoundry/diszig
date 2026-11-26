const std = @import("std");
const diszig = @import("diszig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) return error.MissingArguments;
    const mode = args[1];
    const port = try std.fmt.parseInt(u16, args[2], 10);

    var base_buffer: [64]u8 = undefined;
    const base = try std.fmt.bufPrint(&base_buffer, "http://127.0.0.1:{d}", .{port});

    var client = try diszig.rest.Client.init(init.gpa, init.io, .{
        .base_url = base,
        .auth = .{ .bearer = "abc" },
        .max_response_bytes = 4096,
    });
    defer client.deinit();

    var stdout_buffer: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);

    if (std.mem.eql(u8, mode, "get")) {
        var response = try client.send(.GET, "/ok", .{});
        defer response.deinit();
        try stdout.interface.print("status={d} body={s}\n", .{ response.status, response.body });
    } else if (std.mem.eql(u8, mode, "redirect")) {
        var response = try client.send(.GET, "/redirect", .{});
        defer response.deinit();
        try stdout.interface.print("status={d} body={s}\n", .{ response.status, response.body });
    } else if (std.mem.eql(u8, mode, "cross")) {
        _ = client.send(.GET, "/cross", .{}) catch |err| {
            try stdout.interface.print("error={s}\n", .{@errorName(err)});
            try stdout.interface.flush();
            return;
        };
        return error.ExpectedCrossOriginFailure;
    } else if (std.mem.eql(u8, mode, "empty")) {
        var response = try client.send(.GET, "/empty", .{});
        defer response.deinit();
        try stdout.interface.print("status={d} len={d}\n", .{ response.status, response.body.len });
    } else {
        return error.UnknownMode;
    }
    try stdout.interface.flush();
}

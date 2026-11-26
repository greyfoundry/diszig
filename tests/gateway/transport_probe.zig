//! Local Gateway transport probe.
//!
//! Connects to `tests/gateway/transport_fixture.py`, a raw RFC 6455 server,
//! and prints one line per observed outcome. It never contacts Discord.

const std = @import("std");
const diszig = @import("diszig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 4) return error.MissingArguments;
    const mode = args[1];
    const port = try std.fmt.parseInt(u16, args[2], 10);
    const bound = try std.fmt.parseInt(usize, args[3], 10);

    var url_buffer: [64]u8 = undefined;
    const url_text = try std.fmt.bufPrint(&url_buffer, "ws://127.0.0.1:{d}/", .{port});
    const url = try diszig.gateway.Url.parse(url_text);

    const compressed = std.mem.eql(u8, mode, "compressed") or std.mem.eql(u8, mode, "bomb");
    var connection = try diszig.gateway.Connection.connect(init.gpa, init.io, .{
        .url = url,
        .max_message_bytes = bound,
        .read_buffer_bytes = @min(bound, 8 * 1024),
        .compression = if (compressed) .zlib_stream else .none,
        .handshake_timeout_ms = 3000,
        .read_timeout_ms = 2000,
    });
    defer connection.deinit();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const out = &stdout.interface;

    if (std.mem.eql(u8, mode, "partial") or std.mem.eql(u8, mode, "bomb")) {
        const result = connection.next();
        if (result) |maybe_message| {
            if (maybe_message) |message| {
                try out.print("unexpected:{s}\n", .{message.data});
            } else {
                try out.print("timeout\n", .{});
            }
        } else |err| {
            try out.print("error:{s}\n", .{@errorName(err)});
        }
        try out.flush();
        return;
    }

    var seen: usize = 0;
    while (seen < 4) : (seen += 1) {
        const result = connection.next();
        if (result) |maybe_message| {
            const message = maybe_message orelse {
                try out.print("timeout\n", .{});
                break;
            };
            switch (message.kind) {
                .text => try out.print("msg:{s}\n", .{message.data}),
                .binary => try out.print("binary:{d}\n", .{message.data.len}),
                .close => {
                    try out.print("close:{?d}\n", .{message.close_code});
                    break;
                },
            }
        } else |err| {
            try out.print("error:{s}\n", .{@errorName(err)});
            break;
        }
    }
    try out.flush();
}

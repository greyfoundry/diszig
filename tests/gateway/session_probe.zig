//! Local Gateway session probe: Hello, background heartbeat and ACK liveness.
//!
//! The probe never calls `tick` itself. A separate thread must keep sending
//! heartbeats while this loop only reads, which is the ownership split the
//! session documents.

const std = @import("std");
const diszig = @import("diszig");

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);
    if (args.len < 3) return error.MissingArguments;
    // args[1] is the fixture mode; the server drives the scenario.
    const port = try std.fmt.parseInt(u16, args[2], 10);

    var url_buffer: [64]u8 = undefined;
    const url_text = try std.fmt.bufPrint(&url_buffer, "ws://127.0.0.1:{d}/", .{port});
    const url = try diszig.gateway.Url.parse(url_text);

    var session = try diszig.gateway.Session.connect(init.gpa, init.io, .{
        .transport = .{
            .url = url,
            .max_message_bytes = 64 * 1024,
            .read_buffer_bytes = 8 * 1024,
            .handshake_timeout_ms = 3000,
        },
        // Deterministic first heartbeat for the fixture.
        .initial_jitter = 0.0,
    });
    defer session.deinit();
    try session.startHeartbeat();

    var stdout_buffer: [4096]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    const out = &stdout.interface;

    var iterations: usize = 0;
    while (iterations < 16) : (iterations += 1) {
        const result = session.next();
        if (result) |message| {
            switch (message.kind) {
                .text => try out.print("event:{s}\n", .{message.data}),
                .close => {
                    try out.print("close:{?d}\n", .{message.close_code});
                    break;
                },
                .binary => try out.print("binary:{d}\n", .{message.data.len}),
            }
        } else |err| {
            try out.print("error:{s}\n", .{@errorName(err)});
            break;
        }
        if (session.isZombie()) break;
    }

    try out.print("heartbeats:{d}\n", .{try session.heartbeatCount()});
    if (session.isZombie()) try out.print("zombie\n", .{});
    try out.flush();
}

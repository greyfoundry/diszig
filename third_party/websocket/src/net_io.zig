const std = @import("std");
const Io = std.Io;
const net = Io.net;

pub fn read(io: Io, handle: net.Socket.Handle, data: [][]u8) !usize {
    const result = try io.operate(.{ .net_read = .{ .socket_handle = handle, .data = data } });
    return (try result.net_read).data_len;
}

pub fn write(io: Io, handle: net.Socket.Handle, bytes: []const u8) !usize {
    const result = try io.operate(.{ .net_write = .{
        .socket_handle = handle,
        .header = bytes,
        .data = &.{""},
        .splat = 0,
    } });
    return result.net_write;
}

pub fn writeWithSocketTimeout(handle: net.Socket.Handle, bytes: []const u8) !usize {
    while (true) {
        const result = std.c.send(handle, bytes.ptr, bytes.len, std.posix.MSG.NOSIGNAL);
        switch (std.posix.errno(result)) {
            .SUCCESS => return @intCast(result),
            .INTR => continue,
            .AGAIN => return error.ConnectionTimedOut,
            .PIPE, .CONNRESET, .NOTCONN => return error.ConnectionResetByPeer,
            .BADF => unreachable,
            else => |err| return std.posix.unexpectedErrno(err),
        }
    }
}

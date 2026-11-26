const std = @import("std");
const diszig = @import("diszig");

pub fn main(init: std.process.Init) !void {
    const id = try diszig.Snowflake.parse("18446744073709551615");

    var buffer: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try id.writeDecimal(&writer);

    var stdout_buffer: [256]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &stdout_buffer);
    try stdout.interface.print("{s} {d}\n", .{ writer.buffered(), id.timestampMs() });
    try stdout.interface.flush();
}

const std = @import("std");
const diszig = @import("diszig");

test "public paginator returns a bounded first page and stops on empty" {
    var pager = diszig.rest.pagination.Paginator.init(.after, 50);
    const first = (try pager.next(null, 0)).?;
    try std.testing.expectEqual(@as(u16, 50), first.limit);

    const second = (try pager.next(10, 1)).?;
    try std.testing.expectEqual(@as(?u64, 10), second.after);
    try std.testing.expectEqual(@as(?diszig.rest.pagination.PageRequest, null), try pager.next(0, 0));
}

test "public paginator rejects a repeated cursor" {
    var pager = diszig.rest.pagination.Paginator.init(.before, 25);
    _ = try pager.next(null, 0);
    _ = try pager.next(99, 2);
    try std.testing.expectError(error.DuplicateCursor, pager.next(99, 2));
}

test "public audit reason encoder handles unicode and bounds" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try diszig.rest.audit.encode(&writer, "caf\u{00E9}");
    try std.testing.expectEqualStrings("caf%C3%A9", writer.buffered());

    var second: [128]u8 = undefined;
    var second_writer = std.Io.Writer.fixed(&second);
    try std.testing.expectError(error.EmptyReason, diszig.rest.audit.encode(&second_writer, ""));
}

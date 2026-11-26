const std = @import("std");
const diszig = @import("diszig");

test "public REST error retains nested path and unknown code" {
    const body =
        \\{"code":999999,"errors":{"field":{"nested":{"_errors":[{"code":"X"}]}}}}
    ;
    const path = try diszig.rest.errors.firstFieldPath(std.testing.allocator, body, 4096);
    try std.testing.expectEqualStrings("field.nested", path.text());

    const api_error = diszig.rest.errors.ApiError{
        .status = .{ .code = 400 },
        .code = 999999,
    };
    try std.testing.expect(api_error.unknownCode(&.{50035}));
}

test "webhook credential is absent from REST diagnostics" {
    var context = diszig.protocol.errors.Context.init(.http_status);
    context.setDetail("https://discord.com/api/webhooks/123/abcdefghijklmnopqrstuvwxyz");
    try std.testing.expect(std.mem.indexOf(u8, context.detail(), "abcdefghijklmnopqrstuvwxyz") == null);
}

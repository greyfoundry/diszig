const std = @import("std");
const diszig = @import("diszig");

test "route identity includes method, normalized path and major" {
    var a_buf: [160]u8 = undefined;
    var b_buf: [160]u8 = undefined;
    var a_writer = std.Io.Writer.fixed(&a_buf);
    var b_writer = std.Io.Writer.fixed(&b_buf);
    try diszig.rest.routes.create_message.identity(1).writeBucketKey(&a_writer);
    try diszig.rest.routes.create_message.identity(2).writeBucketKey(&b_writer);
    try std.testing.expect(!std.mem.eql(u8, a_writer.buffered(), b_writer.buffered()));
}

test "webhook tokens are absent from bucket keys" {
    var buffer: [160]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try diszig.rest.routes.execute_webhook.identity(42).writeBucketKey(&writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "webhooks/{}/{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "secret") == null);
}

test "public encoding and query helpers" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var path = diszig.rest.request.PathBuilder{ .writer = &writer };
    try path.segment("a/b");
    try std.testing.expectEqualStrings("/a%2Fb", path.done());

    var query_buffer: [128]u8 = undefined;
    var query_writer = std.Io.Writer.fixed(&query_buffer);
    var query = diszig.rest.request.QueryBuilder{ .writer = &query_writer };
    try query.addOptional("limit", null);
    try query.addOptional("before", "");
    try std.testing.expectEqualStrings("?before=", query.done());
}

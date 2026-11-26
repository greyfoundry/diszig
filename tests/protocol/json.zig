const std = @import("std");
const diszig = @import("diszig");

const Value = struct {
    x: diszig.json.Presence(i64) = .absent,
};

test "public presence distinguishes absent, null and zero" {
    var missing = try std.json.parseFromSlice(Value, std.testing.allocator, "{}", .{});
    defer missing.deinit();
    try std.testing.expect(missing.value.x.isAbsent());

    var explicit_null = try std.json.parseFromSlice(Value, std.testing.allocator, "{\"x\":null}", .{});
    defer explicit_null.deinit();
    try std.testing.expect(explicit_null.value.x.isNull());

    var zero = try std.json.parseFromSlice(Value, std.testing.allocator, "{\"x\":0}", .{});
    defer zero.deinit();
    try std.testing.expectEqual(@as(?i64, 0), zero.value.x.get());
}

test "unknown inbound fields decode only with the explicit option" {
    const bytes =
        \\{"x":7,"future":{"nested":true}}
    ;
    var parsed = try std.json.parseFromSlice(Value, std.testing.allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?i64, 7), parsed.value.x.get());
}

const ArrayValue = struct {
    values: []const i64,
};

fn decodeArray(allocator: std.mem.Allocator, bytes: []const u8) !void {
    var parsed = try std.json.parseFromSlice(ArrayValue, allocator, bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 3), parsed.value.values.len);
}

test "failed allocation mid-array releases the parse arena" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        decodeArray,
        .{"{\"values\":[1,2,3]}"},
    );
}

test "depth and size bounds fail explicitly" {
    try std.testing.expectError(error.NestingTooDeep, diszig.json.checkDepth("[[[0]]]", 2));
    try std.testing.expectError(
        error.InputTooLarge,
        diszig.json.parseBounded(Value, std.testing.allocator, "{\"x\":1}", 4, .{}),
    );
}

//! Components model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const components = diszig.protocol.models.components;

test "every listed schema is exported" {
    _ = components.ButtonStyleTypes;
    _ = components.CheckboxGroupOptionForRequest;
    _ = components.MessageComponentSeparatorSpacingSize;
    _ = components.MessageComponentTypes;
    _ = components.RadioGroupOptionForRequest;
    _ = components.SnowflakeSelectDefaultValueTypes;
    _ = components.TextInputStyleTypes;
    _ = components.UnfurledMediaRequest;
    _ = components.UnfurledMediaRequestWithAttachmentReferenceRequired;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(components.ButtonStyleTypes.primary));
    try std.testing.expectEqual(@as(u8, 5), @backingInt(components.ButtonStyleTypes.link));
    try std.testing.expectEqual(@as(u8, 6), @backingInt(components.ButtonStyleTypes.premium));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(components.MessageComponentSeparatorSpacingSize.small));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(components.MessageComponentTypes.action_row));
    try std.testing.expectEqual(@as(u8, 21), @backingInt(components.MessageComponentTypes.radio_group));
    try std.testing.expectEqual(@as(u8, 23), @backingInt(components.MessageComponentTypes.checkbox));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(components.TextInputStyleTypes.short));
    try std.testing.expectEqualStrings("user", @tagName(components.SnowflakeSelectDefaultValueTypes.user));
}

test "option and media validation" {
    try (components.CheckboxGroupOptionForRequest{
        .label = "label",
        .value = "value",
        .description = "desc",
        .default = true,
    }).validate();
    try std.testing.expectError(
        error.InvalidValue,
        (components.RadioGroupOptionForRequest{ .label = "l", .value = "" }).validate(),
    );
    const long_url: [2049]u8 = @splat('h');
    try std.testing.expectError(
        error.UrlTooLong,
        (components.UnfurledMediaRequest{ .url = &long_url }).validate(),
    );
    try (components.UnfurledMediaRequestWithAttachmentReferenceRequired{ .url = "attachment://file.png" }).validate();
    try std.testing.expectError(
        error.MissingAttachmentReference,
        (components.UnfurledMediaRequestWithAttachmentReferenceRequired{ .url = "attachment://" }).validate(),
    );
}

test "unknown inbound enums are retained" {
    var button = try std.json.parseFromSlice(components.InboundButtonStyleTypes, std.testing.allocator, "99", .{});
    defer button.deinit();
    try std.testing.expectEqual(@as(?components.ButtonStyleTypes, null), button.value.known());

    var select = try std.json.parseFromSlice(components.InboundSnowflakeSelectDefaultValueTypes, std.testing.allocator, "\"future\"", .{});
    defer select.deinit();
    try std.testing.expectEqual(@as(?components.SnowflakeSelectDefaultValueTypes, null), select.value.known());
}

fn parseOption(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value = try std.json.parseFromSliceLeaky(components.CheckboxGroupOptionForRequest, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
    try value.validate();
}

test "allocation failure while parsing option strings is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseOption,
        .{"{\"label\":\"label\",\"value\":\"value\",\"description\":\"desc\"}"},
    );
}

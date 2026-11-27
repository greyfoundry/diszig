//! Resources model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const resources = diszig.protocol.models.resources;

test "every listed schema is exported" {
    _ = resources.CreateGroupDMInviteRequest;
    _ = resources.InviteTargetTypes;
    _ = resources.InviteTypes;
    _ = resources.ScheduledEventUserCountResponse;
    _ = resources.StickerFormatTypes;
    _ = resources.StickerTypes;
    _ = resources.SettingsEmojiResponse;
    _ = resources.StandardStickerResponse;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(resources.InviteTargetTypes.stream));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(resources.InviteTargetTypes.embedded_application));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(resources.InviteTypes.guild));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(resources.InviteTypes.friend));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(resources.StickerFormatTypes.png));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(resources.StickerFormatTypes.lottie));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(resources.StickerTypes.standard));
}

test "group DM invite request validation" {
    try (resources.CreateGroupDMInviteRequest{ .max_age = 86_400 }).validate();
    try std.testing.expectError(
        error.InvalidMaxAge,
        (resources.CreateGroupDMInviteRequest{ .max_age = 2_592_001 }).validate(),
    );
}

test "scheduled event user count parses the exception map" {
    var parsed = try std.json.parseFromSlice(resources.ScheduledEventUserCountResponse, std.testing.allocator,
        \\{"guild_scheduled_event_count":12,"guild_scheduled_event_exception_counts":{"123":4,"456":8}}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(i32, 12), parsed.value.guild_scheduled_event_count);
    const counts = parsed.value.guild_scheduled_event_exception_counts.object;
    try std.testing.expectEqual(@as(usize, 2), counts.count());
    try std.testing.expectEqual(@as(i64, 4), counts.get("123").?.integer);
    try std.testing.expectEqual(@as(i64, 8), counts.get("456").?.integer);
}

test "scheduled event user count requires both fields" {
    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(resources.ScheduledEventUserCountResponse, std.testing.allocator,
            \\{"guild_scheduled_event_count":1}
        , .{}),
    );
}

test "unknown inbound resource enums are retained" {
    var target = try std.json.parseFromSlice(resources.InboundInviteTargetTypes, std.testing.allocator, "99", .{});
    defer target.deinit();
    try std.testing.expectEqual(@as(?resources.InviteTargetTypes, null), target.value.known());

    var sticker = try std.json.parseFromSlice(resources.InboundStickerTypes, std.testing.allocator, "99", .{});
    defer sticker.deinit();
    try std.testing.expectEqual(@as(?resources.StickerTypes, null), sticker.value.known());
}

fn parseCounts(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try std.json.parseFromSliceLeaky(resources.ScheduledEventUserCountResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
}

test "allocation failure while parsing the exception map is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseCounts,
        .{"{\"guild_scheduled_event_count\":1,\"guild_scheduled_event_exception_counts\":{\"1\":2}}"},
    );
}

test "settings emoji and standard sticker contracts" {
    var emoji = try std.json.parseFromSlice(resources.SettingsEmojiResponse, std.testing.allocator,
        \\{"id":"1","name":"wave","animated":true}
    , .{ .ignore_unknown_fields = true });
    defer emoji.deinit();
    try std.testing.expect(emoji.value.id != null);
    try std.testing.expect(emoji.value.animated);

    var sticker = try std.json.parseFromSlice(resources.StandardStickerResponse, std.testing.allocator,
        \\{"id":"1","name":"wave","tags":"wave","type":1,"format_type":2,"description":"d","pack_id":"2","sort_value":0}
    , .{ .ignore_unknown_fields = true });
    defer sticker.deinit();
    try sticker.value.validate();
    try std.testing.expectEqual(resources.StickerFormatTypes.apng, sticker.value.format_type.?);

    try std.testing.expectError(
        error.InvalidStickerType,
        (resources.StandardStickerResponse{
            .id = sticker.value.id,
            .name = "n",
            .tags = "t",
            .type = .guild,
            .format_type = null,
            .description = null,
            .pack_id = sticker.value.pack_id,
            .sort_value = 0,
        }).validate(),
    );
}

fn parseSticker(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value = try std.json.parseFromSliceLeaky(resources.StandardStickerResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
    try value.validate();
}

test "allocation failure while parsing a standard sticker is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseSticker,
        .{"{\"id\":\"1\",\"name\":\"wave\",\"tags\":\"wave\",\"type\":1,\"format_type\":1,\"description\":null,\"pack_id\":\"2\",\"sort_value\":0}"},
    );
}

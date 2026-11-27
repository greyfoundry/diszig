//! Messages model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const messages = diszig.protocol.models.messages;

test "every listed schema is exported" {
    _ = messages.AllowedMentionTypes;
    _ = messages.BlockMessageActionMetadata;
    _ = messages.BlockMessageActionMetadataResponse;
    _ = messages.EmbeddedActivityLocationKind;
    _ = messages.MessageEmbedAudioResponse;
    _ = messages.MessageEmbedAuthorResponse;
    _ = messages.MessageEmbedFieldResponse;
    _ = messages.MessageEmbedFooterResponse;
    _ = messages.MessageEmbedProviderResponse;
    _ = messages.MessageLobbyMemberResponse;
    _ = messages.MessageReactionCountDetailsResponse;
    _ = messages.MessageReferenceType;
    _ = messages.MessageShareCustomUserThemeBaseTheme;
    _ = messages.MessageType;
    _ = messages.PollLayoutTypes;
    _ = messages.PollResultsEntryResponse;
    _ = messages.ReactionTypes;
    _ = messages.RichEmbedAudio;
    _ = messages.RichEmbedAuthor;
    _ = messages.RichEmbedField;
    _ = messages.RichEmbedFooter;
    _ = messages.RichEmbedImage;
    _ = messages.RichEmbedProvider;
    _ = messages.RichEmbedThumbnail;
    _ = messages.RichEmbedVideo;
    _ = messages.SearchableEmbedType;
    _ = messages.WebhookSlackEmbedField;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 0), @backingInt(messages.MessageType.default));
    try std.testing.expectEqual(@as(u8, 19), @backingInt(messages.MessageType.reply));
    try std.testing.expectEqual(@as(u8, 55), @backingInt(messages.MessageType.hd_streaming_upgraded));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(messages.MessageReferenceType.default));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(messages.PollLayoutTypes.default));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(messages.ReactionTypes.burst));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(messages.MessageShareCustomUserThemeBaseTheme.light));
    try std.testing.expectEqualStrings("everyone", @tagName(messages.AllowedMentionTypes.everyone));
    try std.testing.expectEqualStrings("gc", @tagName(messages.EmbeddedActivityLocationKind.gc));
}

test "rich embed validation bounds" {
    try (messages.RichEmbedAudio{ .url = "https://x", .description = "d" }).validate();
    try (messages.RichEmbedAuthor{ .name = "n", .url = "https://x" }).validate();
    try (messages.RichEmbedFooter{ .text = "t", .icon_url = "https://x" }).validate();
    try (messages.RichEmbedProvider{ .name = "p", .url = "https://x" }).validate();
    try (messages.RichEmbedImage{ .url = "https://x", .placeholder_version = 1 }).validate();
    try (messages.RichEmbedThumbnail{ .url = "https://x" }).validate();

    const long_text: [4097]u8 = @splat('t');
    try std.testing.expectError(
        error.TextTooLong,
        (messages.RichEmbedAudio{ .description = &long_text }).validate(),
    );
    try std.testing.expectError(
        error.InvalidPlaceholderVersion,
        (messages.RichEmbedImage{ .placeholder_version = 2_147_483_648 }).validate(),
    );
}

test "embed responses parse" {
    var field = try std.json.parseFromSlice(messages.MessageEmbedFieldResponse, std.testing.allocator,
        \\{"name":"n","value":"v","inline":true}
    , .{ .ignore_unknown_fields = true });
    defer field.deinit();
    try std.testing.expect(field.value.@"inline");

    var author = try std.json.parseFromSlice(messages.MessageEmbedAuthorResponse, std.testing.allocator,
        \\{"name":"author","url":"https://x"}
    , .{ .ignore_unknown_fields = true });
    defer author.deinit();
    try std.testing.expectEqualStrings("author", author.value.name);

    var counts = try std.json.parseFromSlice(messages.MessageReactionCountDetailsResponse, std.testing.allocator,
        \\{"burst":1,"normal":2}
    , .{ .ignore_unknown_fields = true });
    defer counts.deinit();
    try std.testing.expectEqual(@as(i32, 1), counts.value.burst);
}

test "video embed, searchable type and slack field validate" {
    try (messages.RichEmbedVideo{
        .url = "https://x/v.mp4",
        .placeholder = "p",
        .placeholder_version = 2_147_483_647,
        .description = "d",
    }).validate();
    const long_placeholder: [65]u8 = @splat('p');
    try std.testing.expectError(
        error.PlaceholderTooLong,
        (messages.RichEmbedVideo{ .placeholder = &long_placeholder }).validate(),
    );

    try std.testing.expectEqual(messages.SearchableEmbedType.article, messages.SearchableEmbedType.parseWire("article").?);
    try std.testing.expectEqual(@as(?messages.SearchableEmbedType, null), messages.SearchableEmbedType.parseWire("Article"));

    try (messages.WebhookSlackEmbedField{ .name = "n", .value = "v", .@"inline" = false }).validate();
    try std.testing.expectEqual(@as(usize, 152_133), messages.WebhookSlackEmbedField.max_text_len);
}

test "unknown inbound message enum is retained" {
    var parsed = try std.json.parseFromSlice(messages.InboundMessageType, std.testing.allocator, "250", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?messages.MessageType, null), parsed.value.known());
    try std.testing.expectEqual(@as(i64, 250), parsed.value.raw.integer);
}

fn parseAuthor(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try std.json.parseFromSliceLeaky(messages.MessageEmbedAuthorResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
}

test "allocation failure while parsing embed author strings is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseAuthor,
        .{"{\"name\":\"author\",\"url\":\"https://x\",\"icon_url\":\"https://i\"}"},
    );
}

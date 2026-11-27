//! Message/embed/mention/attachment builder contracts.

const std = @import("std");
const diszig = @import("diszig");
const builders = diszig.builders;
const Snowflake = diszig.Snowflake;

fn serialize(allocator: std.mem.Allocator, message: builders.Message) ![]u8 {
    try message.validate();
    return message.toOwnedSlice(allocator);
}

test "combined embed character limit is rejected" {
    const first_description: [4096]u8 = @splat('a');
    const second_description: [2000]u8 = @splat('b');
    const message = builders.Message{
        .embeds = &.{
            .{ .description = &first_description },
            .{ .description = &second_description },
        },
    };
    try std.testing.expectError(error.TotalEmbedsTooLong, serialize(std.testing.allocator, message));
}

test "mention suppression is serialized exactly" {
    const role = try Snowflake.parse("42");
    const message = builders.Message{
        .content = .{ .value = "hi" },
        .allowed_mentions = .{
            .parse = .{},
            .roles = &.{role},
            .users = &.{},
            .replied_user = false,
        },
    };
    const json = try serialize(std.testing.allocator, message);
    defer std.testing.allocator.free(json);
    try std.testing.expectEqualStrings(
        "{\"content\":\"hi\",\"allowed_mentions\":{\"parse\":[],\"roles\":[\"42\"],\"users\":[],\"replied_user\":false}}",
        json,
    );
}

test "edit omits content while explicit null is preserved" {
    const omitted = try serialize(std.testing.allocator, .{});
    defer std.testing.allocator.free(omitted);
    try std.testing.expectEqualStrings("{}", omitted);

    const cleared = try serialize(std.testing.allocator, .{ .content = .null });
    defer std.testing.allocator.free(cleared);
    try std.testing.expectEqualStrings("{\"content\":null}", cleared);
}

test "attachment references must resolve" {
    const missing = builders.Message{
        .embeds = &.{.{ .thumbnail = .{ .url = "attachment://missing.png" } }},
    };
    try std.testing.expectError(
        error.UnknownAttachmentReference,
        serialize(std.testing.allocator, missing),
    );

    const present = builders.Message{
        .embeds = &.{.{ .thumbnail = .{ .url = "attachment://present.png" } }},
        .attachments = &.{.{ .filename = "present.png" }},
    };
    const json = try serialize(std.testing.allocator, present);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "attachment://present.png") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"filename\":\"present.png\"") != null);
}

test "retain and upload attachments are distinguished" {
    const id = try Snowflake.parse("7");
    const retained = builders.Message{
        .attachments = &.{.{ .id = id, .description = "keep" }},
    };
    const json = try serialize(std.testing.allocator, retained);
    defer std.testing.allocator.free(json);
    try std.testing.expect(std.mem.indexOf(u8, json, "\"id\":\"7\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, json, "filename") == null);

    try std.testing.expectError(
        error.MissingAttachmentFilename,
        serialize(std.testing.allocator, .{ .attachments = &.{.{}} }),
    );
    try std.testing.expectError(
        error.DuplicateAttachment,
        serialize(std.testing.allocator, .{
            .attachments = &.{ .{ .filename = "a.png" }, .{ .filename = "a.png" } },
        }),
    );
}

test "message JSON round-trips through a generic parser" {
    const channel = try Snowflake.parse("9");
    const message = builders.Message{
        .content = .{ .value = "hello" },
        .reply = .{ .message_id = try Snowflake.parse("1"), .channel_id = channel },
        .tts = true,
        .flags = builders.message.flags.suppress_embeds,
    };
    const json = try serialize(std.testing.allocator, message);
    defer std.testing.allocator.free(json);

    var parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hello", parsed.value.object.get("content").?.string);
    try std.testing.expectEqual(@as(i64, 4), parsed.value.object.get("flags").?.integer);
}

test "embed field limits and mention scanning" {
    var fields: [26]builders.embed.Field = undefined;
    for (&fields) |*field| field.* = .{ .name = "n", .value = "v" };
    try std.testing.expectError(
        error.TooManyFields,
        (builders.Embed{ .fields = &fields }).validate(),
    );

    const mentions = try builders.message.scanMentions(
        std.testing.allocator,
        "hi <@1> <@&2> <#3> @everyone",
    );
    defer std.testing.allocator.free(mentions);
    try std.testing.expectEqual(@as(usize, 3), mentions.len);
    try std.testing.expectEqual(@as(u64, 1), mentions[0].user.toU64());
    try std.testing.expectEqual(@as(u64, 2), mentions[1].role.toU64());
    try std.testing.expectEqual(@as(u64, 3), mentions[2].channel.toU64());
}

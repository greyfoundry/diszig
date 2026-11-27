//! Message wire models used by the message Gateway events (batch 1).
//!
//! `Message` is shared by MESSAGE_CREATE and the partial MESSAGE_UPDATE. Fields
//! that can be absent on an update use `Presence`; fields that are absent but
//! not nullable use optionals. Embeds, components, reactions and other
//! action-specific structures stay raw until their model batches land.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;
const shared = @import("shared.zig");
const channels = @import("channels.zig");

pub const MessageType = enum(u8) {
    default = 0,
    recipient_add = 1,
    recipient_remove = 2,
    call = 3,
    channel_name_change = 4,
    channel_icon_change = 5,
    channel_pinned_message = 6,
    user_join = 7,
    reply = 19,
    chat_input_command = 20,
    thread_starter_message = 21,
    guild_invite_reminder = 22,
    context_menu_command = 23,
    auto_moderation_action = 24,
    role_subscription_purchase = 25,
    interaction_premium_upsell = 26,
    stage_start = 27,
    stage_end = 28,
    stage_speaker = 29,
    stage_topic = 30,
    guild_application_premium_subscription = 31,
};

pub const Attachment = struct {
    id: Snowflake,
    filename: []const u8,
    description: json.Presence([]const u8) = .absent,
    content_type: json.Presence([]const u8) = .absent,
    size: i64,
    url: []const u8,
    proxy_url: []const u8,
    height: json.Presence(i64) = .absent,
    width: json.Presence(i64) = .absent,
    ephemeral: ?bool = null,
    duration_secs: ?f64 = null,
    waveform: json.Presence([]const u8) = .absent,
    flags: ?u64 = null,
};

pub const Message = struct {
    id: Snowflake,
    channel_id: ?Snowflake = null,
    guild_id: ?Snowflake = null,
    author: ?shared.User = null,
    content: json.Presence([]const u8) = .absent,
    timestamp: ?[]const u8 = null,
    edited_timestamp: json.Presence([]const u8) = .absent,
    tts: ?bool = null,
    mention_everyone: ?bool = null,
    mentions: ?[]shared.User = null,
    mention_roles: ?[]Snowflake = null,
    attachments: ?[]Attachment = null,
    embeds: ?[]std.json.Value = null,
    components: ?[]std.json.Value = null,
    reactions: ?[]std.json.Value = null,
    nonce: ?std.json.Value = null,
    pinned: ?bool = null,
    webhook_id: ?Snowflake = null,
    type: ?json.InboundEnum(MessageType) = null,
    flags: ?u64 = null,
    message_reference: ?std.json.Value = null,
    referenced_message: ?std.json.Value = null,
    thread: ?channels.Channel = null,
    sticker_items: ?[]std.json.Value = null,
    position: ?i64 = null,
    poll: ?std.json.Value = null,
    interaction: ?std.json.Value = null,
    interaction_metadata: ?std.json.Value = null,
    resolved: ?std.json.Value = null,
    role_subscription_data: ?std.json.Value = null,
};

pub const MessageDelete = struct {
    id: Snowflake,
    channel_id: Snowflake,
    guild_id: ?Snowflake = null,
};

pub const MessageDeleteBulk = struct {
    ids: []Snowflake,
    channel_id: Snowflake,
    guild_id: ?Snowflake = null,
};

test "message create keeps author, content and attachments" {
    var parsed = try std.json.parseFromSlice(Message, std.testing.allocator,
        \\{"id":"1","channel_id":"2","guild_id":"3","author":{"id":"4","username":"u"},"content":"hi","timestamp":"2024-01-01T00:00:00+00:00","type":0,"pinned":false,"attachments":[{"id":"5","filename":"a.txt","size":3,"url":"https://x","proxy_url":"https://p"}]}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("hi", parsed.value.content.get().?);
    try std.testing.expectEqual(@as(usize, 1), parsed.value.attachments.?.len);
    try std.testing.expectEqual(MessageType.default, parsed.value.type.?.known().?);
}

test "partial message update leaves content absent" {
    var parsed = try std.json.parseFromSlice(Message, std.testing.allocator,
        \\{"id":"1","channel_id":"2","edited_timestamp":"2024-01-02T00:00:00+00:00","pinned":true}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expect(parsed.value.content.isAbsent());
    try std.testing.expectEqualStrings("2024-01-02T00:00:00+00:00", parsed.value.edited_timestamp.get().?);
    try std.testing.expect(parsed.value.author == null);
}

test "unknown message type is retained" {
    var parsed = try std.json.parseFromSlice(Message, std.testing.allocator,
        \\{"id":"1","type":250}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?MessageType, null), parsed.value.type.?.known());
    try std.testing.expectEqual(@as(i64, 250), parsed.value.type.?.raw.integer);
}

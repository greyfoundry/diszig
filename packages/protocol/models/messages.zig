//! Messages wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

pub const Error = error{
    TextTooLong,
    UrlTooLong,
    PlaceholderTooLong,
    InvalidPlaceholderVersion,
};

pub const AllowedMentionTypes = enum {
    users,
    roles,
    everyone,
};

pub const InboundAllowedMentionTypes = json.InboundStringEnum(AllowedMentionTypes);

pub const BlockMessageActionMetadata = struct {
    custom_message: ?[]const u8 = null,

    pub fn validate(self: BlockMessageActionMetadata) Error!void {
        if (self.custom_message) |value| {
            if (value.len > 300) return error.TextTooLong;
        }
    }
};

pub const BlockMessageActionMetadataResponse = struct {
    custom_message: ?[]const u8 = null,
};

pub const EmbeddedActivityLocationKind = enum {
    gc,
    pc,
    party,
};

pub const InboundEmbeddedActivityLocationKind = json.InboundStringEnum(EmbeddedActivityLocationKind);

pub const MessageEmbedAudioResponse = struct {
    url: ?[]const u8 = null,
    proxy_url: ?[]const u8 = null,
    content_type: ?[]const u8 = null,
    description: ?[]const u8 = null,
};

pub const MessageEmbedAuthorResponse = struct {
    name: []const u8,
    url: ?[]const u8 = null,
    icon_url: ?[]const u8 = null,
    proxy_icon_url: ?[]const u8 = null,
};

pub const MessageEmbedFieldResponse = struct {
    name: []const u8,
    value: []const u8,
    @"inline": bool,
};

pub const MessageEmbedFooterResponse = struct {
    text: []const u8,
    icon_url: ?[]const u8 = null,
    proxy_icon_url: ?[]const u8 = null,
};

pub const MessageEmbedProviderResponse = struct {
    name: []const u8,
    url: ?[]const u8 = null,
};

pub const MessageLobbyMemberResponse = struct {
    additional_name: []const u8,
};

pub const MessageReactionCountDetailsResponse = struct {
    burst: i32,
    normal: i32,
};

pub const MessageReferenceType = enum(u8) {
    default = 0,
};

pub const InboundMessageReferenceType = json.InboundEnum(MessageReferenceType);

pub const MessageShareCustomUserThemeBaseTheme = enum(u8) {
    unset = 0,
    dark = 1,
    light = 2,
    darker = 3,
    midnight = 4,
};

pub const InboundMessageShareCustomUserThemeBaseTheme = json.InboundEnum(MessageShareCustomUserThemeBaseTheme);

pub const MessageType = enum(u8) {
    default = 0,
    recipient_add = 1,
    recipient_remove = 2,
    call = 3,
    channel_name_change = 4,
    channel_icon_change = 5,
    channel_pinned_message = 6,
    user_join = 7,
    guild_boost = 8,
    guild_boost_tier_1 = 9,
    guild_boost_tier_2 = 10,
    guild_boost_tier_3 = 11,
    channel_follow_add = 12,
    guild_discovery_disqualified = 14,
    guild_discovery_requalified = 15,
    guild_discovery_grace_period_initial_warning = 16,
    guild_discovery_grace_period_final_warning = 17,
    thread_created = 18,
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
    stage_topic = 31,
    guild_application_premium_subscription = 32,
    guild_incident_alert_mode_enabled = 36,
    guild_incident_alert_mode_disabled = 37,
    guild_incident_report_raid = 38,
    guild_incident_report_false_alarm = 39,
    poll_result = 46,
    hd_streaming_upgraded = 55,
};

pub const InboundMessageType = json.InboundEnum(MessageType);

pub const PollLayoutTypes = enum(u8) {
    default = 1,
};

pub const InboundPollLayoutTypes = json.InboundEnum(PollLayoutTypes);

pub const PollResultsEntryResponse = struct {
    id: i32,
    count: i32,
    me_voted: bool,
};

pub const ReactionTypes = enum(u8) {
    normal = 0,
    burst = 1,
};

pub const InboundReactionTypes = json.InboundEnum(ReactionTypes);

pub const RichEmbedAudio = struct {
    url: ?[]const u8 = null,
    description: ?[]const u8 = null,

    pub fn validate(self: RichEmbedAudio) Error!void {
        try optionalText(self.url, 2048, error.UrlTooLong);
        try optionalText(self.description, 4096, error.TextTooLong);
    }
};

pub const RichEmbedAuthor = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,
    icon_url: ?[]const u8 = null,

    pub fn validate(self: RichEmbedAuthor) Error!void {
        try optionalText(self.name, 256, error.TextTooLong);
        try optionalText(self.url, 2048, error.UrlTooLong);
        try optionalText(self.icon_url, 2048, error.UrlTooLong);
    }
};

pub const RichEmbedField = struct {
    name: []const u8,
    value: []const u8,
    @"inline": ?bool = null,

    pub fn validate(self: RichEmbedField) Error!void {
        if (self.name.len > 256) return error.TextTooLong;
        if (self.value.len > 1024) return error.TextTooLong;
    }
};

pub const RichEmbedFooter = struct {
    text: ?[]const u8 = null,
    icon_url: ?[]const u8 = null,

    pub fn validate(self: RichEmbedFooter) Error!void {
        try optionalText(self.text, 2048, error.TextTooLong);
        try optionalText(self.icon_url, 2048, error.UrlTooLong);
    }
};

pub const RichEmbedImage = struct {
    url: ?[]const u8 = null,
    width: ?i64 = null,
    height: ?i64 = null,
    placeholder: ?[]const u8 = null,
    placeholder_version: ?i64 = null,
    is_animated: ?bool = null,
    description: ?[]const u8 = null,

    pub fn validate(self: RichEmbedImage) Error!void {
        try validateImage(self.url, self.placeholder, self.placeholder_version, self.description);
    }
};

pub const RichEmbedProvider = struct {
    name: ?[]const u8 = null,
    url: ?[]const u8 = null,

    pub fn validate(self: RichEmbedProvider) Error!void {
        try optionalText(self.name, 256, error.TextTooLong);
        try optionalText(self.url, 2048, error.UrlTooLong);
    }
};

pub const RichEmbedThumbnail = struct {
    url: ?[]const u8 = null,
    width: ?i64 = null,
    height: ?i64 = null,
    placeholder: ?[]const u8 = null,
    placeholder_version: ?i64 = null,
    is_animated: ?bool = null,
    description: ?[]const u8 = null,

    pub fn validate(self: RichEmbedThumbnail) Error!void {
        try validateImage(self.url, self.placeholder, self.placeholder_version, self.description);
    }
};

fn validateImage(
    url: ?[]const u8,
    placeholder: ?[]const u8,
    placeholder_version: ?i64,
    description: ?[]const u8,
) Error!void {
    try optionalText(url, 2048, error.UrlTooLong);
    try optionalText(placeholder, 64, error.PlaceholderTooLong);
    try optionalText(description, 4096, error.TextTooLong);
    if (placeholder_version) |value| {
        if (value < 0 or value > 2_147_483_647) return error.InvalidPlaceholderVersion;
    }
}

fn optionalText(value: ?[]const u8, limit: usize, comptime err: Error) Error!void {
    if (value) |text| {
        if (text.len > limit) return err;
    }
}

test "message enums" {
    try std.testing.expectEqual(@as(u8, 55), @backingInt(MessageType.hd_streaming_upgraded));
    try std.testing.expectEqual(@as(u8, 46), @backingInt(MessageType.poll_result));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(PollLayoutTypes.default));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(ReactionTypes.burst));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(MessageShareCustomUserThemeBaseTheme.midnight));
    try std.testing.expectEqualStrings("party", @tagName(EmbeddedActivityLocationKind.party));
    try std.testing.expectEqualStrings("roles", @tagName(AllowedMentionTypes.roles));
}

test "rich embed field and image validation" {
    try (RichEmbedField{ .name = "n", .value = "v" }).validate();
    const long_name: [257]u8 = @splat('x');
    try std.testing.expectError(
        error.TextTooLong,
        (RichEmbedField{ .name = &long_name, .value = "v" }).validate(),
    );
    try std.testing.expectError(
        error.InvalidPlaceholderVersion,
        (RichEmbedImage{ .placeholder_version = -1 }).validate(),
    );
    const long_placeholder: [65]u8 = @splat('p');
    try std.testing.expectError(
        error.PlaceholderTooLong,
        (RichEmbedThumbnail{ .placeholder = &long_placeholder }).validate(),
    );
}

test "unknown inbound message enums are retained" {
    var parsed = try std.json.parseFromSlice(InboundMessageType, std.testing.allocator, "250", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?MessageType, null), parsed.value.known());
}

//! Components wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

pub const Error = error{
    InvalidLabel,
    InvalidValue,
    DescriptionTooLong,
    UrlTooLong,
    MissingAttachmentReference,
};

pub const ButtonStyleTypes = enum(u8) {
    primary = 1,
    secondary = 2,
    success = 3,
    danger = 4,
    link = 5,
    premium = 6,
};

pub const InboundButtonStyleTypes = json.InboundEnum(ButtonStyleTypes);

pub const MessageComponentSeparatorSpacingSize = enum(u8) {
    small = 1,
    large = 2,
};

pub const InboundMessageComponentSeparatorSpacingSize = json.InboundEnum(MessageComponentSeparatorSpacingSize);

pub const MessageComponentTypes = enum(u8) {
    action_row = 1,
    button = 2,
    string_select = 3,
    text_input = 4,
    user_select = 5,
    role_select = 6,
    mentionable_select = 7,
    channel_select = 8,
    section = 9,
    text_display = 10,
    thumbnail = 11,
    media_gallery = 12,
    file = 13,
    separator = 14,
    container = 17,
    label = 18,
    file_upload = 19,
    radio_group = 21,
    checkbox_group = 22,
    checkbox = 23,
};

pub const InboundMessageComponentTypes = json.InboundEnum(MessageComponentTypes);

pub const SnowflakeSelectDefaultValueTypes = enum {
    user,
    role,
    channel,
};

pub const InboundSnowflakeSelectDefaultValueTypes = json.InboundStringEnum(SnowflakeSelectDefaultValueTypes);

pub const TextInputStyleTypes = enum(u8) {
    short = 1,
    paragraph = 2,
};

pub const InboundTextInputStyleTypes = json.InboundEnum(TextInputStyleTypes);

pub const CheckboxGroupOptionForRequest = struct {
    label: []const u8,
    value: []const u8,
    description: ?[]const u8 = null,
    default: ?bool = null,

    pub fn validate(self: CheckboxGroupOptionForRequest) Error!void {
        try validateOption(self.label, self.value, self.description);
    }
};

pub const RadioGroupOptionForRequest = struct {
    label: []const u8,
    value: []const u8,
    description: ?[]const u8 = null,
    default: ?bool = null,

    pub fn validate(self: RadioGroupOptionForRequest) Error!void {
        try validateOption(self.label, self.value, self.description);
    }
};

pub const UnfurledMediaRequest = struct {
    url: []const u8,

    pub fn validate(self: UnfurledMediaRequest) Error!void {
        if (self.url.len > 2048) return error.UrlTooLong;
    }
};

/// The schema name requires an attachment reference; the wire shape is the same
/// as UnfurledMediaRequest.
pub const UnfurledMediaRequestWithAttachmentReferenceRequired = struct {
    url: []const u8,

    pub fn validate(self: UnfurledMediaRequestWithAttachmentReferenceRequired) Error!void {
        const prefix = "attachment://";
        if (!std.mem.startsWith(u8, self.url, prefix)) return error.MissingAttachmentReference;
        if (self.url.len == prefix.len) return error.MissingAttachmentReference;
        if (self.url.len > 2048) return error.UrlTooLong;
    }
};

fn validateOption(label: []const u8, value: []const u8, description: ?[]const u8) Error!void {
    if (label.len == 0 or label.len > 100) return error.InvalidLabel;
    if (value.len == 0 or value.len > 100) return error.InvalidValue;
    if (description) |text| {
        if (text.len > 100) return error.DescriptionTooLong;
    }
}

test "component enum values" {
    try std.testing.expectEqual(@as(u8, 6), @backingInt(ButtonStyleTypes.premium));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(MessageComponentSeparatorSpacingSize.large));
    try std.testing.expectEqual(@as(u8, 23), @backingInt(MessageComponentTypes.checkbox));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(TextInputStyleTypes.paragraph));
    try std.testing.expectEqualStrings("channel", @tagName(SnowflakeSelectDefaultValueTypes.channel));
}

test "component request validation" {
    try (CheckboxGroupOptionForRequest{ .label = "l", .value = "v" }).validate();
    try std.testing.expectError(
        error.InvalidLabel,
        (CheckboxGroupOptionForRequest{ .label = "", .value = "v" }).validate(),
    );
    const long_description: [101]u8 = @splat('x');
    try std.testing.expectError(
        error.DescriptionTooLong,
        (RadioGroupOptionForRequest{
            .label = "l",
            .value = "v",
            .description = &long_description,
        }).validate(),
    );
}

test "unfurled media requires an attachment reference when specified" {
    try (UnfurledMediaRequest{ .url = "https://example.com/a.png" }).validate();
    try std.testing.expectError(
        error.MissingAttachmentReference,
        (UnfurledMediaRequestWithAttachmentReferenceRequired{ .url = "https://example.com/a.png" }).validate(),
    );
    try (UnfurledMediaRequestWithAttachmentReferenceRequired{ .url = "attachment://a.png" }).validate();
}

test "unknown inbound component enum is retained" {
    var parsed = try std.json.parseFromSlice(InboundMessageComponentTypes, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?MessageComponentTypes, null), parsed.value.known());
}

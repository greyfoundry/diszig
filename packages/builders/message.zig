//! Message, mention and attachment builder with documented limits.
//!
//! The caller chooses `allowed_mentions` explicitly: leaving it null omits the
//! field (Discord's default parsing), while setting it always serializes an
//! explicit `parse` array (an empty array suppresses all parses).
//!
//! `content` uses `Presence`: `.absent` omits it (edit leaves content alone),
//! `.null` serializes `null`, and `.value` sets text. Attachments with an
//! upload filename are matched against `attachment://` embed references.

const std = @import("std");
const protocol = @import("protocol");
const embed = @import("embed.zig");

const Snowflake = protocol.Snowflake;
const Presence = protocol.presence.Presence;

pub const flags = struct {
    pub const suppress_embeds: u64 = 1 << 2;
    pub const ephemeral: u64 = 1 << 6;
    pub const suppress_notifications: u64 = 1 << 12;
};

pub const Error = embed.Error || error{
    ContentTooLong,
    TooManyEmbeds,
    TotalEmbedsTooLong,
    TooManyAttachments,
    MissingAttachmentFilename,
    DuplicateAttachment,
    UnknownAttachmentReference,
    InvalidMention,
    TooManyMentions,
};

pub const Mention = union(enum) {
    user: Snowflake,
    role: Snowflake,
    channel: Snowflake,
    everyone,
    here,
};

pub const Attachment = struct {
    /// Existing attachment ID for retain-on-edit, or null for an upload.
    id: ?Snowflake = null,
    /// Upload filename; may be empty when retaining an existing attachment.
    filename: []const u8 = "",
    description: ?[]const u8 = null,
};

pub const Reply = struct {
    message_id: Snowflake,
    channel_id: ?Snowflake = null,
    fail_if_not_exists: bool = false,
};

pub const Parse = struct {
    everyone: bool = false,
    users: bool = false,
    roles: bool = false,
};

pub const AllowedMentions = struct {
    /// Empty means "do not parse anything"; omit `allowed_mentions` entirely
    /// for Discord's default parsing.
    parse: Parse = .{},
    roles: []const Snowflake = &.{},
    users: []const Snowflake = &.{},
    replied_user: ?bool = null,

    pub fn writeJson(self: AllowedMentions, writer: anytype, first_message: *bool) !void {
        try key(writer, first_message, "allowed_mentions");
        try writer.writeByte('{');
        var first = true;

        try key(writer, &first, "parse");
        try writer.writeByte('[');
        var parse_first = true;
        if (self.parse.roles) {
            if (!parse_first) try writer.writeByte(',');
            parse_first = false;
            try writer.writeAll("\"roles\"");
        }
        if (self.parse.users) {
            if (!parse_first) try writer.writeByte(',');
            parse_first = false;
            try writer.writeAll("\"users\"");
        }
        if (self.parse.everyone) {
            if (!parse_first) try writer.writeByte(',');
            try writer.writeAll("\"everyone\"");
        }
        try writer.writeByte(']');

        try key(writer, &first, "roles");
        try writeIds(writer, self.roles);
        try key(writer, &first, "users");
        try writeIds(writer, self.users);
        if (self.replied_user) |value| {
            try key(writer, &first, "replied_user");
            try writer.writeAll(if (value) "true" else "false");
        }
        try writer.writeByte('}');
    }

    fn writeIds(writer: anytype, ids: []const Snowflake) !void {
        try writer.writeByte('[');
        for (ids, 0..) |id, index| {
            if (index > 0) try writer.writeByte(',');
            try writer.print("\"{d}\"", .{id.toU64()});
        }
        try writer.writeByte(']');
    }
};

pub const Message = struct {
    content: Presence([]const u8) = .absent,
    embeds: []const embed.Embed = &.{},
    allowed_mentions: ?AllowedMentions = null,
    attachments: []const Attachment = &.{},
    reply: ?Reply = null,
    tts: ?bool = null,
    flags: ?u64 = null,

    pub fn validate(self: Message) Error!void {
        if (self.content.get()) |content| {
            if (content.len > 2000) return error.ContentTooLong;
        }
        if (self.embeds.len > 10) return error.TooManyEmbeds;
        var total: usize = 0;
        for (self.embeds) |value| {
            try value.validate();
            total += value.totalChars();
        }
        if (total > 6000) return error.TotalEmbedsTooLong;

        if (self.attachments.len > 10) return error.TooManyAttachments;
        for (self.attachments, 0..) |attachment, index| {
            if (attachment.filename.len == 0 and attachment.id == null) {
                return error.MissingAttachmentFilename;
            }
            if (attachment.filename.len > 0) {
                for (self.attachments[0..index]) |earlier| {
                    if (earlier.filename.len > 0 and
                        std.mem.eql(u8, earlier.filename, attachment.filename))
                    {
                        return error.DuplicateAttachment;
                    }
                }
            }
        }

        for (self.embeds) |value| {
            if (value.image) |image| try checkAttachmentRef(image.url, self.attachments);
            if (value.thumbnail) |image| try checkAttachmentRef(image.url, self.attachments);
            if (value.author) |author| {
                if (author.icon_url) |url| try checkAttachmentRef(url, self.attachments);
            }
            if (value.footer) |footer| {
                if (footer.icon_url) |url| try checkAttachmentRef(url, self.attachments);
            }
        }
    }

    pub fn writeJson(self: Message, writer: anytype) !void {
        try writer.writeByte('{');
        var first = true;
        switch (self.content) {
            .absent => {},
            .null => {
                try key(writer, &first, "content");
                try writer.writeAll("null");
            },
            .value => |value| {
                try key(writer, &first, "content");
                try std.json.Stringify.value(value, .{}, writer);
            },
        }
        if (self.embeds.len > 0) {
            try key(writer, &first, "embeds");
            try writer.writeByte('[');
            for (self.embeds, 0..) |value, index| {
                if (index > 0) try writer.writeByte(',');
                try value.writeJson(writer);
            }
            try writer.writeByte(']');
        }
        if (self.allowed_mentions) |allowed| try allowed.writeJson(writer, &first);
        if (self.attachments.len > 0) {
            try key(writer, &first, "attachments");
            try writer.writeByte('[');
            for (self.attachments, 0..) |attachment, index| {
                if (index > 0) try writer.writeByte(',');
                try writer.writeByte('{');
                var attachment_first = true;
                if (attachment.id) |id| {
                    try key(writer, &attachment_first, "id");
                    try writer.print("\"{d}\"", .{id.toU64()});
                }
                if (attachment.filename.len > 0) {
                    try key(writer, &attachment_first, "filename");
                    try std.json.Stringify.value(attachment.filename, .{}, writer);
                }
                if (attachment.description) |description| {
                    try key(writer, &attachment_first, "description");
                    try std.json.Stringify.value(description, .{}, writer);
                }
                try writer.writeByte('}');
            }
            try writer.writeByte(']');
        }
        if (self.reply) |reply| {
            try key(writer, &first, "message_reference");
            try writer.writeByte('{');
            var reply_first = true;
            try key(writer, &reply_first, "message_id");
            try writer.print("\"{d}\"", .{reply.message_id.toU64()});
            if (reply.channel_id) |channel_id| {
                try key(writer, &reply_first, "channel_id");
                try writer.print("\"{d}\"", .{channel_id.toU64()});
            }
            try key(writer, &reply_first, "fail_if_not_exists");
            try writer.writeAll(if (reply.fail_if_not_exists) "true" else "false");
            try writer.writeByte('}');
        }
        if (self.tts) |tts| {
            try key(writer, &first, "tts");
            try writer.writeAll(if (tts) "true" else "false");
        }
        if (self.flags) |value| {
            try key(writer, &first, "flags");
            try writer.print("{d}", .{value});
        }
        try writer.writeByte('}');
    }

    pub fn toOwnedSlice(self: Message, allocator: std.mem.Allocator) ![]u8 {
        var allocating = std.Io.Writer.Allocating.init(allocator);
        defer allocating.deinit();
        try self.writeJson(&allocating.writer);
        return allocating.toOwnedSlice();
    }
};

fn checkAttachmentRef(url: []const u8, attachments: []const Attachment) Error!void {
    const prefix = "attachment://";
    if (!std.mem.startsWith(u8, url, prefix)) return;
    const name = url[prefix.len..];
    for (attachments) |attachment| {
        if (attachment.filename.len > 0 and std.mem.eql(u8, attachment.filename, name)) return;
    }
    return error.UnknownAttachmentReference;
}

fn key(writer: anytype, first: *bool, name: []const u8) !void {
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try writer.writeByte('"');
    try writer.writeAll(name);
    try writer.writeAll("\":");
}

pub fn parseMention(text: []const u8) Error!Mention {
    if (std.mem.eql(u8, text, "@everyone")) return .everyone;
    if (std.mem.eql(u8, text, "@here")) return .here;
    if (text.len < 4 or text[0] != '<' or text[text.len - 1] != '>') return error.InvalidMention;

    const inner = text[1 .. text.len - 1];
    if (inner.len >= 2 and inner[0] == '#') {
        return .{ .channel = Snowflake.parse(inner[1..]) catch return error.InvalidMention };
    }
    if (inner.len >= 2 and inner[0] == '@') {
        var rest = inner[1..];
        if (rest.len > 0 and rest[0] == '&') {
            return .{ .role = Snowflake.parse(rest[1..]) catch return error.InvalidMention };
        }
        if (rest.len > 0 and rest[0] == '!') rest = rest[1..];
        return .{ .user = Snowflake.parse(rest) catch return error.InvalidMention };
    }
    return error.InvalidMention;
}

pub fn scanMentions(allocator: std.mem.Allocator, content: []const u8) ![]Mention {
    var list: std.ArrayList(Mention) = .empty;
    errdefer list.deinit(allocator);
    var index: usize = 0;
    while (index < content.len) {
        if (content[index] == '<') {
            const end = std.mem.indexOfScalarPos(u8, content, index, '>') orelse
                return error.InvalidMention;
            if (list.items.len >= 100) return error.TooManyMentions;
            try list.append(allocator, try parseMention(content[index .. end + 1]));
            index = end + 1;
        } else {
            index += 1;
        }
    }
    return list.toOwnedSlice(allocator);
}

pub fn writeMention(mention: Mention, writer: anytype) !void {
    switch (mention) {
        .user => |id| try writer.print("<@{d}>", .{id.toU64()}),
        .role => |id| try writer.print("<@&{d}>", .{id.toU64()}),
        .channel => |id| try writer.print("<#{d}>", .{id.toU64()}),
        .everyone => try writer.writeAll("@everyone"),
        .here => try writer.writeAll("@here"),
    }
}

test "message serializes explicit allowed mentions and partial content" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const message = Message{
        .content = .{ .value = "hello" },
        .allowed_mentions = .{
            .parse = .{},
            .roles = &.{try Snowflake.parse("1")},
            .replied_user = false,
        },
    };
    try message.validate();
    try message.writeJson(&writer);
    try std.testing.expectEqualStrings(
        "{\"content\":\"hello\",\"allowed_mentions\":{\"parse\":[],\"roles\":[\"1\"],\"users\":[],\"replied_user\":false}}",
        writer.buffered(),
    );
}

test "absent content is omitted and null is explicit" {
    var buffer: [256]u8 = undefined;

    var writer = std.Io.Writer.fixed(&buffer);
    try (Message{}).writeJson(&writer);
    try std.testing.expectEqualStrings("{}", writer.buffered());

    writer = std.Io.Writer.fixed(&buffer);
    try (Message{ .content = .null }).writeJson(&writer);
    try std.testing.expectEqualStrings("{\"content\":null}", writer.buffered());
}

test "missing attachment reference is rejected" {
    const message = Message{
        .embeds = &.{.{
            .image = .{ .url = "attachment://missing.png" },
        }},
    };
    try std.testing.expectError(error.UnknownAttachmentReference, message.validate());
}

test "mention parsing and serialization" {
    const user = try parseMention("<@123>");
    try std.testing.expectEqual(@as(u64, 123), user.user.toU64());
    const role = try parseMention("<@&456>");
    try std.testing.expectEqual(@as(u64, 456), role.role.toU64());
    const channel = try parseMention("<#789>");
    try std.testing.expectEqual(@as(u64, 789), channel.channel.toU64());
    try std.testing.expect((try parseMention("@everyone")) == .everyone);
    try std.testing.expectError(error.InvalidMention, parseMention("<@notanid>"));

    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeMention(role, &writer);
    try std.testing.expectEqualStrings("<@&456>", writer.buffered());
}

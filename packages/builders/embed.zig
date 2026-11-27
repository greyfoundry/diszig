//! Embed builder with the documented field and aggregate limits.
//!
//! Serialization omits absent optional fields and preserves explicit values.
//! The caller owns all strings; the builder never allocates.

const std = @import("std");
const protocol = @import("protocol");

pub const Error = error{
    TitleTooLong,
    DescriptionTooLong,
    TooManyFields,
    FieldNameTooLong,
    FieldValueTooLong,
    EmptyFieldName,
    EmptyFieldValue,
    FooterTooLong,
    AuthorNameTooLong,
    TotalTooLong,
    InvalidTimestamp,
    InvalidColor,
};

pub const Field = struct {
    name: []const u8,
    value: []const u8,
    is_inline: bool = false,
};

pub const Footer = struct {
    text: []const u8,
    icon_url: ?[]const u8 = null,
};

pub const Image = struct {
    url: []const u8,
};

pub const Author = struct {
    name: []const u8,
    url: ?[]const u8 = null,
    icon_url: ?[]const u8 = null,
};

pub const Embed = struct {
    title: ?[]const u8 = null,
    description: ?[]const u8 = null,
    url: ?[]const u8 = null,
    timestamp: ?[]const u8 = null,
    color: ?u24 = null,
    footer: ?Footer = null,
    image: ?Image = null,
    thumbnail: ?Image = null,
    author: ?Author = null,
    fields: []const Field = &.{},

    pub fn totalChars(self: Embed) usize {
        var total: usize = 0;
        if (self.title) |value| total += value.len;
        if (self.description) |value| total += value.len;
        if (self.footer) |footer| total += footer.text.len;
        if (self.author) |author| total += author.name.len;
        for (self.fields) |field| total += field.name.len + field.value.len;
        return total;
    }

    pub fn validate(self: Embed) Error!void {
        if (self.title) |value| {
            if (value.len > 256) return error.TitleTooLong;
        }
        if (self.description) |value| {
            if (value.len > 4096) return error.DescriptionTooLong;
        }
        if (self.fields.len > 25) return error.TooManyFields;
        for (self.fields) |field| {
            if (field.name.len == 0) return error.EmptyFieldName;
            if (field.value.len == 0) return error.EmptyFieldValue;
            if (field.name.len > 256) return error.FieldNameTooLong;
            if (field.value.len > 1024) return error.FieldValueTooLong;
        }
        if (self.footer) |footer| {
            if (footer.text.len > 2048) return error.FooterTooLong;
        }
        if (self.author) |author| {
            if (author.name.len > 256) return error.AuthorNameTooLong;
        }
        if (self.timestamp) |value| {
            _ = protocol.Timestamp.parse(value) catch return error.InvalidTimestamp;
        }
        if (self.totalChars() > 6000) return error.TotalTooLong;
    }

    pub fn writeJson(self: Embed, writer: anytype) !void {
        try writer.writeByte('{');
        var first = true;
        if (self.title) |value| {
            try key(writer, &first, "title");
            try std.json.Stringify.value(value, .{}, writer);
        }
        if (self.description) |value| {
            try key(writer, &first, "description");
            try std.json.Stringify.value(value, .{}, writer);
        }
        if (self.url) |value| {
            try key(writer, &first, "url");
            try std.json.Stringify.value(value, .{}, writer);
        }
        if (self.timestamp) |value| {
            try key(writer, &first, "timestamp");
            try std.json.Stringify.value(value, .{}, writer);
        }
        if (self.color) |value| {
            try key(writer, &first, "color");
            try writer.print("{d}", .{value});
        }
        if (self.footer) |footer| {
            try key(writer, &first, "footer");
            try writer.writeByte('{');
            try key(writer, &first, "text");
            try std.json.Stringify.value(footer.text, .{}, writer);
            if (footer.icon_url) |value| {
                try key(writer, &first, "icon_url");
                try std.json.Stringify.value(value, .{}, writer);
            }
            try writer.writeByte('}');
        }
        if (self.image) |image| {
            try key(writer, &first, "image");
            try imageJson(image, writer);
        }
        if (self.thumbnail) |image| {
            try key(writer, &first, "thumbnail");
            try imageJson(image, writer);
        }
        if (self.author) |author| {
            try key(writer, &first, "author");
            try writer.writeByte('{');
            try key(writer, &first, "name");
            try std.json.Stringify.value(author.name, .{}, writer);
            if (author.url) |value| {
                try key(writer, &first, "url");
                try std.json.Stringify.value(value, .{}, writer);
            }
            if (author.icon_url) |value| {
                try key(writer, &first, "icon_url");
                try std.json.Stringify.value(value, .{}, writer);
            }
            try writer.writeByte('}');
        }
        if (self.fields.len > 0) {
            try key(writer, &first, "fields");
            try writer.writeByte('[');
            for (self.fields, 0..) |field, index| {
                if (index > 0) try writer.writeByte(',');
                try writer.writeByte('{');
                var field_first = true;
                try key(writer, &field_first, "name");
                try std.json.Stringify.value(field.name, .{}, writer);
                try key(writer, &field_first, "value");
                try std.json.Stringify.value(field.value, .{}, writer);
                if (field.is_inline) {
                    try key(writer, &field_first, "inline");
                    try writer.writeAll("true");
                }
                try writer.writeByte('}');
            }
            try writer.writeByte(']');
        }
        try writer.writeByte('}');
    }

    fn imageJson(image: Image, writer: anytype) !void {
        try writer.writeByte('{');
        var first = true;
        try key(writer, &first, "url");
        try std.json.Stringify.value(image.url, .{}, writer);
        try writer.writeByte('}');
    }
};

fn key(writer: anytype, first: *bool, name: []const u8) !void {
    if (!first.*) try writer.writeByte(',');
    first.* = false;
    try writer.writeByte('"');
    try writer.writeAll(name);
    try writer.writeAll("\":");
}

test "embed limits and serialization" {
    var buffer: [1024]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const value = Embed{
        .title = "Title",
        .description = "Description",
        .color = 0x00ff00,
        .fields = &.{.{ .name = "n", .value = "v", .is_inline = true }},
        .footer = .{ .text = "f" },
    };
    try value.validate();
    try value.writeJson(&writer);
    try std.testing.expectEqualStrings(
        "{\"title\":\"Title\",\"description\":\"Description\",\"color\":65280,\"footer\":{\"text\":\"f\"},\"fields\":[{\"name\":\"n\",\"value\":\"v\",\"inline\":true}]}",
        writer.buffered(),
    );
}

test "aggregate limit is rejected" {
    const big_description: [4096]u8 = @splat('x');
    const big_value: [1024]u8 = @splat('y');
    const big_value2: [1024]u8 = @splat('z');
    const value = Embed{
        .description = &big_description,
        .fields = &.{
            .{ .name = "a", .value = &big_value },
            .{ .name = "b", .value = &big_value2 },
        },
    };
    try std.testing.expectError(error.TotalTooLong, value.validate());
}

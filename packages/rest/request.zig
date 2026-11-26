//! Bounded request-target construction with correct percent encoding.
//!
//! Path segments are encoded from raw values. A caller that already has an
//! encoded path can use `writeRawPath`, which validates percent escapes and
//! does not double-encode them.

const std = @import("std");

pub const EncodeError = error{
    PathTooLong,
    InvalidRawPath,
    WriteFailed,
};

fn isUnreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~';
}

pub fn encodeSegment(writer: *std.Io.Writer, value: []const u8) EncodeError!void {
    const hex = "0123456789ABCDEF";
    for (value) |c| {
        if (isUnreserved(c)) {
            writer.writeByte(c) catch return error.WriteFailed;
        } else {
            var bytes = [_]u8{ '%', hex[c >> 4], hex[c & 0x0f] };
            writer.writeAll(&bytes) catch return error.WriteFailed;
        }
    }
}

pub fn encodeQueryValue(writer: *std.Io.Writer, value: []const u8) EncodeError!void {
    return encodeSegment(writer, value);
}

/// Validates a pre-encoded path and copies it without re-encoding.
pub fn writeRawPath(writer: *std.Io.Writer, path: []const u8) EncodeError!void {
    if (path.len == 0 or path[0] != '/') return error.InvalidRawPath;
    var index: usize = 0;
    while (index < path.len) : (index += 1) {
        const c = path[index];
        if (c == '\r' or c == '\n' or c == 0 or c == '?' or c == '#') return error.InvalidRawPath;
        if (c == '%') {
            if (index + 2 >= path.len or !std.ascii.isHex(path[index + 1]) or !std.ascii.isHex(path[index + 2]))
                return error.InvalidRawPath;
            index += 2;
        }
        writer.writeByte(c) catch return error.WriteFailed;
    }
}

pub const PathBuilder = struct {
    writer: *std.Io.Writer,
    started: bool = false,

    pub fn literal(self: *PathBuilder, text: []const u8) EncodeError!void {
        if (!self.started) {
            try self.writer.writeByte('/');
            self.started = true;
        }
        try self.writer.writeAll(text);
    }

    pub fn segment(self: *PathBuilder, value: []const u8) EncodeError!void {
        if (!self.started) {
            try self.writer.writeByte('/');
            self.started = true;
        } else {
            try self.writer.writeByte('/');
        }
        try encodeSegment(self.writer, value);
    }

    pub fn done(self: *PathBuilder) []const u8 {
        return self.writer.buffered();
    }
};

pub const QueryBuilder = struct {
    writer: *std.Io.Writer,
    count: usize = 0,

    pub fn add(self: *QueryBuilder, name: []const u8, value: []const u8) EncodeError!void {
        if (self.count == 0) {
            self.writer.writeByte('?') catch return error.WriteFailed;
        } else {
            self.writer.writeByte('&') catch return error.WriteFailed;
        }
        self.count += 1;
        try encodeQueryValue(self.writer, name);
        self.writer.writeByte('=') catch return error.WriteFailed;
        try encodeQueryValue(self.writer, value);
    }

    /// `null` omits the parameter entirely; an empty string serializes as
    /// `name=`.
    pub fn addOptional(self: *QueryBuilder, name: []const u8, value: ?[]const u8) EncodeError!void {
        if (value) |present| try self.add(name, present);
    }

    pub fn done(self: *QueryBuilder) []const u8 {
        return self.writer.buffered();
    }
};

test "path segments encode slash and unicode as one segment" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var path = PathBuilder{ .writer = &writer };
    try path.segment("<:123456789012345678>");
    try path.segment("a/b \u{1F600}");
    try std.testing.expectEqualStrings("/%3C%3A123456789012345678%3E/a%2Fb%20%F0%9F%98%80", path.done());
}

test "raw paths keep existing escapes and reject malformed ones" {
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try writeRawPath(&writer, "/a%20b/c");
    try std.testing.expectEqualStrings("/a%20b/c", writer.buffered());

    var bad_buffer: [64]u8 = undefined;
    var bad_writer = std.Io.Writer.fixed(&bad_buffer);
    try std.testing.expectError(error.InvalidRawPath, writeRawPath(&bad_writer, "/a%2"));
}

test "omitted query differs from an empty value" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    var query = QueryBuilder{ .writer = &writer };
    try query.addOptional("limit", null);
    try query.addOptional("before", "");
    try query.add("name", "a b&c");
    try std.testing.expectEqualStrings("?before=&name=a%20b%26c", query.done());
}

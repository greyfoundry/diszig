//! Streaming multipart writer for Discord message/webhook uploads.
//!
//! File contents are copied from the source in bounded chunks. The writer never
//! buffers a whole file and never closes caller-owned file handles.

const std = @import("std");

pub const Source = union(enum) {
    bytes: []const u8,
    file: std.Io.File,
};

pub const FilePart = struct {
    filename: []const u8,
    content_type: ?[]const u8 = null,
    source: Source,
};

pub const Error = error{
    InvalidBoundary,
    InvalidFilename,
    WriteFailed,
    ReadFailed,
    PayloadTooLarge,
};

fn validBoundary(boundary: []const u8) bool {
    if (boundary.len == 0 or boundary.len > 70) return false;
    for (boundary) |c| {
        if (c == '\r' or c == '\n' or c == 0) return false;
    }
    return true;
}

fn validFilename(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |c| {
        if (c == '\r' or c == '\n' or c == 0) return false;
    }
    return true;
}

fn writeQuoted(writer: *std.Io.Writer, value: []const u8) Error!void {
    try writer.writeByte('"');
    for (value) |c| {
        if (c == '"' or c == '\\') try writer.writeByte('\\');
        try writer.writeByte(c);
    }
    try writer.writeByte('"');
}

fn writeSource(writer: *std.Io.Writer, io: std.Io, source: Source) Error!void {
    switch (source) {
        .bytes => |bytes| writer.writeAll(bytes) catch return error.WriteFailed,
        .file => |file| {
            var reader_buffer: [4096]u8 = undefined;
            var chunk_buffer: [64 * 1024]u8 = undefined;
            var reader = file.reader(io, &reader_buffer);
            while (true) {
                const n = reader.interface.readSliceShort(&chunk_buffer) catch return error.ReadFailed;
                if (n == 0) return;
                writer.writeAll(chunk_buffer[0..n]) catch return error.WriteFailed;
            }
        },
    }
}

/// Writes a complete multipart/form-data body. `payload_json` is the caller's
/// already-validated JSON; files are streamed in order as `files[0]`, `files[1]`.
pub fn write(
    writer: *std.Io.Writer,
    io: std.Io,
    boundary: []const u8,
    payload_json: []const u8,
    files: []const FilePart,
    max_payload_bytes: usize,
) Error!void {
    if (!validBoundary(boundary)) return error.InvalidBoundary;
    if (payload_json.len > max_payload_bytes) return error.PayloadTooLarge;

    writer.writeAll("--") catch return error.WriteFailed;
    writer.writeAll(boundary) catch return error.WriteFailed;
    writer.writeAll("\r\nContent-Disposition: form-data; name=\"payload_json\"\r\nContent-Type: application/json\r\n\r\n") catch return error.WriteFailed;
    writer.writeAll(payload_json) catch return error.WriteFailed;
    writer.writeAll("\r\n") catch return error.WriteFailed;

    for (files, 0..) |file, index| {
        if (!validFilename(file.filename)) return error.InvalidFilename;

        writer.writeAll("--") catch return error.WriteFailed;
        writer.writeAll(boundary) catch return error.WriteFailed;
        writer.writeAll("\r\nContent-Disposition: form-data; name=\"files[") catch return error.WriteFailed;
        writer.print("{d}", .{index}) catch return error.WriteFailed;
        writer.writeAll("]\"; filename=") catch return error.WriteFailed;
        try writeQuoted(writer, file.filename);
        if (file.content_type) |content_type| {
            writer.writeAll("\r\nContent-Type: ") catch return error.WriteFailed;
            writer.writeAll(content_type) catch return error.WriteFailed;
        }
        writer.writeAll("\r\n\r\n") catch return error.WriteFailed;
        try writeSource(writer, io, file.source);
        writer.writeAll("\r\n") catch return error.WriteFailed;
    }

    writer.writeAll("--") catch return error.WriteFailed;
    writer.writeAll(boundary) catch return error.WriteFailed;
    writer.writeAll("--\r\n") catch return error.WriteFailed;
}

test "multipart body preserves multiple file parts" {
    var buffer: [2048]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const files = [_]FilePart{
        .{ .filename = "a b.txt", .content_type = "text/plain", .source = .{ .bytes = "one" } },
        .{ .filename = "b.txt", .source = .{ .bytes = "two" } },
    };
    try write(&writer, std.testing.io, "BOUND", "{\"content\":\"hi\"}", &files, 1024);
    const text = writer.buffered();
    try std.testing.expect(std.mem.indexOf(u8, text, "name=\"payload_json\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "name=\"files[0]\"; filename=\"a b.txt\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "name=\"files[1]\"; filename=\"b.txt\"") != null);
    try std.testing.expect(std.mem.endsWith(u8, text, "--BOUND--\r\n"));
}

test "invalid filenames and boundaries are rejected" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const bad_name = [_]FilePart{.{ .filename = "a\r\nb", .source = .{ .bytes = "x" } }};
    try std.testing.expectError(error.InvalidFilename, write(&writer, std.testing.io, "B", "{}", &bad_name, 16));

    var second: [256]u8 = undefined;
    var second_writer = std.Io.Writer.fixed(&second);
    try std.testing.expectError(error.InvalidBoundary, write(&second_writer, std.testing.io, "bad\r\n", "{}", &.{}, 16));
}

test "payload size is bounded" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(
        error.PayloadTooLarge,
        write(&writer, std.testing.io, "B", "{\"long\":\"payload\"}", &.{}, 4),
    );
}

//! Structured HTTP/Discord API errors.
//!
//! The HTTP status is preserved, Discord's numeric code is kept as an i64 so
//! unknown codes are representable, and a nested validation path is bounded.
//! Diagnostics use the shared redacted context; tokens are not stored here.

const std = @import("std");
const protocol = @import("protocol");

pub const Status = struct {
    code: u16,

    pub const ok: Status = .{ .code = 200 };
    pub const created: Status = .{ .code = 201 };
    pub const no_content: Status = .{ .code = 204 };
    pub const not_modified: Status = .{ .code = 304 };
    pub const bad_request: Status = .{ .code = 400 };
    pub const unauthorized: Status = .{ .code = 401 };
    pub const forbidden: Status = .{ .code = 403 };
    pub const not_found: Status = .{ .code = 404 };
    pub const method_not_allowed: Status = .{ .code = 405 };
    pub const too_many_requests: Status = .{ .code = 429 };
    pub const gateway_unavailable: Status = .{ .code = 502 };

    pub fn isSuccess(self: Status) bool {
        return self.code >= 200 and self.code < 300;
    }

    pub fn isRedirect(self: Status) bool {
        return self.code >= 300 and self.code < 400;
    }

    pub fn isClientError(self: Status) bool {
        return self.code >= 400 and self.code < 500;
    }

    pub fn isServerError(self: Status) bool {
        return self.code >= 500 and self.code < 600;
    }

    /// 1xx, 204 and 304 responses have no body to decode.
    pub fn bodyExpected(self: Status) bool {
        if (self.code >= 100 and self.code < 200) return false;
        return self.code != 204 and self.code != 304;
    }
};

pub const FieldPath = struct {
    pub const max = 192;
    buffer: [max]u8 = undefined,
    length: usize = 0,

    pub fn text(self: *const FieldPath) []const u8 {
        return self.buffer[0..self.length];
    }

    pub fn empty(self: FieldPath) bool {
        return self.length == 0;
    }
};

pub const ApiError = struct {
    status: Status,
    code: i64 = 0,
    retry_after_ms: ?u64 = null,
    field_path: FieldPath = .{},
    context: protocol.errors.Context = .{},

    pub fn unknownCode(self: ApiError, known: []const i64) bool {
        for (known) |value| {
            if (value == self.code) return false;
        }
        return true;
    }
};

const Segment = union(enum) {
    key: []const u8,
    index: usize,
};

const PathBuilder = struct {
    segments: [16]Segment = undefined,
    length: usize = 0,

    fn append(self: *PathBuilder, segment: Segment) bool {
        if (self.length == self.segments.len) return false;
        self.segments[self.length] = segment;
        self.length += 1;
        return true;
    }

    fn pop(self: *PathBuilder) void {
        if (self.length > 0) self.length -= 1;
    }

    fn render(self: *const PathBuilder) FieldPath {
        var path = FieldPath{};
        var writer = std.Io.Writer.fixed(&path.buffer);
        for (self.segments[0..self.length], 0..) |segment, index| {
            if (index != 0) writer.writeByte('.') catch break;
            switch (segment) {
                .key => |key| writer.writeAll(key) catch break,
                .index => |value| writer.print("{d}", .{value}) catch break,
            }
        }
        path.length = writer.end;
        return path;
    }
};

fn findErrors(value: std.json.Value, path: *PathBuilder, depth: usize) bool {
    if (depth > 16) return false;
    switch (value) {
        .object => |object| {
            if (object.get("_errors") != null) return true;
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                if (!path.append(.{ .key = entry.key_ptr.* })) return false;
                if (findErrors(entry.value_ptr.*, path, depth + 1)) return true;
                path.pop();
            }
        },
        .array => |array| {
            for (array.items, 0..) |item, index| {
                if (!path.append(.{ .index = index })) return false;
                if (findErrors(item, path, depth + 1)) return true;
                path.pop();
            }
        },
        else => {},
    }
    return false;
}

/// Extracts the first nested validation path from a Discord 50035 body. Input
/// is size- and depth-bounded; the returned path contains only field names and
/// array indices, never server messages or credentials.
pub fn firstFieldPath(
    allocator: std.mem.Allocator,
    body: []const u8,
    max_bytes: usize,
) !FieldPath {
    if (body.len > max_bytes) return error.InputTooLarge;
    try protocol.json.checkDepth(body, 16);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{
        .max_value_len = 4096,
    });
    defer parsed.deinit();

    if (parsed.value != .object) return error.InvalidErrorBody;
    const errors_value = parsed.value.object.get("errors") orelse return error.InvalidErrorBody;
    var builder = PathBuilder{};
    if (!findErrors(errors_value, &builder, 0)) return error.InvalidErrorBody;
    return builder.render();
}

test "nested validation path is retained" {
    const body =
        \\{"code":50035,"errors":{"activities":{"0":{"platform":{"_errors":[{"code":"BASE_TYPE_CHOICES"}]}}}}}
    ;
    const path = try firstFieldPath(std.testing.allocator, body, 4096);
    try std.testing.expectEqualStrings("activities.0.platform", path.text());
}

test "unknown codes are representable" {
    const api_error = ApiError{ .status = .bad_request, .code = 999_999 };
    try std.testing.expect(api_error.unknownCode(&.{ 50035, 50013 }));
}

test "204 and 304 have no body" {
    try std.testing.expect(!Status.no_content.bodyExpected());
    try std.testing.expect(!Status.not_modified.bodyExpected());
    try std.testing.expect(Status.ok.bodyExpected());
    try std.testing.expect(Status.created.isSuccess());
    try std.testing.expect(Status.too_many_requests.isClientError());
    try std.testing.expect(Status.gateway_unavailable.isServerError());
}

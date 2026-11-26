//! Caller-owned, allocation-free error context shared by REST, Gateway and
//! validation code.
//!
//! Zig errors cannot carry payloads. Instead, an operation takes `*Context`
//! supplied by its caller and fills it on failure. There is no global
//! last-error and no allocation hidden inside this type.
//!
//! Route and detail text pass through a bounded redactor before being stored.
//! Callers should still pass route templates such as `/webhooks/{}/{}` rather
//! than formatted URLs.

const std = @import("std");

pub const Kind = enum {
    unknown,
    canceled,
    timeout,
    connection,
    tls,
    http_status,
    discord_api,
    validation,
    rate_limited,
    ambiguous_write,
    out_of_memory,
    closed,
    unsupported,
};

pub const Context = struct {
    pub const max_route = 128;
    pub const max_detail = 256;

    kind: Kind = .unknown,
    status: ?u16 = null,
    discord_code: ?i64 = null,
    retry_after_ms: ?u64 = null,
    route_buf: [max_route]u8 = undefined,
    route_len: usize = 0,
    detail_buf: [max_detail]u8 = undefined,
    detail_len: usize = 0,

    pub fn init(kind: Kind) Context {
        return .{ .kind = kind };
    }

    pub fn reset(self: *Context) void {
        self.* = .{};
    }

    /// Stores a redacted route template or short description.
    pub fn setRoute(self: *Context, text: []const u8) void {
        self.route_len = redact(self.route_buf[0..], text);
    }

    pub fn route(self: *const Context) []const u8 {
        return self.route_buf[0..self.route_len];
    }

    /// Stores a redacted, truncated diagnostic excerpt.
    pub fn setDetail(self: *Context, text: []const u8) void {
        self.detail_len = redact(self.detail_buf[0..], text);
    }

    pub fn detail(self: *const Context) []const u8 {
        return self.detail_buf[0..self.detail_len];
    }
};

fn isTokenChar(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '_';
}

fn isCredentialChar(c: u8) bool {
    return isTokenChar(c) or c == '.';
}

fn isWordStart(src: []const u8, i: usize) bool {
    return i == 0 or !isTokenChar(src[i - 1]);
}

fn append(out: []u8, len: *usize, text: []const u8) void {
    if (len.* == out.len) return;
    const count = @min(text.len, out.len - len.*);
    @memcpy(out[len.*..][0..count], text[0..count]);
    len.* += count;
}

fn looksLikeBotToken(run: []const u8) bool {
    var parts = std.mem.splitScalar(u8, run, '.');
    var lengths: [3]usize = undefined;
    var count: usize = 0;
    while (parts.next()) |part| {
        if (count == 3) return false;
        if (part.len == 0) return false;
        for (part) |c| if (!isTokenChar(c)) return false;
        lengths[count] = part.len;
        count += 1;
    }
    return count == 3 and lengths[0] >= 10 and lengths[1] >= 5 and lengths[2] >= 20;
}

fn authorizationValueEnd(src: []const u8, i: usize) ?usize {
    if (!isWordStart(src, i)) return null;
    if (i + "authorization".len > src.len) return null;
    if (!std.ascii.eqlIgnoreCase(src[i..][0.."authorization".len], "authorization")) return null;

    var j = i + "authorization".len;
    while (j < src.len and (src[j] == ' ' or src[j] == '\t')) j += 1;
    if (j >= src.len or src[j] != ':') return null;
    j += 1;
    while (j < src.len and (src[j] == ' ' or src[j] == '\t')) j += 1;
    var end = j;
    while (end < src.len and src[end] != '\r' and src[end] != '\n') end += 1;
    return end;
}

fn tokenParameterEnd(src: []const u8, i: usize) ?usize {
    if (i == 0) return null;
    if (src[i - 1] != '?' and src[i - 1] != '&' and !std.ascii.isWhitespace(src[i - 1])) return null;
    if (i + "token=".len > src.len) return null;
    if (!std.ascii.eqlIgnoreCase(src[i..][0.."token=".len], "token=")) return null;
    var end = i + "token=".len;
    while (end < src.len and src[end] != '&' and !std.ascii.isWhitespace(src[end])) end += 1;
    return end;
}

fn webhookTokenEnd(src: []const u8, i: usize) ?usize {
    const prefix = "/webhooks/";
    if (i + prefix.len > src.len) return null;
    if (!std.mem.eql(u8, src[i..][0..prefix.len], prefix)) return null;

    var j = i + prefix.len;
    const id_start = j;
    while (j < src.len and std.ascii.isDigit(src[j])) j += 1;
    if (j == id_start or j >= src.len or src[j] != '/') return null;
    j += 1;
    const token_start = j;
    while (j < src.len and isTokenChar(src[j])) j += 1;
    if (j - token_start < 10) return null;
    return j;
}

fn credentialEnd(src: []const u8, i: usize) ?usize {
    if (!isCredentialChar(src[i])) return null;
    if (i > 0 and isCredentialChar(src[i - 1])) return null;
    var end = i;
    while (end < src.len and isCredentialChar(src[end])) end += 1;
    if (looksLikeBotToken(src[i..end])) return end;
    return null;
}

/// Copies at most `dst.len` bytes, replacing recognized credential material
/// with `[redacted]`. Never reads past `src`.
fn redact(dst: []u8, src: []const u8) usize {
    var out: usize = 0;
    var i: usize = 0;
    while (i < src.len) {
        if (authorizationValueEnd(src, i)) |end| {
            var j = i;
            while (j < src.len and src[j] != ':') j += 1;
            append(dst, &out, src[i .. j + 1]);
            append(dst, &out, " [redacted]");
            i = end;
            continue;
        }
        if (tokenParameterEnd(src, i)) |end| {
            append(dst, &out, src[i..][0.."token=".len]);
            append(dst, &out, "[redacted]");
            i = end;
            continue;
        }
        if (webhookTokenEnd(src, i)) |end| {
            const token_start = std.mem.lastIndexOfScalar(u8, src[i..end], '/').? + i + 1;
            append(dst, &out, src[i..token_start]);
            append(dst, &out, "[redacted]");
            i = end;
            continue;
        }
        if (credentialEnd(src, i)) |end| {
            append(dst, &out, "[redacted]");
            i = end;
            continue;
        }
        append(dst, &out, src[i..][0..1]);
        i += 1;
    }
    return out;
}

test "authorization header value is redacted" {
    var ctx = Context.init(.http_status);
    ctx.setDetail("Authorization: Bot MTA1234567890.ABCDEF.GHIJKLMNOPQRSTUVWXYZ123456\r\nnext");
    try std.testing.expectEqualStrings("Authorization: [redacted]\r\nnext", ctx.detail());
}

test "bot token is redacted outside a header" {
    var ctx = Context.init(.validation);
    ctx.setDetail("token MTA1234567890.ABCDEF.GHIJKLMNOPQRSTUVWXYZ123456 leaked");
    try std.testing.expectEqualStrings("token [redacted] leaked", ctx.detail());
}

test "token query parameter is redacted" {
    var ctx = Context.init(.validation);
    ctx.setDetail("/callback?state=ok&token=abcdefghijklmnop&x=1");
    try std.testing.expectEqualStrings("/callback?state=ok&token=[redacted]&x=1", ctx.detail());
}

test "webhook token path is redacted" {
    var ctx = Context.init(.http_status);
    ctx.setDetail("/webhooks/123456789012345678/abcdefghijklmnopqrstuvwxyz");
    try std.testing.expectEqualStrings("/webhooks/123456789012345678/[redacted]", ctx.detail());
}

test "route templates survive unchanged" {
    var ctx = Context.init(.connection);
    ctx.setRoute("/webhooks/{}/{}");
    try std.testing.expectEqualStrings("/webhooks/{}/{}", ctx.route());

    ctx.setRoute("/channels/{}/messages");
    try std.testing.expectEqualStrings("/channels/{}/messages", ctx.route());
}

test "detail is copied, bounded and reset" {
    var ctx = Context.init(.discord_api);
    var source: [300]u8 = undefined;
    @memset(source[0..], 'a');
    ctx.setDetail(source[0..]);

    try std.testing.expectEqual(Context.max_detail, ctx.detail().len);
    @memset(source[0..], 'b');
    try std.testing.expectEqual(@as(u8, 'a'), ctx.detail()[0]);

    ctx.reset();
    try std.testing.expectEqual(Kind.unknown, ctx.kind);
    try std.testing.expectEqual(@as(usize, 0), ctx.detail().len);
    try std.testing.expectEqual(@as(usize, 0), ctx.route().len);
}

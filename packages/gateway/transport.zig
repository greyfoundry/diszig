//! Discord Gateway WebSocket transport.
//!
//! This is the framing boundary, not a session: it opens one WebSocket,
//! reassembles fragmented messages, answers pings, applies transport
//! compression and returns gateway payloads in order. Identify, heartbeat,
//! resume and close-code policy live in the session layer.
//!
//! The pinned `websocket` package (see `THIRD_PARTY_NOTICES.md`) owns the
//! RFC 6455 framing. This module deliberately does not implement a second
//! frame parser.

const std = @import("std");
const websocket = @import("websocket");
const compression = @import("compression.zig");

pub const Compression = compression.Mode;

pub const Error = compression.Error || error{
    InvalidUrl,
    InvalidConfiguration,
    InvalidPing,
};

/// A parsed `ws://` or `wss://` URL. Slices borrow from the input string.
pub const Url = struct {
    host: []const u8,
    port: u16,
    tls: bool,
    /// Request target including the query string; always begins with `/`.
    path: []const u8,

    pub fn parse(text: []const u8) Error!Url {
        const scheme_end = std.mem.indexOf(u8, text, "://") orelse return error.InvalidUrl;
        const scheme = text[0..scheme_end];
        const rest = text[scheme_end + 3 ..];
        const tls = if (std.mem.eql(u8, scheme, "wss"))
            true
        else if (std.mem.eql(u8, scheme, "ws"))
            false
        else
            return error.InvalidUrl;

        if (rest.len == 0) return error.InvalidUrl;
        // Discord gateway URLs need neither userinfo nor fragments, and both
        // are easy to mishandle. Reject them explicitly.
        if (std.mem.indexOfScalar(u8, rest, '@') != null) return error.InvalidUrl;
        if (std.mem.indexOfScalar(u8, rest, '#') != null) return error.InvalidUrl;

        const authority_end = std.mem.indexOfAny(u8, rest, "/?") orelse rest.len;
        const authority = rest[0..authority_end];
        if (authority.len == 0) return error.InvalidUrl;
        // Bracket IPv6 literals are not supported at this boundary.
        if (authority[0] == '[') return error.InvalidUrl;

        const path = if (authority_end == rest.len)
            "/"
        else if (rest[authority_end] == '/')
            rest[authority_end..]
        else
            // A query with no path would produce an invalid request target.
            return error.InvalidUrl;
        if (path.len > 2048) return error.InvalidUrl;

        var host = authority;
        var port: u16 = if (tls) 443 else 80;
        if (std.mem.lastIndexOfScalar(u8, authority, ':')) |colon| {
            host = authority[0..colon];
            const port_text = authority[colon + 1 ..];
            if (port_text.len == 0) return error.InvalidUrl;
            port = std.fmt.parseInt(u16, port_text, 10) catch return error.InvalidUrl;
            if (port == 0) return error.InvalidUrl;
        }
        if (host.len == 0) return error.InvalidUrl;
        if (std.mem.indexOfScalar(u8, host, ':') != null) return error.InvalidUrl;

        return .{ .host = host, .port = port, .tls = tls, .path = path };
    }
};

pub const Options = struct {
    url: Url,
    /// Hard bound for one WebSocket message and for one decompressed gateway
    /// payload. The WebSocket library only honours `max_size` when the static
    /// read buffer cannot hold the message, so `read_buffer_bytes` must not
    /// exceed this value.
    max_message_bytes: usize = 16 * 1024 * 1024,
    /// Static WebSocket read buffer. Also holds the handshake request.
    read_buffer_bytes: usize = 16 * 1024,
    compression: Compression = .none,
    handshake_timeout_ms: u32 = 10_000,
    /// Default socket read timeout. `next` returns null when it expires.
    read_timeout_ms: u32 = 30_000,
    ca_bundle: ?std.crypto.Certificate.Bundle = null,
    /// Extra handshake headers ("Name: value" pairs joined by CRLF), no
    /// trailing CRLF required.
    extra_handshake_headers: ?[]const u8 = null,
};

pub const Kind = enum { text, binary, close };

pub const Message = struct {
    kind: Kind,
    /// Borrowed from the connection, valid until the next `next`, `close` or
    /// `deinit` call. For `close`, this is the reason string.
    data: []const u8,
    close_code: ?u16 = null,
};

pub const Connection = struct {
    allocator: std.mem.Allocator,
    client: websocket.Client,
    inflater: ?*compression.Inflater,
    message_buf: std.ArrayList(u8),
    max_message_bytes: usize,
    closed: bool,

    pub fn connect(allocator: std.mem.Allocator, io: std.Io, options: Options) !Connection {
        if (options.max_message_bytes == 0) return error.InvalidConfiguration;
        if (options.read_buffer_bytes == 0) return error.InvalidConfiguration;
        if (options.read_buffer_bytes > options.max_message_bytes) return error.InvalidConfiguration;
        if (options.compression == .zstd_stream) return error.UnsupportedCompression;

        // The library writes the request into the static read buffer without
        // bounds checks.
        const extra_len = if (options.extra_handshake_headers) |headers| headers.len else 0;
        const handshake_bytes = options.url.path.len + extra_len + 256;
        if (options.read_buffer_bytes < handshake_bytes) return error.InvalidConfiguration;

        var inflater: ?*compression.Inflater = null;
        if (options.compression == .zlib_stream) {
            const inf = try allocator.create(compression.Inflater);
            inf.init(allocator, options.max_message_bytes) catch |err| {
                allocator.destroy(inf);
                return err;
            };
            inflater = inf;
        }
        errdefer if (inflater) |inf| {
            inf.deinit();
            allocator.destroy(inf);
        };

        var client = try websocket.Client.init(io, allocator, .{
            .host = options.url.host,
            .port = options.url.port,
            .tls = options.url.tls,
            .max_size = options.max_message_bytes,
            .buffer_size = options.read_buffer_bytes,
            .ca_bundle = options.ca_bundle,
        });
        errdefer client.deinit();

        try client.handshake(options.url.path, .{
            .timeout_ms = options.handshake_timeout_ms,
            .headers = options.extra_handshake_headers,
        });
        try client.readTimeout(options.read_timeout_ms);

        return .{
            .allocator = allocator,
            .client = client,
            .inflater = inflater,
            .message_buf = .empty,
            .max_message_bytes = options.max_message_bytes,
            .closed = false,
        };
    }

    pub fn deinit(self: *Connection) void {
        self.client.deinit();
        if (self.inflater) |inf| {
            inf.deinit();
            self.allocator.destroy(inf);
        }
        @memset(self.message_buf.items, 0);
        self.message_buf.deinit(self.allocator);
        self.* = undefined;
    }

    pub fn isClosed(self: *const Connection) bool {
        return self.closed or self.client.isClosed();
    }

    /// Changes the socket read timeout. Used by the session's cancellation
    /// loop; a shorter timeout simply makes `next` return null more often.
    pub fn setReadTimeout(self: *Connection, ms: u32) !void {
        try self.client.readTimeout(ms);
    }

    /// Returns the next gateway payload, or null if the read timeout expired
    /// before a complete message arrived. Pings are answered and pongs are
    /// ignored internally.
    pub fn next(self: *Connection) !?Message {
        if (self.closed) return error.Closed;
        while (true) {
            const raw = try self.client.read() orelse return null;
            defer self.client.done(raw);

            switch (raw.type) {
                .text, .binary => {
                    if (raw.data.len == 0) continue;
                    if (self.inflater) |inf| {
                        const complete = try inf.feed(raw.data);
                        if (!complete) continue;
                        return .{
                            .kind = if (raw.type == .text) .text else .binary,
                            .data = inf.message(),
                        };
                    }
                    if (raw.data.len > self.max_message_bytes) return error.MessageTooLarge;
                    try self.message_buf.resize(self.allocator, raw.data.len);
                    @memcpy(self.message_buf.items, raw.data);
                    return .{
                        .kind = if (raw.type == .text) .text else .binary,
                        .data = self.message_buf.items,
                    };
                },
                .ping => try self.answerPing(raw.data),
                .pong => {},
                .close => {
                    self.closed = true;
                    const code: ?u16 = if (raw.data.len >= 2)
                        (@as(u16, raw.data[0]) << 8) | @as(u16, raw.data[1])
                    else
                        null;
                    const reason = if (raw.data.len > 2) raw.data[2..] else raw.data[0..0];
                    try self.message_buf.resize(self.allocator, reason.len);
                    @memcpy(self.message_buf.items, reason);
                    // Echo the close frame; a peer that already left may make
                    // this fail, which is not an application error.
                    self.client.close(.{ .code = code }) catch {};
                    return .{
                        .kind = .close,
                        .data = self.message_buf.items,
                        .close_code = code,
                    };
                },
            }
        }
    }

    /// Sends one text payload. The WebSocket library masks the payload in
    /// place, so a private copy is used and then wiped. This payload may
    /// contain an Identify token.
    pub fn sendText(self: *Connection, payload: []const u8) !void {
        if (self.closed) return error.Closed;
        if (payload.len > self.max_message_bytes) return error.MessageTooLarge;
        const copy = try self.allocator.dupe(u8, payload);
        defer {
            @memset(copy, 0);
            self.allocator.free(copy);
        }
        try self.client.writeText(copy);
    }

    /// Best-effort close frame. Errors are ignored because the transport may
    /// already be gone; callers that need certainty should inspect `isClosed`.
    pub fn close(self: *Connection, code: ?u16, reason: []const u8) void {
        self.client.close(.{ .code = code, .reason = reason }) catch {};
        self.closed = true;
    }

    fn answerPing(self: *Connection, data: []u8) !void {
        // Control frame payloads are at most 125 bytes (RFC 6455 5.5).
        if (data.len > 125) return error.InvalidPing;
        var buf: [125]u8 = undefined;
        @memcpy(buf[0..data.len], data);
        try self.client.writePong(buf[0..data.len]);
    }
};

test "url parsing covers the documented gateway shape" {
    const url = try Url.parse("wss://gateway.discord.gg/?v=10&encoding=json");
    try std.testing.expectEqualStrings("gateway.discord.gg", url.host);
    try std.testing.expectEqual(@as(u16, 443), url.port);
    try std.testing.expect(url.tls);
    try std.testing.expectEqualStrings("/?v=10&encoding=json", url.path);

    const plain = try Url.parse("ws://127.0.0.1:8080/socket");
    try std.testing.expectEqualStrings("127.0.0.1", plain.host);
    try std.testing.expectEqual(@as(u16, 8080), plain.port);
    try std.testing.expect(!plain.tls);
    try std.testing.expectEqualStrings("/socket", plain.path);

    const no_path = try Url.parse("wss://gateway.discord.gg");
    try std.testing.expectEqualStrings("/", no_path.path);
}

test "url parsing rejects ambiguous or unsupported forms" {
    try std.testing.expectError(error.InvalidUrl, Url.parse("https://gateway.discord.gg/"));
    try std.testing.expectError(error.InvalidUrl, Url.parse("wss://"));
    try std.testing.expectError(error.InvalidUrl, Url.parse("wss://user@host/"));
    try std.testing.expectError(error.InvalidUrl, Url.parse("wss://host/#frag"));
    try std.testing.expectError(error.InvalidUrl, Url.parse("wss://host:0/"));
    try std.testing.expectError(error.InvalidUrl, Url.parse("wss://host:notaport/"));
    try std.testing.expectError(error.InvalidUrl, Url.parse("wss://[::1]/"));
    try std.testing.expectError(error.InvalidUrl, Url.parse("wss://host?v=10"));
}

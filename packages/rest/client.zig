//! Independently usable Discord REST client transport.
//!
//! This module does not require Gateway, client, builders or voice. It uses
//! `std.http.Client` with bounded bodies, explicit redirects and credential
//! separation.

const std = @import("std");
const transport = @import("transport.zig");
const rest_errors = @import("errors.zig");
const retry = @import("retry.zig");

pub const Auth = transport.Auth;

pub const Options = struct {
    base_url: []const u8 = "https://discord.com/api/v10",
    auth: Auth = .none,
    /// Takes ownership when supplied; the client frees the bundle in deinit.
    ca_bundle: ?std.crypto.Certificate.Bundle = null,
    max_response_bytes: usize = 8 * 1024 * 1024,
    max_redirects: u8 = 3,
};

pub const RequestOptions = struct {
    body: ?[]const u8 = null,
    extra_headers: []const std.http.Header = &.{},
    max_response_bytes: ?usize = null,
};

pub const Response = struct {
    status: u16,
    body: []u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *Response) void {
        self.allocator.free(self.body);
        self.* = undefined;
    }
};

pub const Error = error{
    BaseUrlTooLong,
    AuthTooLong,
    InvalidAuth,
    CrossOriginRedirect,
    RedirectRequiresResend,
    TooManyRedirects,
    TransportReadFailed,
};

pub const Client = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    http: std.http.Client,
    base_url: [256]u8 = undefined,
    base_url_len: usize = 0,
    auth_buffer: [256]u8 = undefined,
    auth_len: usize = 0,
    max_response_bytes: usize,
    max_redirects: u8,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, options: Options) !Client {
        var self = Client{
            .allocator = allocator,
            .io = io,
            .http = .{
                .allocator = allocator,
                .io = io,
                .read_buffer_size = 16 * 1024,
            },
            .max_response_bytes = options.max_response_bytes,
            .max_redirects = options.max_redirects,
        };

        if (options.base_url.len > self.base_url.len) return error.BaseUrlTooLong;
        @memcpy(self.base_url[0..options.base_url.len], options.base_url);
        self.base_url_len = options.base_url.len;

        const auth_value = transport.writeAuthHeader(options.auth, &self.auth_buffer) catch |err| switch (err) {
            error.TokenTooLong => return error.AuthTooLong,
            error.InvalidToken => return error.InvalidAuth,
        };
        self.auth_len = auth_value.len;

        if (options.ca_bundle) |bundle| {
            self.http.ca_bundle = bundle;
            self.http.now = std.Io.Timestamp.now(io, .real);
        }
        return self;
    }

    pub fn deinit(self: *Client) void {
        @memset(&self.auth_buffer, 0);
        self.http.deinit();
        self.* = undefined;
    }

    pub fn authHeader(self: *const Client) []const u8 {
        return self.auth_buffer[0..self.auth_len];
    }

    fn maxBody(self: *const Client, options: RequestOptions) usize {
        return options.max_response_bytes orelse self.max_response_bytes;
    }

    fn nowMs(self: *Client) i64 {
        return @intCast(@divTrunc(std.Io.Timestamp.now(self.io, .awake).nanoseconds, std.time.ns_per_ms));
    }

    /// Runs a request under the bounded retry policy. Non-idempotent requests
    /// are never replayed after a transport error; the caller gets
    /// `error.AmbiguousWrite` instead.
    pub fn sendRetry(
        self: *Client,
        method: std.http.Method,
        path: []const u8,
        options: RequestOptions,
        idempotency: retry.Idempotency,
        policy: retry.Policy,
    ) !Response {
        var state = retry.Retry.init(policy, self.nowMs());
        while (true) {
            var response = self.send(method, path, options) catch |err| {
                const outcome = state.afterTransportError(
                    idempotency,
                    options.body != null,
                    self.nowMs(),
                );
                switch (outcome) {
                    .retry_after_ms => |delay| {
                        try std.Io.sleep(self.io, .fromMilliseconds(@intCast(delay)), .awake);
                        continue;
                    },
                    .ambiguous => return error.AmbiguousWrite,
                    .canceled => return error.Canceled,
                    else => return err,
                }
            };

            const outcome = state.afterResponse(
                response.status,
                idempotency,
                null,
                self.nowMs(),
            );
            switch (outcome) {
                .success => return response,
                .retry_after_ms => |delay| {
                    response.deinit();
                    try std.Io.sleep(self.io, .fromMilliseconds(@intCast(delay)), .awake);
                },
                .ambiguous => {
                    response.deinit();
                    return error.AmbiguousWrite;
                },
                .canceled => {
                    response.deinit();
                    return error.Canceled;
                },
                .fail => return response,
            }
        }
    }

    pub fn send(
        self: *Client,
        method: std.http.Method,
        path: []const u8,
        options: RequestOptions,
    ) !Response {
        var uri_buffer: [1024]u8 = undefined;
        var uri = try transport.buildUri(self.base_url[0..self.base_url_len], path, &uri_buffer);

        var location_buffer: [2048]u8 = undefined;
        var hops: u8 = 0;
        while (true) {
            const attempt = try self.sendOnce(method, uri, options, &location_buffer);
            switch (attempt) {
                .response => |response| return response,
                .redirect => |location| {
                    if (options.body != null) return error.RedirectRequiresResend;
                    if (hops >= self.max_redirects) return error.TooManyRedirects;
                    const next = std.Uri.parse(location) catch return error.CrossOriginRedirect;
                    if (!transport.sameOrigin(uri, next)) return error.CrossOriginRedirect;
                    uri = next;
                    hops += 1;
                },
            }
        }
    }

    const Attempt = union(enum) {
        response: Response,
        redirect: []const u8,
    };

    fn sendOnce(
        self: *Client,
        method: std.http.Method,
        uri: std.Uri,
        options: RequestOptions,
        location_buffer: []u8,
    ) !Attempt {
        const auth_override: std.http.Client.Request.Headers.Value = if (self.auth_len == 0)
            .default
        else
            .{ .override = self.authHeader() };

        var request = try self.http.request(method, uri, .{
            .redirect_behavior = .unhandled,
            .headers = .{ .authorization = auth_override },
            .extra_headers = options.extra_headers,
        });
        defer request.deinit();

        if (options.body) |body| {
            request.transfer_encoding = .{ .content_length = body.len };
            var body_writer = try request.sendBodyUnflushed(&.{});
            try body_writer.writer.writeAll(body);
            try body_writer.end();
            try request.connection.?.flush();
        } else {
            try request.sendBodiless();
        }

        var head_buffer: [32 * 1024]u8 = undefined;
        var response = try request.receiveHead(&head_buffer);

        if (response.head.status.class() == .redirect) {
            const location = response.head.location orelse return error.CrossOriginRedirect;
            if (location.len > location_buffer.len) return error.CrossOriginRedirect;
            @memcpy(location_buffer[0..location.len], location);
            return .{ .redirect = location_buffer[0..location.len] };
        }

        const status: u16 = @intCast(@backingInt(response.head.status));
        if (!(rest_errors.Status{ .code = status }).bodyExpected()) {
            return .{ .response = .{
                .status = status,
                .body = try self.allocator.alloc(u8, 0),
                .allocator = self.allocator,
            } };
        }

        var transfer_buffer: [64]u8 = undefined;
        const reader = response.reader(&transfer_buffer);
        const body = reader.allocRemaining(
            self.allocator,
            .limited(self.maxBody(options)),
        ) catch |err| switch (err) {
            error.ReadFailed => {
                if (response.bodyErr()) |body_error| return body_error;
                return error.TransportReadFailed;
            },
            else => |e| return e,
        };
        return .{ .response = .{
            .status = status,
            .body = body,
            .allocator = self.allocator,
        } };
    }
};

test "auth header is distinct for bot and bearer" {
    var client = try Client.init(std.testing.allocator, std.testing.io, .{
        .auth = .{ .bearer = "abc" },
    });
    defer client.deinit();
    try std.testing.expectEqualStrings("Bearer abc", client.authHeader());
}

//! Shared route metadata for scheduling and diagnostics.
//!
//! A limiter identity is method + normalized route + major parameter + auth
//! domain. Parameter values are never used as diagnostic identifiers, and
//! webhook/interaction tokens stay out of the normalized route.

const std = @import("std");

pub const Method = std.http.Method;

pub const AuthDomain = enum {
    none,
    bot,
    bearer,
    webhook,
    interaction,
};

pub const Major = enum {
    none,
    guild,
    channel,
    webhook,
    application,
};

pub const Route = struct {
    method: Method,
    template: []const u8,
    major: Major = .none,
    auth: AuthDomain = .bot,

    pub fn identity(self: Route, major_id: ?u64) Identity {
        return .{
            .method = self.method,
            .template = self.template,
            .major = self.major,
            .major_id = major_id,
            .auth = self.auth,
        };
    }
};

pub const Identity = struct {
    method: Method,
    template: []const u8,
    major: Major,
    major_id: ?u64,
    auth: AuthDomain,

    pub fn writeBucketKey(self: Identity, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{s} {s} major={s}", .{
            @tagName(self.method),
            self.template,
            @tagName(self.major),
        });
        if (self.major_id) |id| try writer.print(":{d}", .{id});
        try writer.print(" auth={s}", .{@tagName(self.auth)});
    }
};

pub const get_current_user = Route{
    .method = .GET,
    .template = "/users/@me",
    .auth = .bearer,
};

pub const create_message = Route{
    .method = .POST,
    .template = "/channels/{}/messages",
    .major = .channel,
};

pub const get_guild_member = Route{
    .method = .GET,
    .template = "/guilds/{}/members/{}",
    .major = .guild,
};

pub const execute_webhook = Route{
    .method = .POST,
    .template = "/webhooks/{}/{}",
    .major = .webhook,
    .auth = .webhook,
};

pub const get_application_commands = Route{
    .method = .GET,
    .template = "/applications/{}/commands",
    .major = .application,
};

test "same route with different major ids has different identity" {
    var a_buf: [128]u8 = undefined;
    var b_buf: [128]u8 = undefined;
    var a_writer = std.Io.Writer.fixed(&a_buf);
    var b_writer = std.Io.Writer.fixed(&b_buf);
    try create_message.identity(1).writeBucketKey(&a_writer);
    try create_message.identity(2).writeBucketKey(&b_writer);
    try std.testing.expect(!std.mem.eql(u8, a_writer.buffered(), b_writer.buffered()));
    try std.testing.expect(std.mem.indexOf(u8, a_writer.buffered(), "channels/{}/messages") != null);
}

test "bucket key never contains a webhook token" {
    var buffer: [160]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try execute_webhook.identity(123).writeBucketKey(&writer);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "webhooks/{}/{}") != null);
    try std.testing.expect(std.mem.indexOf(u8, writer.buffered(), "secret") == null);
}

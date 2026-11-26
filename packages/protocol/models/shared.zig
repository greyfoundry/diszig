//! Shared Discord wire models, batch 1.
//!
//! String unions whose values are still evolving are mapped to `[]const u8`
//! wire fields rather than brittle enums. Numeric unions with stable values use
//! integer enums. Response arrays borrow the JSON parse arena.

const std = @import("std");

pub const ActionTypes = []const u8;
pub const AvailableLocalesEnum = []const u8;
pub const HasOption = []const u8;
pub const Int53Type = i64;

pub const AfkTimeouts = enum(i32) {
    one_minute = 60,
    five_minutes = 300,
    fifteen_minutes = 900,
    thirty_minutes = 1800,
    one_hour = 3600,
};

pub const AuthorType = enum {
    user,
    bot,
    webhook,
    no_user,
    no_bot,
    no_webhook,

    pub fn wireName(self: AuthorType) []const u8 {
        return switch (self) {
            .user => "user",
            .bot => "bot",
            .webhook => "webhook",
            .no_user => "-user",
            .no_bot => "-bot",
            .no_webhook => "-webhook",
        };
    }
};

pub const AutomodActionType = enum(i32) {
    block_message = 1,
    flag_to_channel = 2,
    user_communication_disabled = 3,
    quarantine_user = 4,
};

pub const AutomodEventType = enum(i32) {
    message_send = 1,
    guild_member_join_or_update = 2,
};

pub const AutomodKeywordPresetType = enum(i32) {
    profanity = 1,
    sexual_content = 2,
    slurs = 3,
};

pub const AutomodTriggerType = enum(i32) {
    keyword = 1,
    ml_spam = 3,
    default_keyword_list = 4,
    mention_spam = 5,
    user_profile = 6,
};

pub const ContentScanMetadataResponse = struct {
    flags: u64,
};

pub const EntityMetadataExternal = struct {
    location: []const u8,
};

pub const EntityMetadataExternalResponse = struct {
    location: []const u8,
};

pub const Error = struct {
    code: i32,
    message: []const u8,
};

pub const GatewayBotSessionStartLimitResponse = struct {
    max_concurrency: u32,
    remaining: u32,
    reset_after: u64,
    total: u32,
};

pub const GatewayResponse = struct {
    url: []const u8,
};

pub const GithubAuthor = struct {
    name: []const u8,
    username: ?[]const u8 = null,
};

pub const GithubCheckApp = struct {
    name: []const u8,
};

pub const GithubCheckPullRequest = struct {
    number: i64,
};

pub const GithubCheckRunOutput = struct {
    summary: ?[]const u8 = null,
    title: ?[]const u8 = null,
};

pub const GithubRepository = struct {
    id: u64,
    name: []const u8,
    full_name: []const u8,
    html_url: []const u8,
};

pub const KeywordTriggerMetadata = struct {
    allow_list: ?[]const []const u8 = null,
    keyword_filter: ?[]const []const u8 = null,
    regex_patterns: ?[]const []const u8 = null,
};

pub const KeywordTriggerMetadataResponse = struct {
    allow_list: []const []const u8,
    keyword_filter: []const []const u8,
    regex_patterns: []const []const u8,
};

pub const MLSpamTriggerMetadata = struct {};

test "shared enums use documented numeric values" {
    try std.testing.expectEqual(@as(i32, 60), @backingInt(AfkTimeouts.one_minute));
    try std.testing.expectEqual(@as(i32, 4), @backingInt(AutomodActionType.quarantine_user));
    try std.testing.expectEqualStrings("-webhook", AuthorType.no_webhook.wireName());
}

test "shared response structures decode representative JSON" {
    const bytes =
        \\{"code":50035,"message":"Invalid Form Body"}
    ;
    var parsed = try std.json.parseFromSlice(Error, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(i32, 50035), parsed.value.code);
    try std.testing.expectEqualStrings("Invalid Form Body", parsed.value.message);

    const gateway =
        \\{"url":"wss://gateway.discord.gg"}
    ;
    var gateway_parsed = try std.json.parseFromSlice(GatewayResponse, std.testing.allocator, gateway, .{});
    defer gateway_parsed.deinit();
    try std.testing.expectEqualStrings("wss://gateway.discord.gg", gateway_parsed.value.url);
}

test "keyword metadata arrays decode with ownership by the parse arena" {
    const bytes =
        \\{"keyword_filter":["one","two"],"regex_patterns":["^a"],"allow_list":[]}
    ;
    var parsed = try std.json.parseFromSlice(KeywordTriggerMetadataResponse, std.testing.allocator, bytes, .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(usize, 2), parsed.value.keyword_filter.len);
    try std.testing.expectEqualStrings("two", parsed.value.keyword_filter[1]);
    try std.testing.expectEqual(@as(usize, 0), parsed.value.allow_list.len);
}

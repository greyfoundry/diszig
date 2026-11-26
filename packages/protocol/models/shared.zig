//! Shared Discord wire models, batch 1.
//!
//! String unions whose values are still evolving are mapped to `[]const u8`
//! wire fields rather than brittle enums. Numeric unions with stable values use
//! integer enums. Response arrays borrow the JSON parse arena.

const std = @import("std");
const permissions = @import("../permissions.zig");

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
pub const MLSpamTriggerMetadataResponse = struct {};
pub const TypingIndicatorResponse = struct {};

pub const MentionSpamTriggerMetadata = struct {
    mention_total_limit: ?u32 = null,
    mention_raid_protection_enabled: ?bool = null,
};

pub const MentionSpamTriggerMetadataResponse = struct {
    mention_total_limit: u32,
    mention_raid_protection_enabled: bool,
};

pub const MetadataItemTypes = enum(i32) {
    integer_less_than_equal = 1,
    integer_greater_than_equal = 2,
    integer_equal = 3,
    integer_not_equal = 4,
    datetime_less_than_equal = 5,
    datetime_greater_than_equal = 6,
    boolean_equal = 7,
    boolean_not_equal = 8,
};

pub const NameplatePalette = enum {
    crimson,
    berry,
    sky,
    teal,
    forest,
    bubble_gum,
    violet,
    cobalt,
    clover,
    lemon,
    white,
    black,

    pub fn wireName(self: NameplatePalette) []const u8 {
        return @tagName(self);
    }
};

pub const PermissionsResponse = struct {
    permissions: []const u8,

    pub fn value(self: PermissionsResponse) !permissions.Permissions {
        return permissions.Permissions.parseDecimal(self.permissions);
    }
};

pub const PurchaseType = enum(i32) {
    guild_product = 0,
};

pub const RecurrenceRuleFrequencies = enum(i32) {
    yearly = 0,
    monthly = 1,
    weekly = 2,
    daily = 3,
};

pub const RecurrenceRuleMonths = enum(i32) {
    january = 1,
    february = 2,
    march = 3,
    april = 4,
    may = 5,
    june = 6,
    july = 7,
    august = 8,
    september = 9,
    october = 10,
    november = 11,
    december = 12,
};

pub const RecurrenceRuleWeekdays = enum(i32) {
    monday = 0,
    tuesday = 1,
    wednesday = 2,
    thursday = 3,
    friday = 4,
    saturday = 5,
    sunday = 6,
};

pub const SearchIndexNotReadyResponse = struct {
    message: []const u8,
    code: i32,
    documents_indexed: i32,
    retry_after: i32,
};

pub const SnowflakeType = @import("../snowflake.zig").Snowflake;
pub const UInt32Type = u32;

pub const SortingMode = enum {
    relevance,
    timestamp,

    pub fn wireName(self: SortingMode) []const u8 {
        return @tagName(self);
    }
};

pub const SortingOrder = enum {
    asc,
    desc,

    pub fn wireName(self: SortingOrder) []const u8 {
        return @tagName(self);
    }
};

pub const UpdateDMRequestPartial = struct {
    name: ?[]const u8 = null,
};

pub const UpdateGroupDMRequestPartial = struct {
    name: ?[]const u8 = null,
    icon: ?[]const u8 = null,
};

pub const VanityURLErrorResponse = struct {
    message: []const u8,
    code: i32,
};

pub const VerificationLevels = enum(i32) {
    none = 0,
    low = 1,
    medium = 2,
    high = 3,
    very_high = 4,
};

pub const VideoQualityModes = enum(i32) {
    auto = 1,
    full = 2,
};

pub const WebhookTypes = enum(i32) {
    guild_incoming = 1,
    channel_follower = 2,
    application_incoming = 3,
};

pub const WidgetImageStyles = enum {
    shield,
    banner1,
    banner2,
    banner3,
    banner4,

    pub fn wireName(self: WidgetImageStyles) []const u8 {
        return @tagName(self);
    }
};

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

test "mention spam and search-index responses decode" {
    const mention =
        \\{"mention_total_limit":5,"mention_raid_protection_enabled":true}
    ;
    var parsed_mention = try std.json.parseFromSlice(MentionSpamTriggerMetadataResponse, std.testing.allocator, mention, .{});
    defer parsed_mention.deinit();
    try std.testing.expectEqual(@as(u32, 5), parsed_mention.value.mention_total_limit);
    try std.testing.expect(parsed_mention.value.mention_raid_protection_enabled);

    const search =
        \\{"message":"Index not ready","code":110000,"documents_indexed":10,"retry_after":500}
    ;
    var parsed_search = try std.json.parseFromSlice(SearchIndexNotReadyResponse, std.testing.allocator, search, .{});
    defer parsed_search.deinit();
    try std.testing.expectEqual(@as(i32, 110000), parsed_search.value.code);
}

test "permissions response parses its decimal bitfield" {
    var parsed = try std.json.parseFromSlice(PermissionsResponse, std.testing.allocator, "{\"permissions\":\"8\"}", .{});
    defer parsed.deinit();
    const value = try parsed.value.value();
    try std.testing.expect(value.has(permissions.ADMINISTRATOR));
}

test "SnowflakeType decodes a JSON string only" {
    var parsed = try std.json.parseFromSlice(SnowflakeType, std.testing.allocator, "\"18446744073709551615\"", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(std.math.maxInt(u64), parsed.value.toU64());
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

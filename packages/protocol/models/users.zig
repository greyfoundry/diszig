//! Users wire contracts, dependency layer 0, batch 1.
//!
//! These models come from the pinned OpenAPI schema. Several are wire-only or
//! automation/audit support types; they are exposed as source-level types with
//! no endpoint claim. Integer/string enums have tolerant inbound wrappers.

const std = @import("std");
const json = @import("../json.zig");

pub const Error = error{
    MissingName,
    InvalidUsername,
    InvalidBase64,
    DurationOutOfRange,
    TooManyKeywords,
    InvalidKeyword,
    TooManyRegexPatterns,
    InvalidRegexPattern,
    TooManyAllowListEntries,
    InvalidAllowListEntry,
    InvalidDiscriminator,
};

pub const ActivityActionTypes = enum(u8) {
    join = 1,
    spectate = 2,
    listen = 3,
    join_request = 5,
    stream_request = 6,
};

pub const InboundActivityActionTypes = json.InboundEnum(ActivityActionTypes);

pub const ConnectedAccountProviders = enum {
    battlenet,
    bluesky,
    bungie,
    ebay,
    epicgames,
    facebook,
    github,
    instagram,
    letterboxd,
    mastodon,
    leagueoflegends,
    paypal,
    playstation,
    reddit,
    riotgames,
    roblox,
    skype,
    spotify,
    steam,
    tiktok,
    twitch,
    twitter,
    xbox,
    youtube,
    domain,
};

pub const InboundConnectedAccountProviders = json.InboundStringEnum(ConnectedAccountProviders);

pub const ConnectedAccountVisibility = enum(u8) {
    none = 0,
    everyone = 1,
};

pub const InboundConnectedAccountVisibility = json.InboundEnum(ConnectedAccountVisibility);

pub const NewMemberActionType = enum(u8) {
    view = 0,
    talk = 1,
};

pub const InboundNewMemberActionType = json.InboundEnum(NewMemberActionType);

pub const TargetUsersJobStatusTypes = enum(u8) {
    unspecified = 0,
    processing = 1,
    completed = 2,
    failed = 3,
};

pub const InboundTargetUsersJobStatusTypes = json.InboundEnum(TargetUsersJobStatusTypes);

pub const TeamMembershipStates = enum(u8) {
    invited = 1,
    accepted = 2,
};

pub const InboundTeamMembershipStates = json.InboundEnum(TeamMembershipStates);

pub const UserNotificationSettings = enum(u8) {
    all_messages = 0,
    only_mentions = 1,
};

pub const InboundUserNotificationSettings = json.InboundEnum(UserNotificationSettings);

/// The schema allows exactly the string `"0000"`.
pub const WidgetUserDiscriminator = struct {
    pub const zeroes: []const u8 = "0000";

    pub fn parse(value: []const u8) error{InvalidDiscriminator}![]const u8 {
        if (!std.mem.eql(u8, value, zeroes)) return error.InvalidDiscriminator;
        return zeroes;
    }
};

pub const AccountResponse = struct {
    id: []const u8,
    name: json.Presence([]const u8) = .absent,

    pub fn validate(self: AccountResponse) Error!void {
        if (self.name.isAbsent()) return error.MissingName;
    }
};

pub const BotAccountPatchRequest = struct {
    username: []const u8,
    avatar: ?[]const u8 = null,
    banner: ?[]const u8 = null,

    pub fn validate(self: BotAccountPatchRequest) Error!void {
        if (self.username.len < 2 or self.username.len > 32) return error.InvalidUsername;
        if (self.avatar) |value| try validateBase64(value);
        if (self.banner) |value| try validateBase64(value);
    }
};

pub const GithubUser = struct {
    id: i64,
    login: []const u8,
    html_url: []const u8,
    avatar_url: []const u8,
};

pub const QuarantineUserActionMetadata = struct {};

pub const QuarantineUserActionMetadataResponse = struct {};

pub const UserCommunicationDisabledActionMetadata = struct {
    duration_seconds: ?i64 = null,

    pub fn validate(self: UserCommunicationDisabledActionMetadata) Error!void {
        if (self.duration_seconds) |value| {
            if (value < 0 or value > 2_419_200) return error.DurationOutOfRange;
        }
    }
};

pub const UserCommunicationDisabledActionMetadataResponse = struct {
    duration_seconds: i64,
};

pub const UserProfileMetadata = struct {
    keyword_filter: ?[]const []const u8 = null,
    regex_patterns: ?[]const []const u8 = null,
    allow_list: ?[]const []const u8 = null,

    pub fn validate(self: UserProfileMetadata) Error!void {
        if (self.keyword_filter) |values| {
            if (values.len > 1000) return error.TooManyKeywords;
            for (values) |value| {
                if (value.len == 0 or value.len > 60) return error.InvalidKeyword;
            }
        }
        if (self.regex_patterns) |values| {
            if (values.len > 10) return error.TooManyRegexPatterns;
            for (values) |value| {
                if (value.len == 0 or value.len > 260) return error.InvalidRegexPattern;
            }
        }
        if (self.allow_list) |values| {
            if (values.len > 100) return error.TooManyAllowListEntries;
            for (values) |value| {
                if (value.len == 0 or value.len > 60) return error.InvalidAllowListEntry;
            }
        }
    }
};

pub const UserProfileMetadataResponse = struct {
    keyword_filter: []const []const u8,
    regex_patterns: []const []const u8,
    allow_list: []const []const u8,
};

pub const WidgetActivity = struct {
    name: []const u8,
};

fn validateBase64(value: []const u8) Error!void {
    _ = std.base64.standard.Decoder.calcSizeForSlice(value) catch return error.InvalidBase64;
}

test "documented enum values" {
    try std.testing.expectEqual(@as(u8, 5), @backingInt(ActivityActionTypes.join_request));
    try std.testing.expectEqual(@as(u8, 6), @backingInt(ActivityActionTypes.stream_request));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(ConnectedAccountVisibility.everyone));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(TargetUsersJobStatusTypes.failed));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(TeamMembershipStates.accepted));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(UserNotificationSettings.only_mentions));
    try std.testing.expectEqualStrings("domain", @tagName(ConnectedAccountProviders.domain));
    try std.testing.expectEqualStrings("0000", try WidgetUserDiscriminator.parse("0000"));
    try std.testing.expectError(error.InvalidDiscriminator, WidgetUserDiscriminator.parse("0001"));
}

test "account response keeps absent, null and value distinct" {
    var absent = try std.json.parseFromSlice(AccountResponse, std.testing.allocator,
        \\{"id":"1"}
    , .{ .ignore_unknown_fields = true });
    defer absent.deinit();
    try std.testing.expect(absent.value.name.isAbsent());
    try std.testing.expectError(error.MissingName, absent.value.validate());

    var explicit_null = try std.json.parseFromSlice(AccountResponse, std.testing.allocator,
        \\{"id":"1","name":null}
    , .{ .ignore_unknown_fields = true });
    defer explicit_null.deinit();
    try std.testing.expect(explicit_null.value.name.isNull());
    try explicit_null.value.validate();

    var value = try std.json.parseFromSlice(AccountResponse, std.testing.allocator,
        \\{"id":"1","name":"acct"}
    , .{ .ignore_unknown_fields = true });
    defer value.deinit();
    try std.testing.expectEqualStrings("acct", value.value.name.get().?);
}

test "bot account patch validation" {
    try (BotAccountPatchRequest{ .username = "ab" }).validate();
    try std.testing.expectError(
        error.InvalidUsername,
        (BotAccountPatchRequest{ .username = "a" }).validate(),
    );
    try std.testing.expectError(
        error.InvalidBase64,
        (BotAccountPatchRequest{ .username = "ab", .avatar = "not base64!" }).validate(),
    );
    try (BotAccountPatchRequest{ .username = "ab", .avatar = "aGVsbG8=" }).validate();
}

test "profile metadata and timeout limits" {
    try (UserCommunicationDisabledActionMetadata{ .duration_seconds = 2_419_200 }).validate();
    try std.testing.expectError(
        error.DurationOutOfRange,
        (UserCommunicationDisabledActionMetadata{ .duration_seconds = 2_419_201 }).validate(),
    );

    const too_many: [1001][]const u8 = @splat("safe");
    try std.testing.expectError(
        error.TooManyKeywords,
        (UserProfileMetadata{ .keyword_filter = &too_many }).validate(),
    );
    try std.testing.expectError(
        error.InvalidKeyword,
        (UserProfileMetadata{ .keyword_filter = &.{""} }).validate(),
    );
    const long_regex: [261]u8 = @splat('a');
    try std.testing.expectError(
        error.InvalidRegexPattern,
        (UserProfileMetadata{ .regex_patterns = &.{&long_regex} }).validate(),
    );
}

test "wire-only models parse" {
    var github = try std.json.parseFromSlice(GithubUser, std.testing.allocator,
        \\{"id":1,"login":"octocat","html_url":"https://github.com/octocat","avatar_url":"https://avatar"}
    , .{ .ignore_unknown_fields = true });
    defer github.deinit();
    try std.testing.expectEqual(@as(i64, 1), github.value.id);

    var quarantine = try std.json.parseFromSlice(QuarantineUserActionMetadata, std.testing.allocator,
        \\{}
    , .{ .ignore_unknown_fields = true });
    defer quarantine.deinit();

    var widget = try std.json.parseFromSlice(WidgetActivity, std.testing.allocator,
        \\{"name":"Spotify"}
    , .{ .ignore_unknown_fields = true });
    defer widget.deinit();
    try std.testing.expectEqualStrings("Spotify", widget.value.name);
}

test "unknown inbound enum values are retained" {
    var parsed = try std.json.parseFromSlice(InboundActivityActionTypes, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?ActivityActionTypes, null), parsed.value.known());
    try std.testing.expectEqual(@as(i64, 99), parsed.value.raw.integer);

    var provider = try std.json.parseFromSlice(InboundConnectedAccountProviders, std.testing.allocator, "\"future\"", .{});
    defer provider.deinit();
    try std.testing.expectEqual(@as(?ConnectedAccountProviders, null), provider.value.known());
    try std.testing.expectEqualStrings("future", provider.value.raw);
}

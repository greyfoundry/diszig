//! Users wire contracts, dependency layer 0, batch 1.
//!
//! These models come from the pinned OpenAPI schema. Several are wire-only or
//! automation/audit support types; they are exposed as source-level types with
//! no endpoint claim. Integer/string enums have tolerant inbound wrappers.

const std = @import("std");
const json = @import("../json.zig");
const shared = @import("shared.zig");

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
    InvalidActionType,
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

pub const QuarantineUserAction = struct {
    type: shared.AutomodActionType,
    metadata: ?QuarantineUserActionMetadata = null,

    pub fn validate(self: QuarantineUserAction) Error!void {
        if (self.type != .quarantine_user) return error.InvalidActionType;
    }
};

pub const QuarantineUserActionResponse = struct {
    type: shared.AutomodActionType,
    metadata: QuarantineUserActionMetadataResponse,

    pub fn validate(self: QuarantineUserActionResponse) Error!void {
        if (self.type != .quarantine_user) return error.InvalidActionType;
    }
};

pub const UserCommunicationDisabledAction = struct {
    type: shared.AutomodActionType,
    metadata: UserCommunicationDisabledActionMetadata,

    pub fn validate(self: UserCommunicationDisabledAction) Error!void {
        if (self.type != .user_communication_disabled) return error.InvalidActionType;
        try self.metadata.validate();
    }
};

pub const UserCommunicationDisabledActionResponse = struct {
    type: shared.AutomodActionType,
    metadata: UserCommunicationDisabledActionMetadataResponse,

    pub fn validate(self: UserCommunicationDisabledActionResponse) Error!void {
        if (self.type != .user_communication_disabled) return error.InvalidActionType;
    }
};

/// Status of a bulk target-users job. Timestamps stay as documented ISO8601
/// strings in this batch; callers parse them with `protocol.Timestamp`.
pub const TargetUsersJobStatusResponse = struct {
    status: TargetUsersJobStatusTypes,
    total_users: shared.UInt32Type,
    processed_users: shared.UInt32Type,
    created_at: ?[]const u8,
    completed_at: ?[]const u8,
    error_message: ?[]const u8,
};

pub const UserAvatarDecorationResponse = struct {
    asset: []const u8,
    sku_id: ?shared.SnowflakeType,
};

pub const UserNameplateResponse = struct {
    sku_id: ?shared.SnowflakeType,
    asset: []const u8,
    label: []const u8,
    palette: shared.NameplatePalette,
};

/// Widget member as returned by the unauthenticated widget endpoint. The
/// pinned schema declares `avatar` as JSON null, so it is retained as a raw
/// required value rather than typed as a string that can never arrive.
pub const WidgetMember = struct {
    id: []const u8,
    username: []const u8,
    discriminator: []const u8,
    avatar: std.json.Value,
    status: []const u8,
    avatar_url: []const u8,
    activity: ?WidgetActivity = null,
    deaf: ?bool = null,
    mute: ?bool = null,
    self_deaf: ?bool = null,
    self_mute: ?bool = null,
    suppress: ?bool = null,
    channel_id: ?shared.SnowflakeType = null,

    pub fn validate(self: WidgetMember) Error!void {
        _ = try WidgetUserDiscriminator.parse(self.discriminator);
    }
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

test "automod user actions require their documented type" {
    try (QuarantineUserAction{ .type = .quarantine_user }).validate();
    try std.testing.expectError(
        error.InvalidActionType,
        (QuarantineUserAction{ .type = .block_message }).validate(),
    );
    try std.testing.expectError(
        error.InvalidActionType,
        (QuarantineUserActionResponse{ .type = .flag_to_channel, .metadata = .{} }).validate(),
    );

    try (UserCommunicationDisabledAction{
        .type = .user_communication_disabled,
        .metadata = .{ .duration_seconds = 60 },
    }).validate();
    try std.testing.expectError(
        error.InvalidActionType,
        (UserCommunicationDisabledAction{
            .type = .quarantine_user,
            .metadata = .{},
        }).validate(),
    );
    try std.testing.expectError(
        error.DurationOutOfRange,
        (UserCommunicationDisabledAction{
            .type = .user_communication_disabled,
            .metadata = .{ .duration_seconds = 2_419_201 },
        }).validate(),
    );
}

test "target users job, avatar decoration and nameplate parse" {
    var job = try std.json.parseFromSlice(TargetUsersJobStatusResponse, std.testing.allocator,
        \\{"status":1,"total_users":10,"processed_users":4,"created_at":"2026-01-01T00:00:00+00:00","completed_at":null,"error_message":null}
    , .{ .ignore_unknown_fields = true });
    defer job.deinit();
    try std.testing.expectEqual(TargetUsersJobStatusTypes.processing, job.value.status);
    try std.testing.expectEqual(@as(u32, 10), job.value.total_users);
    try std.testing.expectEqual(@as(?[]const u8, null), job.value.completed_at);

    var decoration = try std.json.parseFromSlice(UserAvatarDecorationResponse, std.testing.allocator,
        \\{"asset":"a_1234","sku_id":null}
    , .{ .ignore_unknown_fields = true });
    defer decoration.deinit();
    try std.testing.expectEqual(@as(?shared.SnowflakeType, null), decoration.value.sku_id);

    var nameplate = try std.json.parseFromSlice(UserNameplateResponse, std.testing.allocator,
        \\{"sku_id":"123","asset":"nameplates/a.png","label":"","palette":"crimson"}
    , .{ .ignore_unknown_fields = true });
    defer nameplate.deinit();
    try std.testing.expectEqual(shared.NameplatePalette.crimson, nameplate.value.palette);
    try std.testing.expect(nameplate.value.sku_id != null);
}

test "widget member parses and validates its discriminator" {
    var member = try std.json.parseFromSlice(WidgetMember, std.testing.allocator,
        \\{"id":"1","username":"widget","discriminator":"0000","avatar":null,"status":"online","avatar_url":"https://cdn/x.png","activity":{"name":"Spotify"},"deaf":false,"mute":false,"channel_id":"2"}
    , .{ .ignore_unknown_fields = true });
    defer member.deinit();
    try member.value.validate();
    try std.testing.expect(member.value.avatar == .null);
    try std.testing.expectEqualStrings("widget", member.value.username);

    var invalid = try std.json.parseFromSlice(WidgetMember, std.testing.allocator,
        \\{"id":"1","username":"widget","discriminator":"0001","avatar":null,"status":"online","avatar_url":"https://cdn/x.png"}
    , .{ .ignore_unknown_fields = true });
    defer invalid.deinit();
    try std.testing.expectError(error.InvalidDiscriminator, invalid.value.validate());
}

//! Guilds wire contracts, dependency layer 0, batch 1.
//!
//! These models come from the pinned OpenAPI schema. Enums have strict outbound
//! types and tolerant inbound wrappers. Request types validate documented
//! bounds; response types preserve required-but-nullable fields with `Presence`.

const std = @import("std");
const json = @import("../json.zig");
const Timestamp = @import("../timestamp.zig").Timestamp;

pub const Error = error{
    MissingRequiredField,
    InvalidDeleteMessageSeconds,
    InvalidDeleteMessageDays,
    InvalidTimestamp,
};

pub const ApplicationIntegrationType = enum(u8) {
    guild_install = 0,
    user_install = 1,
};

pub const InboundApplicationIntegrationType = json.InboundEnum(ApplicationIntegrationType);

pub const AuditLogActionTypes = enum(u16) {
    guild_update = 1,
    channel_create = 10,
    channel_update = 11,
    channel_delete = 12,
    channel_overwrite_create = 13,
    channel_overwrite_update = 14,
    channel_overwrite_delete = 15,
    channel_position_update = 16,
    member_kick = 20,
    member_prune = 21,
    member_ban_add = 22,
    member_ban_remove = 23,
    member_update = 24,
    member_role_update = 25,
    member_move = 26,
    member_disconnect = 27,
    bot_add = 28,
    role_create = 30,
    role_update = 31,
    role_delete = 32,
    role_position_update = 33,
    invite_create = 40,
    invite_update = 41,
    invite_delete = 42,
    webhook_create = 50,
    webhook_update = 51,
    webhook_delete = 52,
    emoji_create = 60,
    emoji_update = 61,
    emoji_delete = 62,
    message_delete = 72,
    message_bulk_delete = 73,
    message_pin = 74,
    message_unpin = 75,
    integration_create = 80,
    integration_update = 81,
    integration_delete = 82,
    stage_instance_create = 83,
    stage_instance_update = 84,
    stage_instance_delete = 85,
    sticker_create = 90,
    sticker_update = 91,
    sticker_delete = 92,
    guild_scheduled_event_create = 100,
    guild_scheduled_event_update = 101,
    guild_scheduled_event_delete = 102,
    thread_create = 110,
    thread_update = 111,
    thread_delete = 112,
    application_command_permission_update = 121,
    soundboard_sound_create = 130,
    soundboard_sound_update = 131,
    soundboard_sound_delete = 132,
    auto_moderation_rule_create = 140,
    auto_moderation_rule_update = 141,
    auto_moderation_rule_delete = 142,
    auto_moderation_block_message = 143,
    auto_moderation_flag_to_channel = 144,
    auto_moderation_user_comm_disabled = 145,
    auto_moderation_quarantine_user = 146,
    creator_monetization_request_created = 150,
    creator_monetization_terms_accepted = 151,
    onboarding_prompt_create = 163,
    onboarding_prompt_update = 164,
    onboarding_prompt_delete = 165,
    onboarding_create = 166,
    onboarding_update = 167,
    guild_home_feature_item = 171,
    guild_home_remove_item = 172,
    harmful_links_blocked_message = 180,
    home_settings_create = 190,
    home_settings_update = 191,
    voice_channel_status_create = 192,
    voice_channel_status_delete = 193,
    guild_scheduled_event_exception_create = 200,
    guild_scheduled_event_exception_update = 201,
    guild_scheduled_event_exception_delete = 202,
    guild_profile_update = 211,
};

pub const InboundAuditLogActionTypes = json.InboundEnum(AuditLogActionTypes);

pub const GuildExplicitContentFilterTypes = enum(u8) {
    disabled = 0,
    members_without_roles = 1,
    all_members = 2,
};

pub const InboundGuildExplicitContentFilterTypes = json.InboundEnum(GuildExplicitContentFilterTypes);

pub const GuildFeatures = enum {
    ANIMATED_BANNER,
    ANIMATED_ICON,
    application_command_permissions_v2,
    AUTO_MODERATION,
    BANNER,
    COMMUNITY,
    CREATOR_MONETIZABLE_PROVISIONAL,
    CREATOR_STORE_PAGE,
    DEVELOPER_SUPPORT_SERVER,
    DISCOVERABLE,
    FEATURABLE,
    INVITES_DISABLED,
    INVITE_SPLASH,
    MEMBER_VERIFICATION_GATE_ENABLED,
    MORE_STICKERS,
    NEWS,
    PARTNERED,
    PREVIEW_ENABLED,
    RAID_ALERTS_DISABLED,
    PRUNE_REQUIRES_ADMIN,
    ROLE_ICONS,
    ROLE_SUBSCRIPTIONS_AVAILABLE_FOR_PURCHASE,
    ROLE_SUBSCRIPTIONS_ENABLED,
    TICKETED_EVENTS_ENABLED,
    VANITY_URL,
    VERIFIED,
    VIP_REGIONS,
    WELCOME_SCREEN_ENABLED,
    OFFICIAL_GAME_GUILD,
};

pub const InboundGuildFeatures = json.InboundStringEnum(GuildFeatures);

pub const GuildJoinRequestApplicationStatus = enum {
    STARTED,
    SUBMITTED,
    REJECTED,
    APPROVED,
};

pub const InboundGuildJoinRequestApplicationStatus = json.InboundStringEnum(GuildJoinRequestApplicationStatus);

pub const GuildMFALevel = enum(u8) {
    none = 0,
    elevated = 1,
};

pub const InboundGuildMFALevel = json.InboundEnum(GuildMFALevel);

pub const GuildMemberVerificationFormFieldType = enum {
    TERMS,
    TEXT_INPUT,
    PARAGRAPH,
    MULTIPLE_CHOICE,
};

pub const InboundGuildMemberVerificationFormFieldType = json.InboundStringEnum(GuildMemberVerificationFormFieldType);

pub const GuildNSFWContentLevel = enum(u8) {
    default = 0,
    explicit = 1,
    safe = 2,
    age_restricted = 3,
};

pub const InboundGuildNSFWContentLevel = json.InboundEnum(GuildNSFWContentLevel);

pub const GuildOnboardingMode = enum(u8) {
    onboarding_default = 0,
    onboarding_advanced = 1,
};

pub const InboundGuildOnboardingMode = json.InboundEnum(GuildOnboardingMode);

pub const GuildScheduledEventEntityTypes = enum(u8) {
    none = 0,
    stage_instance = 1,
    voice = 2,
    external = 3,
};

pub const InboundGuildScheduledEventEntityTypes = json.InboundEnum(GuildScheduledEventEntityTypes);

pub const GuildScheduledEventPrivacyLevels = enum(u8) {
    guild_only = 2,
};

pub const InboundGuildScheduledEventPrivacyLevels = json.InboundEnum(GuildScheduledEventPrivacyLevels);

pub const GuildScheduledEventStatuses = enum(u8) {
    scheduled = 1,
    active = 2,
    completed = 3,
    canceled = 4,
};

pub const InboundGuildScheduledEventStatuses = json.InboundEnum(GuildScheduledEventStatuses);

pub const GuildScheduledEventUserResponses = enum(u8) {
    uninterested = 0,
    interested = 1,
};

pub const InboundGuildScheduledEventUserResponses = json.InboundEnum(GuildScheduledEventUserResponses);

pub const IntegrationExpireBehaviorTypes = enum(u8) {
    remove_role = 0,
    kick = 1,
};

pub const InboundIntegrationExpireBehaviorTypes = json.InboundEnum(IntegrationExpireBehaviorTypes);

pub const ApplicationUserRoleConnectionResponse = struct {
    platform_name: []const u8,
    platform_username: json.Presence([]const u8) = .absent,
    /// `additionalProperties: string`; retained raw for batch 1.
    metadata: ?std.json.Value = null,
};

pub const AuditLogObjectChangeResponse = struct {
    key: json.Presence([]const u8) = .absent,
    new_value: ?std.json.Value = null,
    old_value: ?std.json.Value = null,

    pub fn validate(self: AuditLogObjectChangeResponse) Error!void {
        if (self.key.isAbsent()) return error.MissingRequiredField;
    }
};

pub const BanUserFromGuildRequest = struct {
    delete_message_seconds: ?i64 = null,
    delete_message_days: ?i64 = null,

    pub fn validate(self: BanUserFromGuildRequest) Error!void {
        if (self.delete_message_seconds) |value| {
            if (value < 0 or value > 604_800) return error.InvalidDeleteMessageSeconds;
        }
        if (self.delete_message_days) |value| {
            if (value < 0 or value > 7) return error.InvalidDeleteMessageDays;
        }
    }
};

pub const GuildIncidentActionsRequest = struct {
    invites_disabled_until: ?[]const u8 = null,
    dms_disabled_until: ?[]const u8 = null,

    pub fn validate(self: GuildIncidentActionsRequest) Error!void {
        if (self.invites_disabled_until) |value| {
            _ = Timestamp.parse(value) catch return error.InvalidTimestamp;
        }
        if (self.dms_disabled_until) |value| {
            _ = Timestamp.parse(value) catch return error.InvalidTimestamp;
        }
    }
};

pub const GuildIncidentsDataResponse = struct {
    invites_disabled_until: json.Presence([]const u8) = .absent,
    dms_disabled_until: json.Presence([]const u8) = .absent,

    pub fn validate(self: GuildIncidentsDataResponse) Error!void {
        if (self.invites_disabled_until.isAbsent()) return error.MissingRequiredField;
        if (self.dms_disabled_until.isAbsent()) return error.MissingRequiredField;
    }
};

pub const GuildPruneResponse = struct {
    pruned: json.Presence(i64) = .absent,

    pub fn validate(self: GuildPruneResponse) Error!void {
        if (self.pruned.isAbsent()) return error.MissingRequiredField;
    }
};

pub const GuildRoleColorsResponse = struct {
    primary_color: i64,
    secondary_color: ?i64 = null,
    tertiary_color: ?i64 = null,
};

pub const GuildTemplateRoleColorsResponse = struct {
    primary_color: i64,
    secondary_color: ?i64 = null,
    tertiary_color: ?i64 = null,
};

pub const GuildScheduledEventExceptionCreateRequest = struct {
    scheduled_start_time: ?[]const u8 = null,
    scheduled_end_time: ?[]const u8 = null,
    original_scheduled_start_time: []const u8,
    is_canceled: ?bool = null,

    pub fn validate(self: GuildScheduledEventExceptionCreateRequest) Error!void {
        _ = Timestamp.parse(self.original_scheduled_start_time) catch return error.InvalidTimestamp;
        if (self.scheduled_start_time) |value| {
            _ = Timestamp.parse(value) catch return error.InvalidTimestamp;
        }
        if (self.scheduled_end_time) |value| {
            _ = Timestamp.parse(value) catch return error.InvalidTimestamp;
        }
    }
};

pub const GuildScheduledEventExceptionPatchRequestPartial = struct {
    scheduled_start_time: ?[]const u8 = null,
    scheduled_end_time: ?[]const u8 = null,
    is_canceled: ?bool = null,

    pub fn validate(self: GuildScheduledEventExceptionPatchRequestPartial) Error!void {
        if (self.scheduled_start_time) |value| {
            _ = Timestamp.parse(value) catch return error.InvalidTimestamp;
        }
        if (self.scheduled_end_time) |value| {
            _ = Timestamp.parse(value) catch return error.InvalidTimestamp;
        }
    }
};

test "documented enum values and unknown retention" {
    try std.testing.expectEqual(@as(u16, 211), @backingInt(AuditLogActionTypes.guild_profile_update));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(GuildScheduledEventStatuses.active));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(GuildScheduledEventPrivacyLevels.guild_only));
    try std.testing.expectEqualStrings("OFFICIAL_GAME_GUILD", @tagName(GuildFeatures.OFFICIAL_GAME_GUILD));
    try std.testing.expectEqualStrings("TEXT_INPUT", @tagName(GuildMemberVerificationFormFieldType.TEXT_INPUT));

    var unknown = try std.json.parseFromSlice(InboundAuditLogActionTypes, std.testing.allocator, "9999", .{});
    defer unknown.deinit();
    try std.testing.expectEqual(@as(?AuditLogActionTypes, null), unknown.value.known());
    try std.testing.expectEqual(@as(i64, 9999), unknown.value.raw.integer);
}

test "required nullable response fields are validated" {
    var change = try std.json.parseFromSlice(AuditLogObjectChangeResponse, std.testing.allocator,
        \\{"key":null,"new_value":1}
    , .{ .ignore_unknown_fields = true });
    defer change.deinit();
    try change.value.validate();

    var prune = try std.json.parseFromSlice(GuildPruneResponse, std.testing.allocator,
        \\{"pruned":null}
    , .{ .ignore_unknown_fields = true });
    defer prune.deinit();
    try prune.value.validate();

    var missing = try std.json.parseFromSlice(GuildPruneResponse, std.testing.allocator,
        \\{}
    , .{ .ignore_unknown_fields = true });
    defer missing.deinit();
    try std.testing.expectError(error.MissingRequiredField, missing.value.validate());
}

test "request bounds and timestamps" {
    try (BanUserFromGuildRequest{ .delete_message_seconds = 604_800 }).validate();
    try std.testing.expectError(
        error.InvalidDeleteMessageSeconds,
        (BanUserFromGuildRequest{ .delete_message_seconds = 604_801 }).validate(),
    );
    try std.testing.expectError(
        error.InvalidDeleteMessageDays,
        (BanUserFromGuildRequest{ .delete_message_days = 8 }).validate(),
    );
    try (GuildScheduledEventExceptionCreateRequest{
        .original_scheduled_start_time = "2024-01-01T00:00:00+00:00",
    }).validate();
    try std.testing.expectError(
        error.InvalidTimestamp,
        (GuildScheduledEventExceptionCreateRequest{ .original_scheduled_start_time = "not a time" }).validate(),
    );
}

test "role colors and connection response parse" {
    var colors = try std.json.parseFromSlice(GuildRoleColorsResponse, std.testing.allocator,
        \\{"primary_color":1,"secondary_color":null,"tertiary_color":3}
    , .{ .ignore_unknown_fields = true });
    defer colors.deinit();
    try std.testing.expectEqual(@as(i64, 1), colors.value.primary_color);
    try std.testing.expect(colors.value.secondary_color == null);

    var connection = try std.json.parseFromSlice(ApplicationUserRoleConnectionResponse, std.testing.allocator,
        \\{"platform_name":"steam","platform_username":"user","metadata":{"k":"v"}}
    , .{ .ignore_unknown_fields = true });
    defer connection.deinit();
    try std.testing.expectEqualStrings("steam", connection.value.platform_name);
}

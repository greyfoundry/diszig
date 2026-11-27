//! Guilds model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const guilds = diszig.protocol.models.guilds;

test "every listed schema is exported" {
    _ = guilds.ApplicationIntegrationType;
    _ = guilds.ApplicationUserRoleConnectionResponse;
    _ = guilds.AuditLogActionTypes;
    _ = guilds.AuditLogObjectChangeResponse;
    _ = guilds.BanUserFromGuildRequest;
    _ = guilds.GuildExplicitContentFilterTypes;
    _ = guilds.GuildFeatures;
    _ = guilds.GuildIncidentActionsRequest;
    _ = guilds.GuildIncidentsDataResponse;
    _ = guilds.GuildJoinRequestApplicationStatus;
    _ = guilds.GuildMFALevel;
    _ = guilds.GuildMemberVerificationFormFieldType;
    _ = guilds.GuildNSFWContentLevel;
    _ = guilds.GuildOnboardingMode;
    _ = guilds.GuildPruneResponse;
    _ = guilds.GuildRoleColorsResponse;
    _ = guilds.GuildScheduledEventEntityTypes;
    _ = guilds.GuildScheduledEventExceptionCreateRequest;
    _ = guilds.GuildScheduledEventExceptionPatchRequestPartial;
    _ = guilds.GuildScheduledEventPrivacyLevels;
    _ = guilds.GuildScheduledEventStatuses;
    _ = guilds.GuildScheduledEventUserResponses;
    _ = guilds.GuildTemplateRoleColorsResponse;
    _ = guilds.IntegrationExpireBehaviorTypes;
    _ = guilds.IntegrationExpireGracePeriodTypes;
    _ = guilds.IntegrationTypes;
    _ = guilds.LobbyGuildInviteResponse;
    _ = guilds.OnboardingPromptType;
    _ = guilds.PremiumGuildTiers;
    _ = guilds.RoleColors;
    _ = guilds.TeamMemberRoles;
    _ = guilds.UnbanUserFromGuildRequest;
    _ = guilds.UpdateApplicationUserRoleConnectionRequest;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 0), @backingInt(guilds.ApplicationIntegrationType.guild_install));
    try std.testing.expectEqual(@as(u16, 211), @backingInt(guilds.AuditLogActionTypes.guild_profile_update));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(guilds.GuildExplicitContentFilterTypes.all_members));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(guilds.GuildMFALevel.elevated));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(guilds.GuildNSFWContentLevel.age_restricted));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(guilds.GuildOnboardingMode.onboarding_advanced));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(guilds.GuildScheduledEventEntityTypes.external));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(guilds.GuildScheduledEventPrivacyLevels.guild_only));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(guilds.GuildScheduledEventStatuses.canceled));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(guilds.GuildScheduledEventUserResponses.interested));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(guilds.IntegrationExpireBehaviorTypes.kick));
    try std.testing.expectEqualStrings("COMMUNITY", @tagName(guilds.GuildFeatures.COMMUNITY));
    try std.testing.expectEqualStrings("TEXT_INPUT", @tagName(guilds.GuildMemberVerificationFormFieldType.TEXT_INPUT));
}

test "unknown inbound enums are retained" {
    var integer = try std.json.parseFromSlice(guilds.InboundGuildNSFWContentLevel, std.testing.allocator, "99", .{});
    defer integer.deinit();
    try std.testing.expectEqual(@as(?guilds.GuildNSFWContentLevel, null), integer.value.known());

    var string = try std.json.parseFromSlice(guilds.InboundGuildFeatures, std.testing.allocator, "\"FUTURE_FEATURE\"", .{});
    defer string.deinit();
    try std.testing.expectEqual(@as(?guilds.GuildFeatures, null), string.value.known());
    try std.testing.expectEqualStrings("FUTURE_FEATURE", string.value.raw);
}

test "required nullable response fields are validated" {
    var change = try std.json.parseFromSlice(guilds.AuditLogObjectChangeResponse, std.testing.allocator,
        \\{"key":null}
    , .{ .ignore_unknown_fields = true });
    defer change.deinit();
    try change.value.validate();

    var incidents = try std.json.parseFromSlice(guilds.GuildIncidentsDataResponse, std.testing.allocator,
        \\{"invites_disabled_until":"2024-01-01T00:00:00+00:00","dms_disabled_until":null}
    , .{ .ignore_unknown_fields = true });
    defer incidents.deinit();
    try incidents.value.validate();

    var missing = try std.json.parseFromSlice(guilds.GuildIncidentsDataResponse, std.testing.allocator,
        \\{}
    , .{ .ignore_unknown_fields = true });
    defer missing.deinit();
    try std.testing.expectError(error.MissingRequiredField, missing.value.validate());
}

test "request bounds and timestamps" {
    try (guilds.BanUserFromGuildRequest{ .delete_message_seconds = 604_800 }).validate();
    try std.testing.expectError(
        error.InvalidDeleteMessageSeconds,
        (guilds.BanUserFromGuildRequest{ .delete_message_seconds = 604_801 }).validate(),
    );
    try std.testing.expectError(
        error.InvalidDeleteMessageDays,
        (guilds.BanUserFromGuildRequest{ .delete_message_days = 8 }).validate(),
    );
    try (guilds.GuildScheduledEventExceptionCreateRequest{
        .original_scheduled_start_time = "2024-01-01T00:00:00+00:00",
        .scheduled_start_time = "2024-01-02T00:00:00+00:00",
    }).validate();
    try std.testing.expectError(
        error.InvalidTimestamp,
        (guilds.GuildScheduledEventExceptionCreateRequest{ .original_scheduled_start_time = "bad" }).validate(),
    );
}

fn parseChange(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value = try std.json.parseFromSliceLeaky(guilds.AuditLogObjectChangeResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
    try value.validate();
}

test "allocation failure while parsing owned change fields is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseChange,
        .{"{\"key\":\"name\",\"new_value\":\"x\",\"old_value\":\"y\"}"},
    );
}

test "guild batch 2 exports validate" {
    try std.testing.expectEqual(@as(u8, 14), @backingInt(guilds.IntegrationExpireGracePeriodTypes.fourteen_days));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(guilds.OnboardingPromptType.dropdown));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(guilds.PremiumGuildTiers.tier_2));
    try std.testing.expectEqual(guilds.IntegrationTypes.discord, guilds.IntegrationTypes.parseWire("discord").?);
    try std.testing.expectEqual(guilds.TeamMemberRoles.developer, guilds.TeamMemberRoles.parseWire("developer").?);

    try (guilds.RoleColors{ .primary_color = guilds.max_role_color }).validate();
    try std.testing.expectError(
        error.InvalidColor,
        (guilds.RoleColors{ .secondary_color = guilds.max_role_color + 1 }).validate(),
    );

    var invite = try std.json.parseFromSlice(guilds.LobbyGuildInviteResponse, std.testing.allocator,
        \\{"code":"abc"}
    , .{ .ignore_unknown_fields = true });
    defer invite.deinit();
    try std.testing.expectEqualStrings("abc", invite.value.code);

    try (guilds.UpdateApplicationUserRoleConnectionRequest{
        .platform_name = "steam",
        .platform_username = "player",
    }).validate();
}

fn parseRoleConnection(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value = try std.json.parseFromSliceLeaky(guilds.UpdateApplicationUserRoleConnectionRequest, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
    try value.validate();
}

test "allocation failure while parsing role connection metadata is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseRoleConnection,
        .{"{\"platform_name\":\"steam\",\"platform_username\":\"player\",\"metadata\":{\"a\":\"1\",\"b\":\"2\"}}"},
    );
}

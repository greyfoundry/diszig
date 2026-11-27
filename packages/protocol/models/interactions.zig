//! Interactions wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;
const monetization = @import("monetization.zig");

pub const Error = error{
    InvalidCallbackType,
    IneligibleReasonTooLong,
};

pub const ActivityInstanceCallbackResponse = struct {
    id: []const u8,
};

pub const InteractionCallbackTypes = enum(u8) {
    pong = 1,
    channel_message_with_source = 4,
    deferred_channel_message_with_source = 5,
    deferred_update_message = 6,
    update_message = 7,
    application_command_autocomplete_result = 8,
    modal = 9,
    launch_activity = 12,
    social_layer_sku_purchase_eligibility = 13,
};

pub const InboundInteractionCallbackTypes = json.InboundEnum(InteractionCallbackTypes);

pub const InteractionContextType = enum(u8) {
    guild = 0,
    bot_dm = 1,
    private_channel = 2,
};

pub const InboundInteractionContextType = json.InboundEnum(InteractionContextType);

pub const InteractionTypes = enum(u8) {
    ping = 1,
    application_command = 2,
    message_component = 3,
    application_command_autocomplete = 4,
    modal_submit = 5,
    social_layer_sku_purchase_eligibility = 6,
};

pub const InboundInteractionTypes = json.InboundEnum(InteractionTypes);

pub const InteractionResponse = struct {
    id: Snowflake,
    type: InteractionTypes,
    activity_instance_id: ?[]const u8 = null,
    response_message_id: ?Snowflake = null,
    response_message_loading: ?bool = null,
    response_message_ephemeral: ?bool = null,
    channel_id: ?Snowflake = null,
    guild_id: ?Snowflake = null,
};

pub const LaunchActivityInteractionCallbackRequest = struct {
    type: InteractionCallbackTypes,

    pub fn validate(self: LaunchActivityInteractionCallbackRequest) Error!void {
        if (self.type != .launch_activity) return error.InvalidCallbackType;
    }
};

pub const LaunchActivityInteractionCallbackResponse = struct {
    type: InteractionCallbackTypes,
    activity_instance: ActivityInstanceCallbackResponse,

    pub fn validate(self: LaunchActivityInteractionCallbackResponse) Error!void {
        if (self.type != .launch_activity) return error.InvalidCallbackType;
    }
};

pub const PongInteractionCallbackRequest = struct {
    type: InteractionCallbackTypes,

    pub fn validate(self: PongInteractionCallbackRequest) Error!void {
        if (self.type != .pong) return error.InvalidCallbackType;
    }
};

pub const SocialLayerSKUPurchaseEligibilityCallbackData = struct {
    eligible: bool,
    ineligible_reason: ?monetization.SKUIneligibilityReason = null,
    ineligible_reason_description: ?[]const u8 = null,

    pub fn validate(self: SocialLayerSKUPurchaseEligibilityCallbackData) Error!void {
        if (self.ineligible_reason_description) |description| {
            if (description.len > 255) return error.IneligibleReasonTooLong;
        }
    }
};

test "interaction enum values" {
    try std.testing.expectEqual(@as(u8, 13), @backingInt(InteractionCallbackTypes.social_layer_sku_purchase_eligibility));
    try std.testing.expectEqual(@as(u8, 5), @backingInt(InteractionContextType.private_channel));
    try std.testing.expectEqual(@as(u8, 6), @backingInt(InteractionTypes.social_layer_sku_purchase_eligibility));
}

test "unknown inbound interaction enum is retained" {
    var parsed = try std.json.parseFromSlice(InboundInteractionTypes, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?InteractionTypes, null), parsed.value.known());
    try std.testing.expectEqual(@as(i64, 99), parsed.value.raw.integer);
}

test "interaction response and callback requests parse" {
    var response = try std.json.parseFromSlice(InteractionResponse, std.testing.allocator,
        \\{"id":"1","type":2,"response_message_id":"2","response_message_loading":false,"channel_id":"3"}
    , .{ .ignore_unknown_fields = true });
    defer response.deinit();
    try std.testing.expect(response.value.response_message_id != null);
    try std.testing.expectEqual(@as(?Snowflake, null), response.value.guild_id);

    try (LaunchActivityInteractionCallbackRequest{ .type = .launch_activity }).validate();
    try std.testing.expectError(
        error.InvalidCallbackType,
        (LaunchActivityInteractionCallbackRequest{ .type = .pong }).validate(),
    );
    try (PongInteractionCallbackRequest{ .type = .pong }).validate();
    try std.testing.expectError(
        error.InvalidCallbackType,
        (PongInteractionCallbackRequest{ .type = .modal }).validate(),
    );

    var launch = try std.json.parseFromSlice(LaunchActivityInteractionCallbackResponse, std.testing.allocator,
        \\{"type":12,"activity_instance":{"id":"instance"}}
    , .{ .ignore_unknown_fields = true });
    defer launch.deinit();
    try launch.value.validate();
    try std.testing.expectEqualStrings("instance", launch.value.activity_instance.id);
}

test "sku eligibility callback data validates its description" {
    try (SocialLayerSKUPurchaseEligibilityCallbackData{
        .eligible = false,
        .ineligible_reason = .owns_sku_or_bundle_component,
        .ineligible_reason_description = "already owned",
    }).validate();
    const long_text: [256]u8 = @splat('x');
    try std.testing.expectError(
        error.IneligibleReasonTooLong,
        (SocialLayerSKUPurchaseEligibilityCallbackData{
            .eligible = false,
            .ineligible_reason_description = &long_text,
        }).validate(),
    );

    var parsed = try std.json.parseFromSlice(SocialLayerSKUPurchaseEligibilityCallbackData, std.testing.allocator,
        \\{"eligible":true}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try parsed.value.validate();
    try std.testing.expectEqual(@as(?monetization.SKUIneligibilityReason, null), parsed.value.ineligible_reason);
}

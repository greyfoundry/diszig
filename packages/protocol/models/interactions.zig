//! Interactions wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

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

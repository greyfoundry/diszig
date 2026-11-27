//! Interactions model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const interactions = diszig.protocol.models.interactions;

test "every listed schema is exported" {
    _ = interactions.ActivityInstanceCallbackResponse;
    _ = interactions.InteractionCallbackTypes;
    _ = interactions.InteractionContextType;
    _ = interactions.InteractionTypes;
    _ = interactions.InteractionResponse;
    _ = interactions.LaunchActivityInteractionCallbackRequest;
    _ = interactions.LaunchActivityInteractionCallbackResponse;
    _ = interactions.PongInteractionCallbackRequest;
    _ = interactions.SocialLayerSKUPurchaseEligibilityCallbackData;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(interactions.InteractionCallbackTypes.pong));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(interactions.InteractionCallbackTypes.channel_message_with_source));
    try std.testing.expectEqual(@as(u8, 9), @backingInt(interactions.InteractionCallbackTypes.modal));
    try std.testing.expectEqual(@as(u8, 12), @backingInt(interactions.InteractionCallbackTypes.launch_activity));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(interactions.InteractionContextType.guild));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(interactions.InteractionContextType.private_channel));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(interactions.InteractionTypes.ping));
    try std.testing.expectEqual(@as(u8, 5), @backingInt(interactions.InteractionTypes.modal_submit));
}

test "activity callback response requires an id" {
    var parsed = try std.json.parseFromSlice(interactions.ActivityInstanceCallbackResponse, std.testing.allocator,
        \\{"id":"abc"}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("abc", parsed.value.id);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(interactions.ActivityInstanceCallbackResponse, std.testing.allocator, "{}", .{}),
    );
}

test "unknown inbound interaction enums are retained" {
    var callback = try std.json.parseFromSlice(interactions.InboundInteractionCallbackTypes, std.testing.allocator, "99", .{});
    defer callback.deinit();
    try std.testing.expectEqual(@as(?interactions.InteractionCallbackTypes, null), callback.value.known());

    var context = try std.json.parseFromSlice(interactions.InboundInteractionContextType, std.testing.allocator, "99", .{});
    defer context.deinit();
    try std.testing.expectEqual(@as(?interactions.InteractionContextType, null), context.value.known());
}

fn parseResponse(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try std.json.parseFromSliceLeaky(interactions.ActivityInstanceCallbackResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
}

test "allocation failure while parsing callback id is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseResponse,
        .{"{\"id\":\"abc\"}"},
    );
}

test "callback type gates and sku eligibility data" {
    try (interactions.LaunchActivityInteractionCallbackRequest{ .type = .launch_activity }).validate();
    try std.testing.expectError(
        error.InvalidCallbackType,
        (interactions.PongInteractionCallbackRequest{ .type = .launch_activity }).validate(),
    );
    try (interactions.SocialLayerSKUPurchaseEligibilityCallbackData{ .eligible = true }).validate();
    const long_text: [256]u8 = @splat('x');
    try std.testing.expectError(
        error.IneligibleReasonTooLong,
        (interactions.SocialLayerSKUPurchaseEligibilityCallbackData{
            .eligible = false,
            .ineligible_reason_description = &long_text,
        }).validate(),
    );
}

fn parseEligibility(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value = try std.json.parseFromSliceLeaky(interactions.SocialLayerSKUPurchaseEligibilityCallbackData, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
    try value.validate();
}

test "allocation failure while parsing eligibility is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseEligibility,
        .{"{\"eligible\":false,\"ineligible_reason_description\":\"already owned\"}"},
    );
}

//! Monetization model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const monetization = diszig.protocol.models.monetization;

test "every listed schema is exported" {
    _ = monetization.EntitlementOwnerTypes;
    _ = monetization.EntitlementTenantFulfillmentStatusResponse;
    _ = monetization.EntitlementTypes;
    _ = monetization.PremiumTypes;
    _ = monetization.SKUIneligibilityReason;
    _ = monetization.SubscriptionResponseStatusType;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(monetization.EntitlementOwnerTypes.guild));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(monetization.EntitlementOwnerTypes.user));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(monetization.EntitlementTenantFulfillmentStatusResponse.unknown));
    try std.testing.expectEqual(@as(u8, 7), @backingInt(monetization.EntitlementTenantFulfillmentStatusResponse.unfulfillment_failed));
    try std.testing.expectEqual(@as(u8, 8), @backingInt(monetization.EntitlementTypes.application_subscription));
    try std.testing.expectEqual(@as(u8, 10), @backingInt(monetization.EntitlementTypes.quest_reward));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(monetization.PremiumTypes.none));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(monetization.PremiumTypes.tier_0));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(monetization.SKUIneligibilityReason.owns_sku_or_bundle_component));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(monetization.SubscriptionResponseStatusType.ending));
}

test "unknown inbound monetization enums are retained" {
    var owner = try std.json.parseFromSlice(monetization.InboundEntitlementOwnerTypes, std.testing.allocator, "99", .{});
    defer owner.deinit();
    try std.testing.expectEqual(@as(?monetization.EntitlementOwnerTypes, null), owner.value.known());

    var status = try std.json.parseFromSlice(monetization.InboundSubscriptionResponseStatusType, std.testing.allocator, "99", .{});
    defer status.deinit();
    try std.testing.expectEqual(@as(?monetization.SubscriptionResponseStatusType, null), status.value.known());
}

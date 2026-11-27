//! Monetization wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

pub const EntitlementOwnerTypes = enum(u8) {
    guild = 1,
    user = 2,
};

pub const InboundEntitlementOwnerTypes = json.InboundEnum(EntitlementOwnerTypes);

pub const EntitlementTenantFulfillmentStatusResponse = enum(u8) {
    unknown = 0,
    fulfillment_not_needed = 1,
    fulfillment_needed = 2,
    fulfilled = 3,
    fulfillment_failed = 4,
    unfulfillment_needed = 5,
    unfulfilled = 6,
    unfulfillment_failed = 7,
};

pub const InboundEntitlementTenantFulfillmentStatusResponse = json.InboundEnum(EntitlementTenantFulfillmentStatusResponse);

pub const EntitlementTypes = enum(u8) {
    application_subscription = 8,
    quest_reward = 10,
};

pub const InboundEntitlementTypes = json.InboundEnum(EntitlementTypes);

pub const PremiumTypes = enum(u8) {
    none = 0,
    tier_1 = 1,
    tier_2 = 2,
    tier_0 = 3,
};

pub const InboundPremiumTypes = json.InboundEnum(PremiumTypes);

pub const SKUIneligibilityReason = enum(u8) {
    other = 0,
    owns_sku_or_bundle_component = 1,
    platform_restriction = 2,
};

pub const InboundSKUIneligibilityReason = json.InboundEnum(SKUIneligibilityReason);

pub const SubscriptionResponseStatusType = enum(u8) {
    active = 0,
    inactive = 1,
    ending = 2,
};

pub const InboundSubscriptionResponseStatusType = json.InboundEnum(SubscriptionResponseStatusType);

test "monetization enum values" {
    try std.testing.expectEqual(@as(u8, 2), @backingInt(EntitlementOwnerTypes.user));
    try std.testing.expectEqual(@as(u8, 7), @backingInt(EntitlementTenantFulfillmentStatusResponse.unfulfillment_failed));
    try std.testing.expectEqual(@as(u8, 10), @backingInt(EntitlementTypes.quest_reward));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(PremiumTypes.tier_0));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(SKUIneligibilityReason.platform_restriction));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(SubscriptionResponseStatusType.ending));
}

test "unknown inbound monetization enum is retained" {
    var parsed = try std.json.parseFromSlice(InboundEntitlementTypes, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?EntitlementTypes, null), parsed.value.known());
    try std.testing.expectEqual(@as(i64, 99), parsed.value.raw.integer);
}

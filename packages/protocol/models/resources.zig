//! Resources wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

pub const Error = error{
    InvalidMaxAge,
};

pub const CreateGroupDMInviteRequest = struct {
    /// Null means never expire.
    max_age: ?i64 = null,

    pub fn validate(self: CreateGroupDMInviteRequest) Error!void {
        if (self.max_age) |seconds| {
            if (seconds < 1 or seconds > 2_592_000) return error.InvalidMaxAge;
        }
    }
};

pub const InviteTargetTypes = enum(u8) {
    stream = 1,
    embedded_application = 2,
    role_subscriptions_purchase = 3,
};

pub const InboundInviteTargetTypes = json.InboundEnum(InviteTargetTypes);

pub const InviteTypes = enum(u8) {
    guild = 0,
    group_dm = 1,
    friend = 2,
};

pub const InboundInviteTypes = json.InboundEnum(InviteTypes);

pub const ScheduledEventUserCountResponse = struct {
    guild_scheduled_event_count: i32,
    /// Map of exception id to subscribed user count. The key set is open ended,
    /// so the raw JSON object is retained rather than flattened into a list.
    guild_scheduled_event_exception_counts: std.json.Value,
};

pub const StickerFormatTypes = enum(u8) {
    png = 1,
    apng = 2,
    lottie = 3,
    gif = 4,
};

pub const InboundStickerFormatTypes = json.InboundEnum(StickerFormatTypes);

pub const StickerTypes = enum(u8) {
    standard = 1,
    guild = 2,
};

pub const InboundStickerTypes = json.InboundEnum(StickerTypes);

test "resource enum values" {
    try std.testing.expectEqual(@as(u8, 3), @backingInt(InviteTargetTypes.role_subscriptions_purchase));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(InviteTypes.friend));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(StickerFormatTypes.gif));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(StickerTypes.guild));
}

test "group DM invite max age bounds" {
    try (CreateGroupDMInviteRequest{}).validate();
    try (CreateGroupDMInviteRequest{ .max_age = 1 }).validate();
    try (CreateGroupDMInviteRequest{ .max_age = 2_592_000 }).validate();
    try std.testing.expectError(error.InvalidMaxAge, (CreateGroupDMInviteRequest{ .max_age = 0 }).validate());
    try std.testing.expectError(error.InvalidMaxAge, (CreateGroupDMInviteRequest{ .max_age = 2_592_001 }).validate());
}

test "unknown inbound resource enum is retained" {
    var parsed = try std.json.parseFromSlice(InboundStickerFormatTypes, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?StickerFormatTypes, null), parsed.value.known());
    try std.testing.expectEqual(@as(i64, 99), parsed.value.raw.integer);
}

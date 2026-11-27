//! Voice Control wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

/// Target metadata for a stage-instance entity. The pinned schema defines no
/// properties, so the struct is a marker with room for additive fields later.
pub const EntityMetadataStageInstance = struct {};

/// Response variant of `EntityMetadataStageInstance`; also currently empty.
pub const EntityMetadataStageInstanceResponse = struct {};

/// Target metadata for a voice entity. The pinned schema defines no properties.
pub const EntityMetadataVoice = struct {};

/// Response variant of `EntityMetadataVoice`; also currently empty.
pub const EntityMetadataVoiceResponse = struct {};

pub const StageInstancesPrivacyLevels = enum(u8) {
    /// Public is retained for compatibility but is deprecated by Discord.
    public = 1,
    guild_only = 2,
};

pub const InboundStageInstancesPrivacyLevels = json.InboundEnum(StageInstancesPrivacyLevels);

pub const VoiceRegionResponse = struct {
    id: []const u8,
    name: []const u8,
    custom: bool,
    deprecated: bool,
    optimal: bool,
};

test "voice control enum values" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(StageInstancesPrivacyLevels.public));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(StageInstancesPrivacyLevels.guild_only));
}

test "voice region requires every documented field" {
    var parsed = try std.json.parseFromSlice(VoiceRegionResponse, std.testing.allocator,
        \\{"id":"us-east","name":"US East","custom":false,"deprecated":false,"optimal":true}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("us-east", parsed.value.id);
    try std.testing.expect(parsed.value.optimal);
    try std.testing.expect(!parsed.value.custom);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(VoiceRegionResponse, std.testing.allocator,
            \\{"id":"us-east","name":"US East","custom":false,"deprecated":false}
        , .{}),
    );
}

test "unknown inbound privacy level is retained" {
    var parsed = try std.json.parseFromSlice(InboundStageInstancesPrivacyLevels, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?StageInstancesPrivacyLevels, null), parsed.value.known());
    try std.testing.expectEqual(@as(i64, 99), parsed.value.raw.integer);
}

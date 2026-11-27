//! Voice Control model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const voice_control = diszig.protocol.models.voice_control;

test "every listed schema is exported" {
    _ = voice_control.EntityMetadataStageInstance;
    _ = voice_control.EntityMetadataStageInstanceResponse;
    _ = voice_control.EntityMetadataVoice;
    _ = voice_control.EntityMetadataVoiceResponse;
    _ = voice_control.StageInstancesPrivacyLevels;
    _ = voice_control.VoiceRegionResponse;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(voice_control.StageInstancesPrivacyLevels.public));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(voice_control.StageInstancesPrivacyLevels.guild_only));
}

test "voice region parses and requires all fields" {
    var parsed = try std.json.parseFromSlice(voice_control.VoiceRegionResponse, std.testing.allocator,
        \\{"id":"eu-central","name":"EU Central","custom":true,"deprecated":false,"optimal":false}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("EU Central", parsed.value.name);
    try std.testing.expect(parsed.value.custom);
    try std.testing.expect(!parsed.value.deprecated);

    try std.testing.expectError(
        error.MissingField,
        std.json.parseFromSlice(voice_control.VoiceRegionResponse, std.testing.allocator,
            \\{"id":"eu-central","name":"EU Central","custom":true,"deprecated":false}
        , .{}),
    );
}

test "empty entity metadata accepts unknown additive fields" {
    var parsed = try std.json.parseFromSlice(voice_control.EntityMetadataVoice, std.testing.allocator,
        \\{"future_field":1}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    var response = try std.json.parseFromSlice(voice_control.EntityMetadataStageInstanceResponse, std.testing.allocator,
        \\{}
    , .{ .ignore_unknown_fields = true });
    defer response.deinit();
}

test "unknown inbound privacy level is retained" {
    var parsed = try std.json.parseFromSlice(voice_control.InboundStageInstancesPrivacyLevels, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?voice_control.StageInstancesPrivacyLevels, null), parsed.value.known());
}

fn parseRegion(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try std.json.parseFromSliceLeaky(voice_control.VoiceRegionResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
}

test "allocation failure while parsing a voice region is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseRegion,
        .{"{\"id\":\"us-east\",\"name\":\"US East\",\"custom\":false,\"deprecated\":false,\"optimal\":true}"},
    );
}

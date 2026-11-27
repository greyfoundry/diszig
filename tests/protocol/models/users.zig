//! Users model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const users = diszig.protocol.models.users;

test "every listed schema is exported" {
    _ = users.AccountResponse;
    _ = users.ActivityActionTypes;
    _ = users.BotAccountPatchRequest;
    _ = users.ConnectedAccountProviders;
    _ = users.ConnectedAccountVisibility;
    _ = users.GithubUser;
    _ = users.NewMemberActionType;
    _ = users.QuarantineUserActionMetadata;
    _ = users.QuarantineUserActionMetadataResponse;
    _ = users.TargetUsersJobStatusTypes;
    _ = users.TeamMembershipStates;
    _ = users.UserCommunicationDisabledActionMetadata;
    _ = users.UserCommunicationDisabledActionMetadataResponse;
    _ = users.UserNotificationSettings;
    _ = users.UserProfileMetadata;
    _ = users.UserProfileMetadataResponse;
    _ = users.UserProfileMetadata;
    _ = users.WidgetActivity;
    _ = users.WidgetUserDiscriminator;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(users.ActivityActionTypes.join));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(users.ActivityActionTypes.spectate));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(users.ActivityActionTypes.listen));
    try std.testing.expectEqual(@as(u8, 5), @backingInt(users.ActivityActionTypes.join_request));
    try std.testing.expectEqual(@as(u8, 6), @backingInt(users.ActivityActionTypes.stream_request));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(users.NewMemberActionType.view));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(users.NewMemberActionType.talk));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(users.ConnectedAccountVisibility.none));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(users.ConnectedAccountVisibility.everyone));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(users.TargetUsersJobStatusTypes.unspecified));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(users.TargetUsersJobStatusTypes.failed));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(users.TeamMembershipStates.invited));
    try std.testing.expectEqual(@as(u8, 0), @backingInt(users.UserNotificationSettings.all_messages));
    try std.testing.expectEqualStrings("0000", users.WidgetUserDiscriminator.zeroes);
}

test "account response requires name but allows explicit null" {
    var missing = try std.json.parseFromSlice(users.AccountResponse, std.testing.allocator,
        \\{"id":"1"}
    , .{ .ignore_unknown_fields = true });
    defer missing.deinit();
    try std.testing.expectError(error.MissingName, missing.value.validate());

    var null_name = try std.json.parseFromSlice(users.AccountResponse, std.testing.allocator,
        \\{"id":"1","name":null}
    , .{ .ignore_unknown_fields = true });
    defer null_name.deinit();
    try null_name.value.validate();
}

test "request validation fails for omitted or invalid outbound fields" {
    try std.testing.expectError(
        error.InvalidUsername,
        (users.BotAccountPatchRequest{ .username = "" }).validate(),
    );
    try std.testing.expectError(
        error.InvalidUsername,
        (users.BotAccountPatchRequest{ .username = "a" }).validate(),
    );
    try std.testing.expectError(
        error.DurationOutOfRange,
        (users.UserCommunicationDisabledActionMetadata{ .duration_seconds = -1 }).validate(),
    );
    const too_many: [1001][]const u8 = @splat("safe");
    try std.testing.expectError(
        error.TooManyKeywords,
        (users.UserProfileMetadata{ .keyword_filter = &too_many }).validate(),
    );
}

test "profile response parses bounded arrays" {
    const payload =
        \\{"keyword_filter":["a"],"regex_patterns":["b"],"allow_list":["c"]}
    ;
    var parsed = try std.json.parseFromSlice(users.UserProfileMetadataResponse, std.testing.allocator, payload, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    try std.testing.expectEqualStrings("a", parsed.value.keyword_filter[0]);
    try std.testing.expectEqualStrings("c", parsed.value.allow_list[0]);
}

fn parseAccount(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value = try std.json.parseFromSliceLeaky(users.AccountResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
    try value.validate();
}

test "allocation failure while parsing owned fields is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseAccount,
        .{"{\"id\":\"1\",\"name\":\"account\"}"},
    );
}

fn parseProfile(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try std.json.parseFromSliceLeaky(users.UserProfileMetadataResponse, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
}

test "allocation failure across profile arrays is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseProfile,
        .{"{\"keyword_filter\":[\"a\",\"b\"],\"regex_patterns\":[\"r\"],\"allow_list\":[\"x\",\"y\",\"z\"]}"},
    );
}

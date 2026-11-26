//! Application command permission wire models.

const std = @import("std");
const json = @import("../json.zig");
const Snowflake = @import("../snowflake.zig").Snowflake;

pub const PermissionType = enum(u8) {
    role = 1,
    user = 2,
    channel = 3,
};

pub const ApplicationCommandPermission = struct {
    id: Snowflake,
    type: json.InboundEnum(PermissionType),
    permission: bool,
};

/// `APPLICATION_COMMAND_PERMISSIONS_UPDATE` payload. `id` is a command ID or
/// the application ID when the overwrite applies to all commands.
pub const GuildApplicationCommandPermissions = struct {
    id: Snowflake,
    application_id: Snowflake,
    guild_id: Snowflake,
    permissions: []ApplicationCommandPermission,
};

test "permissions parse with unknown type retention" {
    var parsed = try std.json.parseFromSlice(GuildApplicationCommandPermissions, std.testing.allocator,
        \\{"id":"1","application_id":"2","guild_id":"3","permissions":[{"id":"4","type":1,"permission":true},{"id":"5","type":9,"permission":false}]}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();

    try std.testing.expectEqual(@as(usize, 2), parsed.value.permissions.len);
    try std.testing.expectEqual(PermissionType.role, parsed.value.permissions[0].type.known().?);
    try std.testing.expect(parsed.value.permissions[0].permission);
    try std.testing.expectEqual(@as(?PermissionType, null), parsed.value.permissions[1].type.known());
    try std.testing.expectEqual(@as(i64, 9), parsed.value.permissions[1].type.raw.integer);
}

const std = @import("std");
const diszig = @import("diszig");

test "public permission API follows the documented overwrite order" {
    const permissions = diszig.permissions;
    const base = permissions.Permissions.init(permissions.VIEW_CHANNEL | permissions.SEND_MESSAGES);
    const roles = [_]permissions.Overwrite{
        .{ .allow = permissions.Permissions.init(permissions.VIEW_CHANNEL) },
    };
    const member = permissions.Overwrite{
        .deny = permissions.Permissions.init(permissions.SEND_MESSAGES),
    };

    const result = try permissions.compute(base, null, &roles, member, true);
    try std.testing.expect(result.has(permissions.VIEW_CHANNEL));
    try std.testing.expect(!result.has(permissions.SEND_MESSAGES));
}

test "public flags preserve an unknown bit" {
    const Bits = diszig.flags.Flags(u64);
    const parsed = try Bits.parseDecimal("9223372036854775808");
    try std.testing.expect(parsed.has(1 << 63));
}

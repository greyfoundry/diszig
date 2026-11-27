//! Shared event model fragments.
//!
//! `User` is the batch-1 subset needed by guild ban and integration events. The
//! full user resource is MODEL-USERS-* work.

const std = @import("std");
const Snowflake = @import("../snowflake.zig").Snowflake;

/// Permission bitfields arrive as decimal strings.
pub const PermissionBits = struct {
    bits: u64,

    pub fn jsonParse(
        allocator: std.mem.Allocator,
        source: anytype,
        options: std.json.ParseOptions,
    ) !@This() {
        const text = try std.json.innerParse([]const u8, allocator, source, options);
        return .{ .bits = try std.fmt.parseInt(u64, text, 10) };
    }
};

pub const User = struct {
    id: Snowflake,
    username: []const u8,
    discriminator: ?[]const u8 = null,
    global_name: ?[]const u8 = null,
    avatar: ?[]const u8 = null,
    bot: ?bool = null,
    system: ?bool = null,
};

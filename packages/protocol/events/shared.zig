//! Shared event model fragments.
//!
//! `User` is the batch-1 subset needed by guild ban and integration events. The
//! full user resource is MODEL-USERS-* work.

const std = @import("std");
const json = @import("../json.zig");
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

/// Batch-1 guild member. `user` is absent in some message payloads; `deaf`,
/// `mute`, `flags` and `roles` default so partial interaction members parse.
pub const Member = struct {
    user: ?User = null,
    nick: json.Presence([]const u8) = .absent,
    avatar: json.Presence([]const u8) = .absent,
    banner: json.Presence([]const u8) = .absent,
    roles: []Snowflake = &.{},
    joined_at: json.Presence([]const u8) = .absent,
    premium_since: json.Presence([]const u8) = .absent,
    deaf: bool = false,
    mute: bool = false,
    flags: u64 = 0,
    pending: ?bool = null,
    permissions: ?PermissionBits = null,
    communication_disabled_until: json.Presence([]const u8) = .absent,
    avatar_decoration_data: ?std.json.Value = null,
    collectibles: ?std.json.Value = null,
};

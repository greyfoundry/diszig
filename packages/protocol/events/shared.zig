//! Shared event model fragments.
//!
//! `User` is the batch-1 subset needed by guild ban and integration events. The
//! full user resource is MODEL-USERS-* work.

const std = @import("std");
const Snowflake = @import("../snowflake.zig").Snowflake;

pub const User = struct {
    id: Snowflake,
    username: []const u8,
    discriminator: ?[]const u8 = null,
    global_name: ?[]const u8 = null,
    avatar: ?[]const u8 = null,
    bot: ?bool = null,
    system: ?bool = null,
};

//! Shared protocol types and decoding helpers.

const std = @import("std");

pub const cdn = @import("cdn.zig");
pub const errors = @import("errors.zig");
pub const flags = @import("flags.zig");
pub const json = @import("json.zig");
pub const permissions = @import("permissions.zig");
pub const snowflake = @import("snowflake.zig");
pub const timestamp = @import("timestamp.zig");

pub const Snowflake = snowflake.Snowflake;
pub const Timestamp = timestamp.Timestamp;

test {
    std.testing.refAllDecls(@This());
    _ = cdn;
    _ = errors;
    _ = flags;
    _ = json;
    _ = permissions;
    _ = snowflake;
    _ = timestamp;
}

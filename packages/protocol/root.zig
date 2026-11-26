//! Shared protocol types and decoding helpers.

const std = @import("std");

pub const errors = @import("errors.zig");
pub const json = @import("json.zig");
pub const snowflake = @import("snowflake.zig");

pub const Snowflake = snowflake.Snowflake;

test {
    std.testing.refAllDecls(@This());
    _ = errors;
    _ = json;
    _ = snowflake;
}

//! Shared protocol types and decoding helpers.

const std = @import("std");

pub const cdn = @import("cdn.zig");
pub const errors = @import("errors.zig");
pub const flags = @import("flags.zig");
pub const json = @import("json.zig");
pub const models = @import("models/root.zig");
pub const permissions = @import("permissions.zig");
pub const presence = @import("presence.zig");
pub const snowflake = @import("snowflake.zig");
pub const timestamp = @import("timestamp.zig");
pub const intents = @import("intents.zig");
pub const version = @import("version.zig");

pub const Snowflake = snowflake.Snowflake;
pub const Timestamp = timestamp.Timestamp;
pub const ApiVersion = version.ApiVersion;

test {
    std.testing.refAllDecls(@This());
    _ = cdn;
    _ = errors;
    _ = flags;
    _ = json;
    _ = models;
    _ = permissions;
    _ = presence;
    _ = snowflake;
    _ = timestamp;
    _ = version;
}

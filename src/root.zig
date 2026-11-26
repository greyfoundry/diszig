//! Diszig public entrypoint.
//!
//! Only implemented surfaces are exported. REST, Gateway, client and builders
//! are added when their real behaviour exists.

const std = @import("std");
const protocol_mod = @import("protocol");
const rest_mod = @import("rest");
const gateway_mod = @import("gateway");

pub const protocol = protocol_mod;
pub const rest = rest_mod;
pub const gateway = gateway_mod;
pub const Snowflake = protocol.Snowflake;
pub const Timestamp = protocol.Timestamp;
pub const ApiVersion = protocol.ApiVersion;
pub const cdn = protocol.cdn;
pub const errors = protocol.errors;
pub const flags = protocol.flags;
pub const json = protocol.json;
pub const permissions = protocol.permissions;
pub const presence = protocol.presence;

test "root re-exports the protocol snowflake" {
    const id = try Snowflake.parse("18446744073709551615");
    try std.testing.expectEqual(@as(u64, std.math.maxInt(u64)), id.toU64());
}

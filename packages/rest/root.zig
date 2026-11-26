//! REST-layer types. Transport and endpoint modules are added when implemented.

pub const client = @import("client.zig");
pub const errors = @import("errors.zig");
pub const transport = @import("transport.zig");

pub const Client = client.Client;
pub const Auth = client.Auth;
pub const Response = client.Response;

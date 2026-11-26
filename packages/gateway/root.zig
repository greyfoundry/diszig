//! Gateway transport layer.
//!
//! Present: the WebSocket framing boundary, transport compression and URL
//! parsing. Session state, heartbeats, Identify/Resume and dispatch are added
//! by later packages; nothing here claims a working Gateway client.

pub const compression = @import("compression.zig");
pub const heartbeat = @import("heartbeat.zig");
pub const session = @import("session.zig");
pub const transport = @import("transport.zig");

pub const Compression = compression.Mode;
pub const Inflater = compression.Inflater;
pub const Connection = transport.Connection;
pub const Message = transport.Message;
pub const Url = transport.Url;
pub const Heartbeat = heartbeat.Heartbeat;
pub const Session = session.Session;

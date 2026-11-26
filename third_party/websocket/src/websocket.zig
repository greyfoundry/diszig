//! Client-side root for the vendored websocket.zig source.
//!
//! Upstream `src/websocket.zig` also exports the server and calls
//! `std.testing.refAllDecls`, which forces the server, testing helpers and
//! trust fixtures into every consumer. Diszig only uses the client, so this
//! root re-exports exactly that. See `third_party/websocket/VENDOR.md`.

const std = @import("std");

pub const buffer = @import("buffer.zig");

pub const proto = @import("proto.zig");
pub const OpCode = proto.OpCode;
pub const Message = proto.Message;
pub const MessageType = Message.Type;
pub const MessageTextType = Message.TextType;

pub const Client = @import("client/client.zig").Client;

pub const Compression = struct {
    write_threshold: ?usize = null,
    retain_write_buffer: bool = true,
    /// Require the peer to reset its inflater between messages.
    client_no_context_takeover: bool = true,
    /// Reset the server compressor between messages.
    server_no_context_takeover: bool = true,
};

pub fn bufferProvider(allocator: std.mem.Allocator, config: buffer.Config) !buffer.Provider {
    return buffer.Provider.init(allocator, config);
}

pub fn frameText(comptime msg: []const u8) [proto.calculateFrameLen(msg)]u8 {
    return proto.frame(.text, msg);
}

pub fn frameBin(comptime msg: []const u8) [proto.calculateFrameLen(msg)]u8 {
    return proto.frame(.binary, msg);
}

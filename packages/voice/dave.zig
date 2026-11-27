//! Thin C ABI bindings to Discord's official `libdave` (v1.3.0).
//!
//! This module is only compiled by the optional `voice-probe` step with
//! `-Dlibdave-dir=...`; the default build never imports it and links nothing.
//! It is a feasibility and ABI surface, not a voice transport.
//!
//! Ownership: opaque handles returned by libdave must be destroyed with the
//! matching `*Destroy` function exactly once. Buffers returned through output
//! pointers are owned by the caller and must be released with `daveFree`.

const std = @import("std");

pub const c = @import("dave_c");

pub const Error = error{
    NoSupportedProtocolVersion,
    SessionCreateFailed,
    EmptyKeyPackage,
};

pub const max_protocol_version = c.daveMaxSupportedProtocolVersion;

pub fn maxSupportedProtocolVersion() u16 {
    return c.daveMaxSupportedProtocolVersion();
}

/// A session handle with explicit close semantics. No copy is provided so a
/// handle cannot be destroyed twice by accident.
pub const Session = struct {
    handle: c.DAVESessionHandle,

    /// `auth_session_id` may be null. The failure callback is left null in the
    /// probe; production code will attach logging through the C callback.
    pub fn create(auth_session_id: ?[*:0]const u8) Error!Session {
        const handle = c.daveSessionCreate(null, auth_session_id, null, null);
        if (handle == null) return error.SessionCreateFailed;
        return .{ .handle = handle };
    }

    pub fn destroy(self: *Session) void {
        c.daveSessionDestroy(self.handle);
        self.* = undefined;
    }

    pub fn initGroup(self: Session, version: u16, group_id: u64, self_user_id: [*:0]const u8) void {
        c.daveSessionInit(self.handle, version, group_id, self_user_id);
    }

    pub fn protocolVersion(self: Session) u16 {
        return c.daveSessionGetProtocolVersion(self.handle);
    }

    /// Copies the marshalled MLS key package into `allocator` and releases the
    /// libdave buffer. Caller owns the returned slice.
    pub fn keyPackage(self: Session, allocator: std.mem.Allocator) ![]u8 {
        var buffer: [*c]u8 = null;
        var length: usize = 0;
        c.daveSessionGetMarshalledKeyPackage(self.handle, &buffer, &length);
        defer if (buffer != null) c.daveFree(buffer);
        if (length == 0 or buffer == null) return error.EmptyKeyPackage;
        const bytes = @as([*]const u8, @ptrCast(buffer))[0..length];
        return try allocator.dupe(u8, bytes);
    }
};

/// Reads the official ABI probe values without creating a session. A zero
/// protocol version means the linked library does not expose the expected API.
pub fn abiVersion() Error!u16 {
    const version = maxSupportedProtocolVersion();
    if (version == 0) return error.NoSupportedProtocolVersion;
    return version;
}

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
    MlsFailure,
    CommitRejected,
    MissingKeyRatchet,
    EncryptionFailed,
    DecryptionFailed,
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

    pub fn setExternalSender(self: Session, bytes: []const u8) void {
        c.daveSessionSetExternalSender(self.handle, bytes.ptr, bytes.len);
    }

    pub fn addRecognizedUser(self: Session, user_id: [*:0]const u8) void {
        c.daveSessionAddRecognizedUser(self.handle, user_id);
    }

    /// Runs MLS ProcessProposals and returns the commit/welcome bytes owned by
    /// the caller. Empty output means no commit was produced.
    pub fn processProposals(self: Session, allocator: std.mem.Allocator, proposals: []const u8) ![]u8 {
        var buffer: [*c]u8 = null;
        var length: usize = 0;
        c.daveSessionProcessProposals(self.handle, proposals.ptr, proposals.len, &buffer, &length);
        defer if (buffer != null) c.daveFree(buffer);
        if (length == 0 or buffer == null) return try allocator.alloc(u8, 0);
        const bytes = @as([*]const u8, @ptrCast(buffer))[0..length];
        return try allocator.dupe(u8, bytes);
    }

    pub fn processCommit(self: Session, commit: []const u8) Error!void {
        const result = c.daveSessionProcessCommit(self.handle, commit.ptr, commit.len);
        if (result == null) return error.MlsFailure;
        defer c.daveCommitResultDestroy(result);
        if (c.daveCommitResultIsFailed(result)) return error.CommitRejected;
    }

    pub fn processWelcome(self: Session, welcome: []const u8) Error!void {
        const result = c.daveSessionProcessWelcome(self.handle, welcome.ptr, welcome.len);
        if (result == null) return error.MlsFailure;
        c.daveWelcomeResultDestroy(result);
    }

    /// Copies the last epoch authenticator; caller owns the slice.
    pub fn lastEpochAuthenticator(self: Session, allocator: std.mem.Allocator) ![]u8 {
        var buffer: [*c]u8 = null;
        var length: usize = 0;
        c.daveSessionGetLastEpochAuthenticator(self.handle, &buffer, &length);
        defer if (buffer != null) c.daveFree(buffer);
        if (length == 0 or buffer == null) return try allocator.alloc(u8, 0);
        const bytes = @as([*]const u8, @ptrCast(buffer))[0..length];
        return try allocator.dupe(u8, bytes);
    }

    /// Returns an opaque key ratchet owned by the caller (destroy via
    /// `KeyRatchet.deinit`). Null when the user is not in the group.
    pub fn keyRatchet(self: Session, user_id: [*:0]const u8) !KeyRatchet {
        const handle = c.daveSessionGetKeyRatchet(self.handle, user_id);
        if (handle == null) return error.MissingKeyRatchet;
        return .{ .handle = handle };
    }
};

pub const KeyRatchet = struct {
    handle: c.DAVEKeyRatchetHandle,

    pub fn deinit(self: *KeyRatchet) void {
        c.daveKeyRatchetDestroy(self.handle);
        self.* = undefined;
    }
};

pub const Encryptor = struct {
    handle: c.DAVEEncryptorHandle,

    pub fn create() Error!Encryptor {
        const handle = c.daveEncryptorCreate();
        if (handle == null) return error.SessionCreateFailed;
        return .{ .handle = handle };
    }

    pub fn destroy(self: *Encryptor) void {
        c.daveEncryptorDestroy(self.handle);
        self.* = undefined;
    }

    pub fn setPassthrough(self: Encryptor, enabled: bool) void {
        c.daveEncryptorSetPassthroughMode(self.handle, enabled);
    }

    pub fn isPassthrough(self: Encryptor) bool {
        return c.daveEncryptorIsPassthroughMode(self.handle);
    }

    pub fn hasKeyRatchet(self: Encryptor) bool {
        return c.daveEncryptorHasKeyRatchet(self.handle);
    }

    pub fn assignOpusSsrc(self: Encryptor, ssrc: u32) void {
        c.daveEncryptorAssignSsrcToCodec(self.handle, ssrc, c.DAVE_CODEC_OPUS);
    }

    pub fn maxCiphertextSize(self: Encryptor, frame_len: usize) usize {
        return c.daveEncryptorGetMaxCiphertextByteSize(self.handle, c.DAVE_MEDIA_TYPE_AUDIO, frame_len);
    }

    pub fn encrypt(self: Encryptor, out: []u8, ssrc: u32, frame: []const u8) ![]const u8 {
        var written: usize = 0;
        const result = c.daveEncryptorEncrypt(
            self.handle,
            c.DAVE_MEDIA_TYPE_AUDIO,
            ssrc,
            frame.ptr,
            frame.len,
            out.ptr,
            out.len,
            &written,
        );
        if (result != c.DAVE_ENCRYPTOR_RESULT_CODE_SUCCESS) return error.EncryptionFailed;
        return out[0..written];
    }
};

pub const Decryptor = struct {
    handle: c.DAVEDecryptorHandle,

    pub fn create() Error!Decryptor {
        const handle = c.daveDecryptorCreate();
        if (handle == null) return error.SessionCreateFailed;
        return .{ .handle = handle };
    }

    pub fn destroy(self: *Decryptor) void {
        c.daveDecryptorDestroy(self.handle);
        self.* = undefined;
    }

    pub fn setPassthrough(self: Decryptor, enabled: bool) void {
        c.daveDecryptorTransitionToPassthroughMode(self.handle, enabled);
    }

    pub fn decrypt(self: Decryptor, out: []u8, frame: []const u8) ![]const u8 {
        var written: usize = 0;
        const result = c.daveDecryptorDecrypt(
            self.handle,
            c.DAVE_MEDIA_TYPE_AUDIO,
            frame.ptr,
            frame.len,
            out.ptr,
            out.len,
            &written,
        );
        if (result != c.DAVE_DECRYPTOR_RESULT_CODE_SUCCESS) return error.DecryptionFailed;
        return out[0..written];
    }
};

/// Reads the official ABI probe values without creating a session. A zero
/// protocol version means the linked library does not expose the expected API.
pub fn abiVersion() Error!u16 {
    const version = maxSupportedProtocolVersion();
    if (version == 0) return error.NoSupportedProtocolVersion;
    return version;
}

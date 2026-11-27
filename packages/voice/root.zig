//! Optional voice capability report.
//!
//! Voice is not implemented and remains fully separate from REST and basic
//! bots: this module imports no WebSocket, UDP, Opus, libdave or other native
//! dependency, so a build that never references `diszig.voice` links nothing
//! voice-related.
//!
//! Why there is no partial voice path:
//!
//! - Discord documents that E2EE (the DAVE protocol) is the only supported
//!   call mode for all audio from 2026-03-01. A non-DAVE voice client would be
//!   rejected or unusable, so sending audio without DAVE would be a false
//!   claim rather than a useful fallback.
//! - Voice gateway versions below 4 are rejected; version 8 is recommended.
//! - DAVE needs the MLS group state machine and the documented voice opcodes,
//!   not just UDP framing. The official libdave library and an Opus codec would
//!   have to be pinned by content hash and checked per target ABI.
//!
//! A future implementation must add those dependencies with provenance,
//! licence, transitive and ABI review. Until then every entry point reports
//! `error.UnsupportedVoice`; nothing pretends to connect.

const std = @import("std");

pub const Error = error{UnsupportedVoice};

pub const Status = enum {
    /// No voice transport, UDP, codec or DAVE implementation is linked.
    unavailable,
};

pub const status: Status = .unavailable;

pub const ReasonCode = enum {
    /// DAVE is the only documented call mode from 2026-03-01.
    dave_required,
    /// Native libdave/Opus artifacts are not pinned or ABI-reviewed.
    native_dependencies_not_pinned,
    /// No voice WebSocket, UDP or media transport is implemented.
    transport_not_implemented,
};

pub const Reason = struct {
    code: ReasonCode,
    detail: []const u8,
};

pub const reasons = [_]Reason{
    .{
        .code = .dave_required,
        .detail = "Discord documents E2EE/DAVE as the only supported call mode for all audio from 2026-03-01; a non-DAVE path would not be a usable fallback.",
    },
    .{
        .code = .native_dependencies_not_pinned,
        .detail = "libdave and an Opus codec need content-hash pins, licence review, transitive review and per-target ABI checks before linking.",
    },
    .{
        .code = .transport_not_implemented,
        .detail = "No voice WebSocket handshake, UDP discovery, RTP framing or audio pipeline exists.",
    },
};

/// True only when a real, tested voice implementation is linked. It is
/// compile-time constant so callers can gate voice features without a runtime
/// probe or a hidden dependency.
pub fn isAvailable() bool {
    return false;
}

/// The single gate for callers that need voice. Always fails today; the error
/// is explicit rather than a stub connection or silent no-op.
pub fn require() Error!void {
    return error.UnsupportedVoice;
}

/// Wire version a future implementation must request. Kept here so callers and
/// documentation share one value; it is not a claim that the version is used.
pub const documented_gateway_version: u8 = 8;

/// Documented encryption modes; the first is required by current docs.
pub const encryption_modes = [_][]const u8{
    "aead_xchacha20_poly1305_rtpsize",
    "aead_aes256_gcm_rtpsize",
};

test "voice is explicitly unavailable with reasons" {
    try std.testing.expect(!isAvailable());
    try std.testing.expectEqual(Status.unavailable, status);
    try std.testing.expectError(error.UnsupportedVoice, require());
    try std.testing.expect(reasons.len >= 3);
    try std.testing.expectEqual(@as(u8, 8), documented_gateway_version);
    try std.testing.expectEqualStrings("aead_xchacha20_poly1305_rtpsize", encryption_modes[0]);
}

test "reason codes are unique and documented" {
    for (reasons, 0..) |reason, index| {
        try std.testing.expect(reason.detail.len > 0);
        for (reasons[0..index]) |earlier| {
            try std.testing.expect(earlier.code != reason.code);
        }
    }
}

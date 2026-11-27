//! Optional voice capability report.
//!
//! Voice is not implemented and remains fully separate from REST and basic
//! bots: this module imports no WebSocket, UDP, Opus, libdave or other native
//! dependency, so a build that never references `diszig.voice` links nothing
//! voice-related.
//!
//! Why there is no partial voice path:
//!
//! - Discord discontinued legacy non-DAVE voice connections; ordinary calls
//!   require DAVE end-to-end encryption (stage channels are exempt). Voice
//!   itself is supported, not deprecated.
//! - The official libdave C API is the DAVE integration path. `dave.zig`
//!   binds a small ABI subset and the optional `voice-probe` step proves it
//!   links and creates an MLS key package; no voice transport exists yet.
//! - Voice gateway versions below 4 are rejected; version 8 is recommended.
//! - Opus and a shipping libdave integration still need packaging, recovery
//!   tests and per-target verification before voice can be advertised.
//!
//! A future implementation must add those dependencies with provenance,
//! licence, transitive and ABI review. Until then every entry point reports
//! `error.UnsupportedVoice`; nothing pretends to connect.

const std = @import("std");

pub const gateway = @import("gateway.zig");
pub const audio = @import("audio.zig");
pub const media = @import("media.zig");
pub const recovery = @import("recovery.zig");
pub const rtp = @import("rtp.zig");
pub const session = @import("session.zig");
pub const transitions = @import("transitions.zig");
pub const udp = @import("udp.zig");

pub const Error = error{UnsupportedVoice};

pub const Status = enum {
    /// No voice transport, UDP, codec or DAVE implementation is linked.
    unavailable,
};

pub const status: Status = .unavailable;

pub const ReasonCode = enum {
    /// Legacy non-DAVE connections were discontinued; ordinary calls now
    /// require DAVE. Stage channels are exempt.
    dave_required,
    /// Official libdave artifacts are pinned, but only the optional ABI probe
    /// links them; shipping Opus/voice integration is not wired yet.
    native_dependencies_not_pinned,
    /// No voice WebSocket, UDP or media transport is implemented.
    transport_not_implemented,
};

pub const Reason = struct {
    code: ReasonCode,
    detail: []const u8,
};

/// Pinned official libdave release used by the optional ABI probe.
pub const libdave_release = "v1.3.0/cpp";

pub const reasons = [_]Reason{
    .{
        .code = .dave_required,
        .detail = "Discord discontinued legacy non-DAVE voice connections; ordinary calls require DAVE end-to-end encryption, while stage channels are exempt. Discord voice itself is supported and not deprecated.",
    },
    .{
        .code = .native_dependencies_not_pinned,
        .detail = "Official libdave v1.3.0 artifacts are pinned by SHA-256, but only the optional voice-probe step links them; Opus and a shipping integration are not wired into the default build.",
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
    try std.testing.expectEqualStrings("v1.3.0/cpp", libdave_release);
}

test "reason codes are unique and documented" {
    for (reasons, 0..) |reason, index| {
        try std.testing.expect(reason.detail.len > 0);
        for (reasons[0..index]) |earlier| {
            try std.testing.expect(earlier.code != reason.code);
        }
    }
}

//! DAVE protocol transition state machine (opcodes 21-31).
//!
//! This module tracks the protocol/epoch/transition state and tells the caller
//! which MLS operation or voice opcode to run next. It performs no MLS work and
//! links no native code; the optional libdave probe provides the native MLS and
//! media operations for a build that enables voice.
//!
//! Rules encoded here:
//! - protocol version 0 or above the identified maximum is rejected;
//! - transition IDs must be prepared before they execute, and must match;
//! - an epoch/key change discards the previous epoch state;
//! - a failed commit/welcome produces the explicit invalid-commit opcode, never
//!   a silent downgrade to unencrypted media.

const std = @import("std");
const gateway = @import("gateway.zig");

pub const Error = error{
    UnsupportedVersion,
    UnknownTransition,
    MissingEpoch,
    InvalidState,
    NoTransition,
    BufferTooSmall,
};

pub const Phase = enum {
    idle,
    external_sender_set,
    awaiting_group,
    active,
    stopped,
};

pub const Action = union(enum) {
    none,
    /// Opcode 26: send the marshalled MLS key package for this epoch.
    send_key_package,
    /// Run ProcessProposals and send the resulting commit/welcome as opcode 28.
    prepare_commit_welcome,
    /// Opcode 23: the local MLS state is ready for the transition.
    send_transition_ready: u16,
    /// Opcode 31: the commit or welcome could not be applied.
    send_invalid_commit_welcome,
    /// Opcode 31 plus the documented reset: drop local group state and send a
    /// fresh Opcode 26 key package.
    reset_and_send_key_package_with_invalid_commit,
    /// Apply the epoch to key derivation after Execute Transition.
    apply_epoch: u64,
    /// Execute the prepared transition and drop the previous media context.
    apply_transition: u16,
};

pub const Session = struct {
    max_version: u16,
    version: u16 = 0,
    epoch: u64 = 0,
    pending_epoch: ?u64 = null,
    pending_transition: ?u16 = null,
    phase: Phase = .idle,

    pub fn init(max_version: u16) Error!Session {
        if (max_version == 0) return error.UnsupportedVersion;
        return .{ .max_version = max_version };
    }

    /// Opcode 25 / session description: an external sender or MLS group setup
    /// was received at `version`.
    pub fn onExternalSender(self: *Session, version: u16) Error!void {
        try self.checkVersion(version);
        self.version = version;
        if (self.phase == .idle) self.phase = .external_sender_set;
    }

    /// Opcode 24: prepare a new MLS epoch. The client must send a key package.
    pub fn onPrepareEpoch(self: *Session, epoch: u64, version: u16) Error!Action {
        if (self.phase == .stopped) return error.InvalidState;
        try self.checkVersion(version);
        if (epoch == 0) return error.MissingEpoch;
        self.version = version;
        self.pending_epoch = epoch;
        self.phase = .awaiting_group;
        return .send_key_package;
    }

    /// Opcode 27: proposals were received; the caller runs ProcessProposals and
    /// sends the commit/welcome result.
    pub fn onProposals(self: *Session) Error!Action {
        if (self.phase != .awaiting_group) return error.InvalidState;
        return .prepare_commit_welcome;
    }

    /// Opcode 29: an announced commit for `transition_id` was applied.
    pub fn onAnnounceCommit(self: *Session, transition_id: u16) Error!Action {
        return self.onGroupTransition(transition_id);
    }

    /// Opcode 30: a welcome message for `transition_id` was applied.
    pub fn onWelcome(self: *Session, transition_id: u16) Error!Action {
        return self.onGroupTransition(transition_id);
    }

    fn onGroupTransition(self: *Session, transition_id: u16) Error!Action {
        if (self.phase != .awaiting_group and self.phase != .active) return error.InvalidState;
        if (self.pending_transition) |pending| {
            if (pending != transition_id) return error.UnknownTransition;
        }
        self.pending_transition = transition_id;
        return .{ .send_transition_ready = transition_id };
    }

    /// Opcode 21: a downgrade or protocol version change is prepared. Version 0
    /// is the documented downgrade. Transition id 0 is a reinitialization and is
    /// applied immediately, matching the protocol guidance.
    pub fn onPrepareTransition(self: *Session, transition_id: u16, version: u16) Error!Action {
        if (self.phase == .stopped) return error.InvalidState;
        if (version > self.max_version) return error.UnsupportedVersion;
        if (version != 0) self.version = version;
        if (transition_id == 0) {
            if (version == 0) {
                self.pending_epoch = null;
                self.phase = .external_sender_set;
            }
            return .{ .apply_transition = 0 };
        }
        self.pending_transition = transition_id;
        if (version == 0 and self.pending_epoch != null) {
            // A downgrade discards the pending encrypted epoch.
            self.pending_epoch = null;
        }
        return .{ .send_transition_ready = transition_id };
    }

    /// Opcode 22: execute the prepared transition. The caller drops old media
    /// keys after this point and applies the pending epoch, if any.
    pub fn onExecuteTransition(self: *Session, transition_id: u16) Error!Action {
        const pending = self.pending_transition orelse return error.NoTransition;
        if (pending != transition_id) return error.UnknownTransition;
        self.pending_transition = null;
        if (self.pending_epoch) |epoch| {
            self.epoch = epoch;
            self.pending_epoch = null;
            self.phase = .active;
            return .{ .apply_epoch = epoch };
        }
        self.phase = if (self.version == 0) .external_sender_set else .active;
        return .{ .apply_transition = transition_id };
    }

    /// The local commit/welcome could not be produced or applied.
    pub fn onCommitWelcomeFailed(self: *Session) Action {
        self.pending_transition = null;
        return .send_invalid_commit_welcome;
    }

    /// The local MLS application failed while processing an inbound message.
    /// The documented recovery is to reset local group state, send Opcode 31,
    /// and send a fresh key package.
    pub fn onMlsFailure(self: *Session) Action {
        self.pending_transition = null;
        self.pending_epoch = null;
        if (self.phase != .stopped) self.phase = .awaiting_group;
        return .reset_and_send_key_package_with_invalid_commit;
    }

    pub fn onClose(self: *Session) void {
        self.phase = .stopped;
        self.pending_epoch = null;
        self.pending_transition = null;
        self.version = 0;
        self.epoch = 0;
    }

    fn checkVersion(self: *Session, version: u16) Error!void {
        if (version == 0 or version > self.max_version) return error.UnsupportedVersion;
    }
};

pub const PrepareTransition = struct {
    protocol_version: u16,
    transition_id: u16,
};

pub const ExecuteTransition = struct {
    transition_id: u16,
};

pub const TransitionReady = struct {
    transition_id: u16,
};

pub const PrepareEpoch = struct {
    protocol_version: u16,
    epoch: u64,
};

pub const InvalidCommitWelcome = struct {
    transition_id: u16,
};

pub fn writePrepareTransition(buffer: []u8, data: PrepareTransition) Error![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":21,\"d\":{{\"protocol_version\":{d},\"transition_id\":{d}}}}}",
        .{ data.protocol_version, data.transition_id },
    ) catch return error.BufferTooSmall;
}

pub fn writeExecuteTransition(buffer: []u8, data: ExecuteTransition) Error![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":22,\"d\":{{\"transition_id\":{d}}}}}",
        .{data.transition_id},
    ) catch return error.BufferTooSmall;
}

pub fn writeTransitionReady(buffer: []u8, data: TransitionReady) Error![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":23,\"d\":{{\"transition_id\":{d}}}}}",
        .{data.transition_id},
    ) catch return error.BufferTooSmall;
}

pub fn writePrepareEpoch(buffer: []u8, data: PrepareEpoch) Error![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":24,\"d\":{{\"protocol_version\":{d},\"epoch\":{d}}}}}",
        .{ data.protocol_version, data.epoch },
    ) catch return error.BufferTooSmall;
}

pub fn writeInvalidCommitWelcome(buffer: []u8, data: InvalidCommitWelcome) Error![]const u8 {
    return std.fmt.bufPrint(
        buffer,
        "{{\"op\":31,\"d\":{{\"transition_id\":{d}}}}}",
        .{data.transition_id},
    ) catch return error.BufferTooSmall;
}

/// Parses a JSON DAVE control payload. Binary opcodes 25-30 use the binary
/// framing in `gateway.zig` instead.
pub fn parseControl(
    comptime T: type,
    allocator: std.mem.Allocator,
    envelope: []const u8,
    expected: gateway.Opcode,
    max_bytes: usize,
) !T {
    return gateway.parsePayload(T, allocator, envelope, expected, max_bytes);
}

test "epoch preparation sends a key package and activates on execute" {
    var session = try Session.init(1);
    try session.onExternalSender(1);
    try std.testing.expectEqual(Action.send_key_package, try session.onPrepareEpoch(1, 1));
    try std.testing.expectEqual(Action.prepare_commit_welcome, try session.onProposals());
    try std.testing.expectEqual(
        Action{ .send_transition_ready = 7 },
        try session.onWelcome(7),
    );
    try std.testing.expectEqual(Action{ .apply_epoch = 1 }, try session.onExecuteTransition(7));
    try std.testing.expectEqual(Phase.active, session.phase);
    try std.testing.expectEqual(@as(u64, 1), session.epoch);
}

test "transition ids must match and be prepared" {
    var session = try Session.init(1);
    try session.onExternalSender(1);
    _ = try session.onPrepareEpoch(1, 1);
    _ = try session.onAnnounceCommit(3);
    try std.testing.expectError(error.UnknownTransition, session.onExecuteTransition(4));
    try std.testing.expectEqual(Action{ .apply_epoch = 1 }, try session.onExecuteTransition(3));

    var fresh = try Session.init(1);
    try fresh.onExternalSender(1);
    try std.testing.expectError(error.NoTransition, fresh.onExecuteTransition(1));
}

test "unsupported versions fail closed" {
    var session = try Session.init(1);
    try std.testing.expectError(error.UnsupportedVersion, session.onExternalSender(0));
    try std.testing.expectError(error.UnsupportedVersion, session.onExternalSender(2));
    try std.testing.expectError(error.UnsupportedVersion, session.onPrepareEpoch(1, 2));
    try std.testing.expectError(error.UnsupportedVersion, session.onPrepareTransition(1, 9));
}

test "downgrade clears the pending encrypted epoch" {
    var session = try Session.init(1);
    try session.onExternalSender(1);
    _ = try session.onPrepareEpoch(1, 1);
    try std.testing.expectEqual(Action{ .send_transition_ready = 2 }, try session.onPrepareTransition(2, 0));
    try std.testing.expectEqual(Action{ .apply_transition = 2 }, try session.onExecuteTransition(2));
    try std.testing.expectEqual(@as(?u64, null), session.pending_epoch);
    try std.testing.expectEqual(@as(u64, 0), session.epoch);
    try std.testing.expectEqual(Phase.external_sender_set, session.phase);
}

test "mls failure resets group state and requests a new key package" {
    var session = try Session.init(1);
    try session.onExternalSender(1);
    _ = try session.onPrepareEpoch(1, 1);
    _ = try session.onAnnounceCommit(5);
    try std.testing.expectEqual(
        Action.reset_and_send_key_package_with_invalid_commit,
        session.onMlsFailure(),
    );
    try std.testing.expectEqual(@as(?u16, null), session.pending_transition);
    try std.testing.expectEqual(@as(?u64, null), session.pending_epoch);
    try std.testing.expectEqual(Phase.awaiting_group, session.phase);
}

test "transition id zero applies immediately" {
    var session = try Session.init(1);
    try session.onExternalSender(1);
    _ = try session.onPrepareEpoch(1, 1);
    try std.testing.expectEqual(
        Action{ .apply_transition = 0 },
        try session.onPrepareTransition(0, 0),
    );
    try std.testing.expectEqual(@as(?u64, null), session.pending_epoch);
}

test "control payload codecs match the documented shapes" {
    var buffer: [256]u8 = undefined;
    try std.testing.expectEqualStrings(
        "{\"op\":21,\"d\":{\"protocol_version\":1,\"transition_id\":7}}",
        try writePrepareTransition(&buffer, .{ .protocol_version = 1, .transition_id = 7 }),
    );
    try std.testing.expectEqualStrings(
        "{\"op\":22,\"d\":{\"transition_id\":7}}",
        try writeExecuteTransition(&buffer, .{ .transition_id = 7 }),
    );
    try std.testing.expectEqualStrings(
        "{\"op\":23,\"d\":{\"transition_id\":7}}",
        try writeTransitionReady(&buffer, .{ .transition_id = 7 }),
    );
    try std.testing.expectEqualStrings(
        "{\"op\":24,\"d\":{\"protocol_version\":1,\"epoch\":3}}",
        try writePrepareEpoch(&buffer, .{ .protocol_version = 1, .epoch = 3 }),
    );
    try std.testing.expectEqualStrings(
        "{\"op\":31,\"d\":{\"transition_id\":7}}",
        try writeInvalidCommitWelcome(&buffer, .{ .transition_id = 7 }),
    );

    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const epoch = try parseControl(PrepareEpoch, arena.allocator(),
        \\{"op":24,"d":{"protocol_version":1,"epoch":3}}
    , .dave_prepare_epoch, 256);
    try std.testing.expectEqual(@as(u64, 3), epoch.epoch);
}

test "stopped sessions reject further transitions" {
    var session = try Session.init(1);
    try session.onExternalSender(1);
    session.onClose();
    try std.testing.expectError(error.InvalidState, session.onPrepareEpoch(2, 1));
    try std.testing.expectError(error.InvalidState, session.onPrepareTransition(2, 1));
    try std.testing.expectError(error.InvalidState, session.onAnnounceCommit(1));
}

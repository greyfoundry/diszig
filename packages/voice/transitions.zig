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

pub const Error = error{
    UnsupportedVersion,
    UnknownTransition,
    MissingEpoch,
    InvalidState,
    NoTransition,
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
    /// is the documented downgrade and is accepted only here.
    pub fn onPrepareTransition(self: *Session, transition_id: u16, version: u16) Error!Action {
        if (self.phase == .stopped) return error.InvalidState;
        if (version > self.max_version) return error.UnsupportedVersion;
        if (version != 0) self.version = version;
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
    pub fn onMlsFailure(self: *Session) Action {
        self.pending_transition = null;
        return .send_invalid_commit_welcome;
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

test "mls failure returns the explicit invalid-commit action" {
    var session = try Session.init(1);
    try session.onExternalSender(1);
    _ = try session.onPrepareEpoch(1, 1);
    _ = try session.onAnnounceCommit(5);
    try std.testing.expectEqual(Action.send_invalid_commit_welcome, session.onMlsFailure());
    try std.testing.expectEqual(@as(?u16, null), session.pending_transition);
}

test "stopped sessions reject further transitions" {
    var session = try Session.init(1);
    try session.onExternalSender(1);
    session.onClose();
    try std.testing.expectError(error.InvalidState, session.onPrepareEpoch(2, 1));
    try std.testing.expectError(error.InvalidState, session.onPrepareTransition(2, 1));
    try std.testing.expectError(error.InvalidState, session.onAnnounceCommit(1));
}

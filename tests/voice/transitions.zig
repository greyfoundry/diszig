//! DAVE transition state-machine contracts.

const std = @import("std");
const diszig = @import("diszig");
const transitions = diszig.voice.transitions;

test "dave transition module is exported" {
    _ = transitions.Action;
    try std.testing.expectError(error.UnsupportedVersion, transitions.Session.init(0));
}

test "epoch sequence emits key package, ready and epoch apply" {
    var session = try transitions.Session.init(1);
    try session.onExternalSender(1);
    try std.testing.expectEqual(transitions.Action.send_key_package, try session.onPrepareEpoch(1, 1));
    try std.testing.expectEqual(transitions.Action.prepare_commit_welcome, try session.onProposals());
    try std.testing.expectEqual(
        transitions.Action{ .send_transition_ready = 4 },
        try session.onAnnounceCommit(4),
    );
    try std.testing.expectEqual(
        transitions.Action{ .apply_epoch = 1 },
        try session.onExecuteTransition(4),
    );
    try std.testing.expectEqual(@as(u64, 1), session.epoch);
}

test "mismatched or missing transitions fail closed" {
    var session = try transitions.Session.init(1);
    try session.onExternalSender(1);
    _ = try session.onPrepareEpoch(1, 1);
    _ = try session.onWelcome(2);
    try std.testing.expectError(error.UnknownTransition, session.onExecuteTransition(3));
    try std.testing.expectError(error.UnsupportedVersion, session.onPrepareEpoch(2, 2));
}

test "downgrade clears the encrypted epoch and mls failure is explicit" {
    var session = try transitions.Session.init(1);
    try session.onExternalSender(1);
    _ = try session.onPrepareEpoch(1, 1);
    _ = try session.onPrepareTransition(9, 0);
    try std.testing.expectEqual(
        transitions.Action{ .apply_transition = 9 },
        try session.onExecuteTransition(9),
    );
    try std.testing.expectEqual(@as(?u64, null), session.pending_epoch);

    _ = try session.onPrepareEpoch(2, 1);
    _ = try session.onAnnounceCommit(10);
    try std.testing.expectEqual(
        transitions.Action.reset_and_send_key_package_with_invalid_commit,
        session.onMlsFailure(),
    );
}

test "closing stops the session" {
    var session = try transitions.Session.init(1);
    try session.onExternalSender(1);
    session.onClose();
    try std.testing.expectError(error.InvalidState, session.onPrepareEpoch(1, 1));
}

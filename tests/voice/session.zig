//! Voice session orchestration contracts.

const std = @import("std");
const diszig = @import("diszig");
const session = diszig.voice.session;
const gateway = diszig.voice.gateway;

test "session module is exported and max version zero disables dave" {
    _ = session.Phase;
    const state = try session.Session.init(0);
    try std.testing.expect(state.dave == null);
}

test "sequenced handshake through the public API" {
    var state = try session.Session.init(1);
    try std.testing.expectEqual(session.Action.send_identify, try state.onHello(.{
        .heartbeat_interval = 40,
        .version = 8,
    }));
    const ready = try state.onReady(.{
        .ssrc = 9,
        .ip = "127.0.0.1",
        .port = 5000,
        .modes = &.{"aead_xchacha20_poly1305_rtpsize"},
    });
    try std.testing.expectEqual(@as(u16, 5000), ready.ready.port);

    const select = try state.selectProtocol("203.0.113.9");
    try std.testing.expectEqual(gateway.EncryptionMode.aead_xchacha20_poly1305_rtpsize, select.send_select_protocol.mode);

    const key: [32]u8 = @splat(2);
    const established = try state.onSessionDescription(.{
        .mode = .aead_xchacha20_poly1305_rtpsize,
        .secret_key = &key,
        .dave_protocol_version = 1,
    });
    try std.testing.expectEqual(gateway.EncryptionMode.aead_xchacha20_poly1305_rtpsize, established.established);
    try std.testing.expectEqual(@as(usize, 32), state.secretKey().?.len);
}

test "zero dave version disables dave and close stops" {
    var state = try session.Session.init(0);
    _ = try state.onHello(.{ .heartbeat_interval = 20, .version = 8 });
    try std.testing.expectError(error.UnsupportedVersion, state.onPrepareEpoch(1, 1));
    try std.testing.expectEqual(session.Action{ .closed = .stop }, state.onClose(4017));
}

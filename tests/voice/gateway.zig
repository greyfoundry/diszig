//! Voice gateway control contracts.

const std = @import("std");
const diszig = @import("diszig");
const voice = diszig.voice;
const gateway = voice.gateway;

test "voice gateway is exported and reports the documented version" {
    try std.testing.expectEqual(@as(u8, 8), voice.documented_gateway_version);
    try std.testing.expect(gateway.Opcode.identify.clientMaySend());
}

test "close codes and encryption negotiation" {
    try std.testing.expectEqual(gateway.CloseAction.stop, gateway.classifyClose(4014));
    try std.testing.expectEqual(gateway.CloseAction.resume_session, gateway.classifyClose(4015));
    try std.testing.expectError(
        error.NoSupportedEncryptionMode,
        gateway.selectEncryption(&.{"xsalsa20_poly1305"}),
    );
    try std.testing.expectEqual(
        gateway.EncryptionMode.aead_xchacha20_poly1305_rtpsize,
        try gateway.selectEncryption(&.{"aead_xchacha20_poly1305_rtpsize"}),
    );
}

test "voice state and server correlation" {
    const guild = try diszig.Snowflake.parse("1");
    const user = try diszig.Snowflake.parse("2");
    var correlator = gateway.Correlator.init(guild, user);

    const state = gateway.StateUpdate{
        .guild_id = guild,
        .channel_id = guild,
        .session_id = "session",
        .user_id = user,
    };
    try std.testing.expectEqual(@as(?gateway.Join, null), try correlator.onState(state));
    const join = (try correlator.onServer(.{
        .guild_id = guild,
        .token = "token",
        .endpoint = "voice.example",
    })).?;
    try std.testing.expectEqualStrings("session", join.session_id);
}

test "identify and heartbeat builders" {
    var buffer: [512]u8 = undefined;
    const guild = try diszig.Snowflake.parse("1");
    const user = try diszig.Snowflake.parse("2");
    const identify = try gateway.writeIdentify(&buffer, .{
        .server_id = guild,
        .user_id = user,
        .session_id = "s",
        .token = "t",
    });
    try std.testing.expect(std.mem.indexOf(u8, identify, "\"max_dave_protocol_version\"") == null);

    const heartbeat = try gateway.writeHeartbeat(&buffer, .{
        .version = 8,
        .nonce = 5,
        .seq_ack = null,
    });
    try std.testing.expectEqualStrings("{\"op\":3,\"d\":{\"t\":5,\"seq_ack\":-1}}", heartbeat);
}

fn parseReady(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    _ = try gateway.parsePayload(gateway.Ready, arena.allocator(), payload, .ready, 2048);
}

test "allocation failure while parsing ready modes is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseReady,
        .{"{\"op\":2,\"d\":{\"ssrc\":1,\"ip\":\"127.0.0.1\",\"port\":1234,\"modes\":[\"aead_xchacha20_poly1305_rtpsize\",\"aead_aes256_gcm_rtpsize\"]}}"},
    );
}

//! Voice audio pipeline contracts.

const std = @import("std");
const diszig = @import("diszig");
const audio = diszig.voice.audio;

const FakeCodec = struct {
    var encode_calls: usize = 0;

    fn encode(_: *anyopaque, pcm: []const i16, out: []u8) anyerror![]const u8 {
        encode_calls += 1;
        out[0] = @truncate(@as(u16, @bitCast(pcm[0])));
        return out[0..1];
    }

    fn decode(_: *anyopaque, packet: []const u8, pcm: []i16) anyerror![]const i16 {
        if (packet.len == 0) return error.InvalidFrame;
        pcm[0] = @intCast(packet[0]);
        return pcm;
    }
};

test "audio frame geometry and speaking policy" {
    try std.testing.expectEqual(@as(u32, 48_000), audio.sample_rate);
    try std.testing.expectEqual(@as(usize, 3840), audio.frame_bytes);
    try std.testing.expect(!(audio.SpeakingFlags{}).canSend());
    try std.testing.expect((audio.SpeakingFlags{ .microphone = true }).canSend());
    try std.testing.expectEqual(@as(u8, 0b101), (audio.SpeakingFlags{ .microphone = true, .priority = true }).bits());
}

test "send pipeline paces and cancels cleanly" {
    var context: u8 = 0;
    const encoder = audio.Encoder{ .context = &context, .encodeFn = FakeCodec.encode };
    var pipeline = audio.SendPipeline.init(0);
    pipeline.setSpeaking(.{ .microphone = true });

    const pcm: [audio.frame_samples * audio.channels]i16 = @splat(1);
    var out: [audio.max_packet_bytes]u8 = undefined;
    try std.testing.expect((try pipeline.step(encoder, &pcm, 0, &out)) != null);
    try std.testing.expectEqual(@as(?[]const u8, null), try pipeline.step(encoder, &pcm, 5, &out));
    pipeline.cancel();
    try std.testing.expectError(error.Cancelled, pipeline.step(encoder, &pcm, 20, &out));
    try std.testing.expectEqual(@as(usize, 1), FakeCodec.encode_calls);
}

test "receive requires consent and decodes an in-order packet" {
    var context: u8 = 0;
    const decoder = audio.Decoder{ .context = &context, .decodeFn = FakeCodec.decode };
    try std.testing.expectError(error.ConsentRequired, audio.ReceivePipeline.init(.denied, decoder, 2, 0));

    var pipeline = try audio.ReceivePipeline.init(.granted, decoder, 2, 0);
    try pipeline.push(1, &.{9}, 0);
    var pcm: [audio.frame_samples * audio.channels]i16 = @splat(0);
    const decoded = (try pipeline.step(&pcm, 0)).?;
    try std.testing.expectEqual(@as(i16, 9), decoded[0]);
}

fn parsePipe(allocator: std.mem.Allocator) !void {
    _ = allocator;
    var jitter = try audio.JitterBuffer.init(2, 1);
    try jitter.push(1, "x", 0);
}

test "jitter allocation is not used" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, parsePipe, .{});
}

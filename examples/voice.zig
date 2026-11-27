//! Isolated voice media pipeline example: no socket, no audio device, no codec
//! dependency. Compile with `zig build examples`.

const std = @import("std");
const diszig = @import("diszig");
const audio = diszig.voice.audio;

fn fakeEncode(_: *anyopaque, pcm: []const i16, out: []u8) anyerror![]const u8 {
    out[0] = @truncate(@as(u16, @bitCast(pcm[0])));
    return out[0..1];
}

fn fakeDecode(_: *anyopaque, packet: []const u8, pcm: []i16) anyerror![]const i16 {
    pcm[0] = @intCast(packet[0]);
    return pcm;
}

pub fn main() !void {
    var context: u8 = 0;
    const encoder = audio.Encoder{ .context = &context, .encodeFn = fakeEncode };
    const decoder = audio.Decoder{ .context = &context, .decodeFn = fakeDecode };

    var send = audio.SendPipeline.init(0);
    send.setSpeaking(.{ .microphone = true });
    const pcm: [audio.frame_samples * audio.channels]i16 = @splat(0);
    var packet_buffer: [audio.max_packet_bytes]u8 = undefined;
    const packet = (try send.step(encoder, &pcm, 0, &packet_buffer)) orelse return error.NoPacket;

    var receive = try audio.ReceivePipeline.init(.granted, decoder, 4, 20);
    try receive.push(1, packet, 0);
    var decoded: [audio.frame_samples * audio.channels]i16 = @splat(0);
    _ = (try receive.step(&decoded, 0)) orelse return error.NoFrame;

    std.debug.print("voice pipeline ok: packet={d} bytes frame={d} samples\n", .{ packet.len, decoded.len });
}

//! Optional Opus encode/decode probe. Run with:
//!   python tools/fetch_opus.py
//!   zig build voice-audio-probe -Dopus-dir=third_party/opus/v1.5.2/src/opus-1.5.2

const std = @import("std");
const opus = @import("voice_opus");
const audio = opus.audio;

pub fn main() !void {
    var encoder = try opus.Encoder.init();
    defer encoder.deinit();
    var decoder = try opus.Decoder.init();
    defer decoder.deinit();

    const pcm: [audio.frame_samples * audio.channels]i16 = @splat(0);
    var packet_buffer: [audio.max_packet_bytes]u8 = undefined;
    const packet = try encoder.encodeSamples(&pcm, &packet_buffer);
    if (packet.len == 0 or packet.len > audio.max_packet_bytes) return error.InvalidPacket;

    var decoded: [audio.frame_samples * audio.channels]i16 = @splat(0);
    const samples = try decoder.decodePacket(packet, &decoded);
    if (samples.len == 0) return error.NoSamples;

    std.debug.print(
        "opus ok: packet={d} bytes decoded_samples={d}\n",
        .{ packet.len, samples.len },
    );
}

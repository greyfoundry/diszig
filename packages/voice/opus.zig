//! Optional native Opus bindings.
//!
//! Compiled only when `-Dopus-dir` points at the pinned source tree; the default
//! build links no codec. It implements the `audio.Encoder`/`audio.Decoder`
//! vtables for 48 kHz stereo 20 ms frames.

const std = @import("std");
const voice = @import("voice");
pub const audio = voice.audio;

pub const c = @import("opus_c");

pub const Error = error{
    EncoderCreateFailed,
    DecoderCreateFailed,
    EncodeFailed,
    DecodeFailed,
    InvalidFrame,
};

pub const Encoder = struct {
    handle: *c.OpusEncoder,

    pub fn init() Error!Encoder {
        var err: c_int = 0;
        const handle = c.opus_encoder_create(
            @intCast(audio.sample_rate),
            audio.channels,
            c.OPUS_APPLICATION_VOIP,
            &err,
        );
        if (err != c.OPUS_OK or handle == null) return error.EncoderCreateFailed;
        return .{ .handle = handle.? };
    }

    pub fn deinit(self: *Encoder) void {
        c.opus_encoder_destroy(self.handle);
        self.* = undefined;
    }

    pub fn encodeSamples(self: *Encoder, pcm: []const i16, out: []u8) ![]const u8 {
        if (pcm.len != audio.frame_samples * audio.channels) return error.InvalidFrame;
        const written = c.opus_encode(
            self.handle,
            pcm.ptr,
            @intCast(audio.frame_samples),
            out.ptr,
            @intCast(out.len),
        );
        if (written < 0) return error.EncodeFailed;
        return out[0..@intCast(written)];
    }

    pub fn vtable(self: *Encoder) audio.Encoder {
        return .{ .context = self, .encodeFn = encodeVtable };
    }

    fn encodeVtable(context: *anyopaque, pcm: []const i16, out: []u8) anyerror![]const u8 {
        const self: *Encoder = @ptrCast(@alignCast(context));
        return self.encodeSamples(pcm, out);
    }
};

pub const Decoder = struct {
    handle: *c.OpusDecoder,

    pub fn init() Error!Decoder {
        var err: c_int = 0;
        const handle = c.opus_decoder_create(@intCast(audio.sample_rate), audio.channels, &err);
        if (err != c.OPUS_OK or handle == null) return error.DecoderCreateFailed;
        return .{ .handle = handle.? };
    }

    pub fn deinit(self: *Decoder) void {
        c.opus_decoder_destroy(self.handle);
        self.* = undefined;
    }

    pub fn decodePacket(self: *Decoder, packet: []const u8, pcm: []i16) ![]const i16 {
        if (packet.len == 0 or packet.len > audio.max_packet_bytes) return error.InvalidFrame;
        if (pcm.len != audio.frame_samples * audio.channels) return error.InvalidFrame;
        const written = c.opus_decode(
            self.handle,
            packet.ptr,
            @intCast(packet.len),
            pcm.ptr,
            @intCast(audio.frame_samples),
            0,
        );
        if (written < 0) return error.DecodeFailed;
        return pcm[0 .. @as(usize, @intCast(written)) * audio.channels];
    }

    pub fn vtable(self: *Decoder) audio.Decoder {
        return .{ .context = self, .decodeFn = decodeVtable };
    }

    fn decodeVtable(context: *anyopaque, packet: []const u8, pcm: []i16) anyerror![]const i16 {
        const self: *Decoder = @ptrCast(@alignCast(context));
        return self.decodePacket(packet, pcm);
    }
};

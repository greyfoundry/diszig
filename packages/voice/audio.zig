//! Bounded Opus media pipeline scaffolding.
//!
//! This module owns pacing, speaking/silence policy, cancellation and bounded
//! jitter buffering. It does not link an Opus codec: encoders/decoders are
//! caller-supplied vtable objects, so the default build has no audio
//! dependency and tests use a deterministic fake codec. Native Opus binding is
//! a separate optional build step.

const std = @import("std");

pub const Error = error{
    BufferTooSmall,
    InvalidFrame,
    QueueFull,
    TooLate,
    Duplicate,
    NothingReady,
    Cancelled,
    ConsentRequired,
    EncoderFailed,
    DecoderFailed,
};

pub const sample_rate: u32 = 48_000;
pub const channels: u8 = 2;
pub const frame_samples: usize = 960; // 20 ms
pub const frame_bytes: usize = frame_samples * channels * @sizeOf(i16);
pub const frame_interval_ms: u32 = 20;
/// Opus packets are bounded; 1275 bytes is the largest standard packet.
pub const max_packet_bytes: usize = 1275;

pub const SpeakingFlags = packed struct(u8) {
    microphone: bool = false,
    soundshare: bool = false,
    priority: bool = false,
    _reserved: u5 = 0,

    pub fn bits(self: SpeakingFlags) u8 {
        return @bitCast(self);
    }

    pub fn canSend(self: SpeakingFlags) bool {
        return self.bits() != 0;
    }
};

pub const Encoder = struct {
    context: *anyopaque,
    encodeFn: *const fn (context: *anyopaque, pcm: []const i16, out: []u8) anyerror![]const u8,

    pub fn encode(self: Encoder, pcm: []const i16, out: []u8) ![]const u8 {
        if (pcm.len != frame_samples * channels) return error.InvalidFrame;
        return self.encodeFn(self.context, pcm, out);
    }
};

pub const Decoder = struct {
    context: *anyopaque,
    decodeFn: *const fn (context: *anyopaque, packet: []const u8, pcm: []i16) anyerror![]const i16,

    pub fn decode(self: Decoder, packet: []const u8, pcm: []i16) ![]const i16 {
        if (packet.len == 0 or packet.len > max_packet_bytes) return error.InvalidFrame;
        if (pcm.len != frame_samples * channels) return error.InvalidFrame;
        return self.decodeFn(self.context, packet, pcm);
    }
};

/// 20 ms send pacing. A late deadline catches up by at most one interval so a
/// slow producer cannot create an unbounded burst.
pub const Pacer = struct {
    next_ms: u64,
    interval_ms: u32 = frame_interval_ms,
    started: bool = false,

    pub fn init(now_ms: u64) Pacer {
        return .{ .next_ms = now_ms };
    }

    pub fn ready(self: *Pacer, now_ms: u64) bool {
        if (!self.started) {
            self.started = true;
            self.next_ms = now_ms + self.interval_ms;
            return true;
        }
        if (now_ms < self.next_ms) return false;
        const late = now_ms - self.next_ms;
        const intervals = late / self.interval_ms;
        self.next_ms += (intervals + 1) * self.interval_ms;
        return true;
    }

    pub fn delayMs(self: Pacer, now_ms: u64) u32 {
        if (!self.started or now_ms >= self.next_ms) return 0;
        return @intCast(self.next_ms - now_ms);
    }
};

/// Send-side state: pacing, speaking mode and cancellation. A zero speaking
/// mask cannot send audio; silence is an explicit choice by the caller.
pub const SendPipeline = struct {
    pacer: Pacer,
    speaking: SpeakingFlags = .{},
    cancelled: bool = false,
    frames_sent: u64 = 0,

    pub fn init(now_ms: u64) SendPipeline {
        return .{ .pacer = Pacer.init(now_ms) };
    }

    pub fn setSpeaking(self: *SendPipeline, flags: SpeakingFlags) void {
        self.speaking = flags;
    }

    pub fn cancel(self: *SendPipeline) void {
        self.cancelled = true;
    }

    /// Encodes and returns one frame when the pacer allows it. The caller owns
    /// the packet buffer. Cancellation is checked before encoding so a cancelled
    /// pipeline never touches the codec.
    pub fn step(
        self: *SendPipeline,
        encoder: Encoder,
        pcm: []const i16,
        now_ms: u64,
        out: []u8,
    ) !?[]const u8 {
        if (self.cancelled) return error.Cancelled;
        if (!self.speaking.canSend()) return null;
        if (!self.pacer.ready(now_ms)) return null;
        const packet = try encoder.encode(pcm, out);
        if (packet.len == 0 or packet.len > max_packet_bytes) return error.EncoderFailed;
        self.frames_sent += 1;
        return packet;
    }
};

pub const ReceiveConsent = enum {
    denied,
    granted,
};

const slot_empty = std.math.maxInt(u16);

/// Bounded jitter buffer. Packets are copied into fixed slots; no allocator is
/// used. Reordering is limited to the buffer depth. When the expected sequence
/// is missing past its deadline the pipeline reports `packet_lost` and skips,
/// which is the documented loss policy; it never blocks forever.
pub const JitterBuffer = struct {
    capacity: usize,
    max_packet: usize,
    packets: [16][max_packet_bytes]u8 = undefined,
    lengths: [16]u16 = @splat(0),
    sequences: [16]u16 = @splat(slot_empty),
    count: usize = 0,
    next_sequence: ?u16 = null,
    deadline_ms: u64,
    delay_ms: u32,

    pub fn init(capacity: usize, delay_ms: u32) !JitterBuffer {
        if (capacity == 0 or capacity > 16) return error.InvalidFrame;
        return .{
            .capacity = capacity,
            .max_packet = max_packet_bytes,
            .deadline_ms = 0,
            .delay_ms = delay_ms,
        };
    }

    fn find(self: *JitterBuffer, sequence: u16) ?usize {
        for (0..self.capacity) |index| {
            if (self.sequences[index] == sequence) return index;
        }
        return null;
    }

    fn freeSlot(self: *JitterBuffer) ?usize {
        for (0..self.capacity) |index| {
            if (self.sequences[index] == slot_empty) return index;
        }
        return null;
    }

    pub fn push(self: *JitterBuffer, sequence: u16, packet: []const u8, now_ms: u64) !void {
        if (packet.len == 0 or packet.len > self.max_packet) return error.InvalidFrame;
        if (self.find(sequence) != null) return error.Duplicate;
        if (self.count == 0) self.deadline_ms = now_ms + self.delay_ms;
        const slot = self.freeSlot() orelse blk: {
            // Drop the oldest packet rather than growing without bound.
            self.evictOldest();
            break :blk self.freeSlot().?;
        };
        @memcpy(self.packets[slot][0..packet.len], packet);
        self.lengths[slot] = @intCast(packet.len);
        self.sequences[slot] = sequence;
        self.count += 1;
        if (self.next_sequence == null) self.next_sequence = sequence;
    }

    fn evictOldest(self: *JitterBuffer) void {
        var oldest: ?usize = null;
        for (0..self.capacity) |index| {
            if (self.sequences[index] == slot_empty) continue;
            if (oldest == null or sequenceBefore(self.sequences[index], self.sequences[oldest.?])) {
                oldest = index;
            }
        }
        if (oldest) |index| {
            self.sequences[index] = slot_empty;
            self.lengths[index] = 0;
            self.count -= 1;
        }
    }

    fn advance(self: *JitterBuffer) void {
        if (self.next_sequence) |next| self.next_sequence = next +% 1;
    }

    pub const Pop = union(enum) {
        packet: []const u8,
        packet_lost,
        nothing,
    };

    /// Returns the next in-order packet, a loss indication once the deadline
    /// passes, or `nothing` while waiting.
    pub fn pop(self: *JitterBuffer, now_ms: u64) Pop {
        const next = self.next_sequence orelse return .nothing;
        if (self.find(next)) |index| {
            const packet = self.packets[index][0..self.lengths[index]];
            self.sequences[index] = slot_empty;
            self.lengths[index] = 0;
            self.count -= 1;
            self.advance();
            if (self.count == 0) self.deadline_ms = now_ms + self.delay_ms;
            return .{ .packet = packet };
        }
        if (now_ms >= self.deadline_ms) {
            self.advance();
            self.deadline_ms = now_ms + self.delay_ms;
            return .packet_lost;
        }
        return .nothing;
    }
};

fn sequenceBefore(a: u16, b: u16) bool {
    return @as(i16, @bitCast(a -% b)) < 0;
}

/// Receive-side pipeline: explicit consent, bounded jitter, decode-on-pop. It
/// stores no recordings and never touches an audio device.
pub const ReceivePipeline = struct {
    jitter: JitterBuffer,
    decoder: Decoder,
    consent: ReceiveConsent,
    decoded_frames: u64 = 0,
    losses: u64 = 0,

    pub fn init(consent: ReceiveConsent, decoder: Decoder, capacity: usize, delay_ms: u32) !ReceivePipeline {
        if (consent != .granted) return error.ConsentRequired;
        return .{
            .jitter = try JitterBuffer.init(capacity, delay_ms),
            .decoder = decoder,
            .consent = consent,
        };
    }

    pub fn push(self: *ReceivePipeline, sequence: u16, packet: []const u8, now_ms: u64) !void {
        if (self.consent != .granted) return error.ConsentRequired;
        try self.jitter.push(sequence, packet, now_ms);
    }

    /// Pops one packet and decodes it into `pcm`. On loss, returns
    /// `packet_lost` and the caller decides whether to conceal.
    pub fn step(self: *ReceivePipeline, pcm: []i16, now_ms: u64) !?[]const i16 {
        if (self.consent != .granted) return error.ConsentRequired;
        switch (self.jitter.pop(now_ms)) {
            .nothing => return null,
            .packet_lost => {
                self.losses += 1;
                return null;
            },
            .packet => |packet| {
                const decoded = try self.decoder.decode(packet, pcm);
                self.decoded_frames += 1;
                return decoded;
            },
        }
    }
};

test "pacer enforces 20ms and catches up at most one interval" {
    var pacer = Pacer.init(1000);
    try std.testing.expect(pacer.ready(1000));
    try std.testing.expect(!pacer.ready(1010));
    try std.testing.expect(pacer.ready(1020));
    try std.testing.expectEqual(@as(u32, 0), pacer.delayMs(1020));
    // A 200ms stall only advances one interval past now, not a burst.
    try std.testing.expect(pacer.ready(1220));
    try std.testing.expect(!pacer.ready(1221));
}

test "send pipeline requires speaking, respects cancel and bounds packets" {
    const Fake = struct {
        fn encode(_: *anyopaque, pcm: []const i16, out: []u8) anyerror![]const u8 {
            if (pcm.len == 0) return error.InvalidFrame;
            out[0] = @intCast(pcm[0] & 0xff);
            return out[0..1];
        }
    };
    var context: u8 = 0;
    const encoder = Encoder{ .context = &context, .encodeFn = Fake.encode };
    var pipeline = SendPipeline.init(0);
    const pcm: [frame_samples * channels]i16 = @splat(0);

    var sink: [64]u8 = @splat(0);
    try std.testing.expectEqual(@as(?[]const u8, null), try pipeline.step(encoder, &pcm, 0, &sink));
    pipeline.setSpeaking(.{ .microphone = true });
    var out: [max_packet_bytes]u8 = undefined;
    const packet = (try pipeline.step(encoder, &pcm, 0, &out)).?;
    try std.testing.expectEqual(@as(usize, 1), packet.len);
    pipeline.cancel();
    try std.testing.expectError(error.Cancelled, pipeline.step(encoder, &pcm, 20, &out));
}

test "jitter buffer bounds, reorders and reports loss" {
    var jitter = try JitterBuffer.init(2, 30);
    try jitter.push(2, "two", 0);
    try jitter.push(1, "one", 0);
    try std.testing.expectError(error.Duplicate, jitter.push(1, "dup", 0));
    try jitter.push(3, "three", 0); // capacity 2: evicts the oldest
    const first = jitter.pop(0);
    try std.testing.expect(first == .packet);
    try std.testing.expectEqualStrings("two", first.packet);
    const second = jitter.pop(0);
    try std.testing.expect(second == .packet);
    try std.testing.expectEqualStrings("three", second.packet);
    // Sequence 4 missing: loss after the deadline, not a hang.
    try std.testing.expect(jitter.pop(0) == .nothing);
    try std.testing.expect(jitter.pop(60) == .packet_lost);
}

test "receive pipeline requires consent and decodes through the codec" {
    const Fake = struct {
        fn decode(_: *anyopaque, packet: []const u8, pcm: []i16) anyerror![]const i16 {
            _ = packet;
            pcm[0] = 7;
            return pcm;
        }
    };
    var context: u8 = 0;
    const decoder = Decoder{ .context = &context, .decodeFn = Fake.decode };

    try std.testing.expectError(
        error.ConsentRequired,
        ReceivePipeline.init(.denied, decoder, 2, 0),
    );

    var pipeline = try ReceivePipeline.init(.granted, decoder, 2, 0);
    try pipeline.push(1, "packet", 0);
    var pcm: [frame_samples * channels]i16 = @splat(0);
    const decoded = (try pipeline.step(&pcm, 0)).?;
    try std.testing.expectEqual(@as(i16, 7), decoded[0]);
    try std.testing.expectEqual(@as(u64, 1), pipeline.decoded_frames);
}

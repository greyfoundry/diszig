//! Bounded Gateway dispatch queue.
//!
//! One queue preserves FIFO order for one shard. Multiple consumers on the same
//! queue would break that order, so a shard uses one consumer. The queue copies
//! each payload because the transport buffer is only valid until the next read.
//! A handler receives a borrowed slice for the callback and must call `copy`
//! to retain it.
//!
//! Overload is explicit: `tryPush` returns `error.QueueFull` and increments a
//! drop counter. It never blocks the reader or the heartbeat thread, and it
//! never grows the queue.
//!
//! Resume replay can deliver an event more than once. The queue does not
//! deduplicate; handlers should use `sequence` when they need idempotence.

const std = @import("std");

pub const max_name_bytes = 64;

pub const Options = struct {
    /// Fixed queue capacity. Zero is rejected.
    capacity: usize = 256,
    /// Maximum bytes retained for one event payload.
    max_event_bytes: usize = 1024 * 1024,
    /// Maximum event name bytes. Longer names are rejected.
    max_name: usize = max_name_bytes,
};

pub const Error = error{
    CapacityZero,
    QueueFull,
    EventTooLarge,
    NameTooLong,
    InvalidNameLimit,
    OutOfMemory,
};

pub const Event = struct {
    name: []const u8,
    sequence: ?i64,
    payload: []const u8,

    /// Owns an independent copy of this event. Use when a handler or cache must
    /// retain data past the callback.
    pub fn copy(self: Event, allocator: std.mem.Allocator) !OwnedEvent {
        const name = try allocator.dupe(u8, self.name);
        errdefer allocator.free(name);
        const payload = try allocator.dupe(u8, self.payload);
        return .{
            .allocator = allocator,
            .name = name,
            .payload = payload,
            .sequence = self.sequence,
        };
    }
};

pub const OwnedEvent = struct {
    allocator: std.mem.Allocator,
    name: []u8,
    payload: []u8,
    sequence: ?i64,

    pub fn deinit(self: *OwnedEvent) void {
        self.allocator.free(self.name);
        self.allocator.free(self.payload);
        self.* = undefined;
    }
};

const Slot = struct {
    name: [max_name_bytes]u8,
    name_len: usize,
    payload: ?[]u8,
    payload_len: usize,
    sequence: ?i64,
};

pub const Queue = struct {
    allocator: std.mem.Allocator,
    slots: []Slot,
    head: usize,
    len: usize,
    dropped: u64,
    max_event_bytes: usize,
    max_name: usize,

    pub fn init(allocator: std.mem.Allocator, options: Options) !Queue {
        if (options.capacity == 0) return error.CapacityZero;
        if (options.max_name == 0 or options.max_name > max_name_bytes) return error.InvalidNameLimit;

        const slots = try allocator.alloc(Slot, options.capacity);
        for (slots) |*slot| {
            slot.* = .{
                .name = undefined,
                .name_len = 0,
                .payload = null,
                .payload_len = 0,
                .sequence = null,
            };
        }
        return .{
            .allocator = allocator,
            .slots = slots,
            .head = 0,
            .len = 0,
            .dropped = 0,
            .max_event_bytes = options.max_event_bytes,
            .max_name = options.max_name,
        };
    }

    pub fn deinit(self: *Queue) void {
        for (self.slots) |*slot| {
            if (slot.payload) |payload| self.allocator.free(payload);
        }
        self.allocator.free(self.slots);
        self.* = undefined;
    }

    /// Copies an event into the queue. Returns `error.QueueFull` when the fixed
    /// capacity is reached and increments the drop counter; the caller must not
    /// retry blindly.
    pub fn tryPush(
        self: *Queue,
        name: []const u8,
        sequence: ?i64,
        payload: []const u8,
    ) Error!void {
        if (self.len == self.slots.len) {
            self.dropped +|= 1;
            return error.QueueFull;
        }
        if (name.len > self.max_name) return error.NameTooLong;
        if (payload.len > self.max_event_bytes) return error.EventTooLarge;

        const index = (self.head + self.len) % self.slots.len;
        const slot = &self.slots[index];

        if (payload.len == 0) {
            @memset(slot.name[0..slot.name_len], 0);
            @memcpy(slot.name[0..name.len], name);
            slot.name_len = name.len;
            slot.payload_len = 0;
            slot.sequence = sequence;
            self.len += 1;
            return;
        }

        if (slot.payload) |existing| {
            if (existing.len < payload.len) {
                slot.payload = try self.allocator.realloc(existing, payload.len);
            }
        } else {
            slot.payload = try self.allocator.alloc(u8, payload.len);
        }
        const storage = slot.payload.?;
        @memcpy(storage[0..payload.len], payload);
        @memcpy(slot.name[0..name.len], name);
        slot.name_len = name.len;
        slot.payload_len = payload.len;
        slot.sequence = sequence;
        self.len += 1;
    }

    /// Returns the oldest event. The slices stay valid until `release` or until
    /// the slot is reused, whichever comes first.
    pub fn pop(self: *Queue) ?Event {
        if (self.len == 0) return null;
        const slot = &self.slots[self.head];
        const payload: []const u8 = if (slot.payload) |storage| storage[0..slot.payload_len] else &.{};
        return .{
            .name = slot.name[0..slot.name_len],
            .sequence = slot.sequence,
            .payload = payload,
        };
    }

    /// Releases the event returned by `pop`. Must be called exactly once per
    /// successful pop.
    pub fn release(self: *Queue) void {
        std.debug.assert(self.len > 0);
        self.head = (self.head + 1) % self.slots.len;
        self.len -= 1;
    }

    pub fn pending(self: *const Queue) usize {
        return self.len;
    }

    pub fn capacity(self: *const Queue) usize {
        return self.slots.len;
    }

    pub fn droppedCount(self: *const Queue) u64 {
        return self.dropped;
    }
};

test "queue preserves FIFO and copies payloads" {
    var queue = try Queue.init(std.testing.allocator, .{ .capacity = 2 });
    defer queue.deinit();

    var scratch: [32]u8 = undefined;
    @memcpy(scratch[0..5], "first");
    try queue.tryPush("EVENT_A", 1, scratch[0..5]);
    // Overwrite the caller's buffer; the queue must have copied.
    @memcpy(scratch[0..6], "second");
    try queue.tryPush("EVENT_B", 2, scratch[0..6]);

    const first = queue.pop().?;
    try std.testing.expectEqualStrings("EVENT_A", first.name);
    try std.testing.expectEqualStrings("first", first.payload);
    try std.testing.expectEqual(@as(?i64, 1), first.sequence);
    queue.release();

    const second = queue.pop().?;
    try std.testing.expectEqualStrings("EVENT_B", second.name);
    try std.testing.expectEqualStrings("second", second.payload);
    queue.release();
    try std.testing.expectEqual(@as(usize, 0), queue.pending());
}

test "full queue reports overload without blocking or growing" {
    var queue = try Queue.init(std.testing.allocator, .{ .capacity = 1 });
    defer queue.deinit();
    try queue.tryPush("A", null, "x");
    try std.testing.expectError(error.QueueFull, queue.tryPush("B", null, "y"));
    try std.testing.expectEqual(@as(u64, 1), queue.droppedCount());
    try std.testing.expectEqual(@as(usize, 1), queue.pending());
    try std.testing.expectEqual(@as(usize, 1), queue.capacity());
}

test "a retained copy survives slot reuse" {
    var queue = try Queue.init(std.testing.allocator, .{ .capacity = 1 });
    defer queue.deinit();
    try queue.tryPush("A", 1, "original");

    const borrowed = queue.pop().?;
    var owned = try borrowed.copy(std.testing.allocator);
    defer owned.deinit();
    queue.release();

    try queue.tryPush("B", 2, "replacement");
    try std.testing.expectEqualStrings("A", owned.name);
    try std.testing.expectEqualStrings("original", owned.payload);
    try std.testing.expectEqual(@as(?i64, 1), owned.sequence);
}

test "duplicate replay is delivered twice, not deduplicated" {
    var queue = try Queue.init(std.testing.allocator, .{ .capacity = 2 });
    defer queue.deinit();
    try queue.tryPush("MESSAGE_CREATE", 7, "{\"id\":\"1\"}");
    try queue.tryPush("MESSAGE_CREATE", 7, "{\"id\":\"1\"}");

    const first = queue.pop().?;
    try std.testing.expectEqual(@as(?i64, 7), first.sequence);
    queue.release();
    const second = queue.pop().?;
    try std.testing.expectEqual(@as(?i64, 7), second.sequence);
    queue.release();
    try std.testing.expectEqual(@as(usize, 0), queue.pending());
}

test "name and payload bounds are explicit" {
    var queue = try Queue.init(std.testing.allocator, .{
        .capacity = 1,
        .max_event_bytes = 8,
        .max_name = 4,
    });
    defer queue.deinit();
    try std.testing.expectError(error.NameTooLong, queue.tryPush("LONG", null, "x"));
    try std.testing.expectError(error.EventTooLarge, queue.tryPush("A", null, "123456789"));
    try std.testing.expectError(error.CapacityZero, Queue.init(std.testing.allocator, .{ .capacity = 0 }));
    try std.testing.expectError(
        error.InvalidNameLimit,
        Queue.init(std.testing.allocator, .{ .max_name = max_name_bytes + 1 }),
    );
}

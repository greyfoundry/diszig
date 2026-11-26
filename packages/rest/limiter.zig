//! Bounded REST admission control with learned buckets.
//!
//! The limiter is deliberately transport-independent and has no background
//! worker. Callers pass monotonic milliseconds, so a wall-clock jump cannot
//! change scheduling. Route and bucket tables are fixed-size; admission fails
//! explicitly when capacity is exhausted.

const std = @import("std");

pub const max_routes = 128;
pub const max_buckets = 64;
pub const max_key = 128;
pub const max_bucket_id = 64;

pub const Admission = union(enum) {
    granted,
    wait_ms: u64,
};

pub const Error = error{
    QueueFull,
    RouteTableFull,
    BucketTableFull,
    KeyTooLong,
    Canceled,
};

const RouteEntry = struct {
    key: [max_key]u8 = undefined,
    key_len: usize = 0,
    bucket: ?usize = null,
};

const Bucket = struct {
    id: [max_bucket_id]u8 = undefined,
    id_len: usize = 0,
    limit: u32 = 1,
    remaining: u32 = 1,
    reset_ms: i64 = 0,
};

pub const ResponseInfo = struct {
    bucket_id: ?[]const u8 = null,
    limit: ?u32 = null,
    remaining: ?u32 = null,
    reset_after_ms: ?u64 = null,
    retry_after_ms: ?u64 = null,
    global: bool = false,
    status: u16 = 200,
};

pub const Limiter = struct {
    routes: [max_routes]RouteEntry = undefined,
    route_count: usize = 0,
    buckets: [max_buckets]Bucket = undefined,
    bucket_count: usize = 0,
    pending: usize = 0,
    max_pending: usize,
    global_until_ms: i64 = 0,
    canceled: bool = false,

    pub fn init(max_pending: usize) Limiter {
        return .{ .max_pending = max_pending };
    }

    pub fn cancelPending(self: *Limiter) void {
        self.pending = 0;
        self.canceled = true;
    }

    pub fn resetCancel(self: *Limiter) void {
        self.canceled = false;
    }

    fn findRoute(self: *const Limiter, key: []const u8) ?*const RouteEntry {
        for (self.routes[0..self.route_count]) |*route| {
            if (std.mem.eql(u8, route.key[0..route.key_len], key)) return route;
        }
        return null;
    }

    fn findRouteMut(self: *Limiter, key: []const u8) ?*RouteEntry {
        for (self.routes[0..self.route_count]) |*route| {
            if (std.mem.eql(u8, route.key[0..route.key_len], key)) return route;
        }
        return null;
    }

    fn findBucket(self: *const Limiter, id: []const u8) ?usize {
        for (self.buckets[0..self.bucket_count], 0..) |*bucket, index| {
            if (std.mem.eql(u8, bucket.id[0..bucket.id_len], id)) return index;
        }
        return null;
    }

    fn addBucket(self: *Limiter, id: []const u8) Error!usize {
        if (id.len > max_bucket_id) return error.KeyTooLong;
        if (self.bucket_count == max_buckets) return error.BucketTableFull;
        const index = self.bucket_count;
        var bucket = &self.buckets[index];
        bucket.* = .{};
        @memcpy(bucket.id[0..id.len], id);
        bucket.id_len = id.len;
        self.bucket_count += 1;
        return index;
    }

    fn ensureRoute(self: *Limiter, key: []const u8) Error!*RouteEntry {
        if (self.findRouteMut(key)) |route| return route;
        if (key.len > max_key) return error.KeyTooLong;
        if (self.route_count == max_routes) return error.RouteTableFull;
        const route = &self.routes[self.route_count];
        route.* = .{};
        @memcpy(route.key[0..key.len], key);
        route.key_len = key.len;
        self.route_count += 1;
        return route;
    }

    fn bucketFor(self: *Limiter, route: *RouteEntry) Error!*Bucket {
        const index = route.bucket orelse blk: {
            const new_index = try self.addBucket(route.key[0..route.key_len]);
            route.bucket = new_index;
            break :blk new_index;
        };
        return &self.buckets[index];
    }

    /// Learns a bucket id from response headers and reconciles all routes that
    /// share it onto one budget.
    pub fn learn(
        self: *Limiter,
        route_key: []const u8,
        info: ResponseInfo,
        now_ms: i64,
    ) Error!void {
        const route = try self.ensureRoute(route_key);
        const id = info.bucket_id orelse route_key;
        const index = self.findBucket(id) orelse try self.addBucket(id);
        route.bucket = index;

        const bucket = &self.buckets[index];
        if (info.limit) |limit| bucket.limit = limit;
        if (info.remaining) |remaining| bucket.remaining = remaining;
        if (info.reset_after_ms) |after| bucket.reset_ms = now_ms + @as(i64, @intCast(after));

        if (info.status == 429) {
            if (info.global) {
                const after = info.retry_after_ms orelse info.reset_after_ms orelse 1000;
                self.global_until_ms = now_ms + @as(i64, @intCast(after));
            } else {
                bucket.remaining = 0;
                if (info.retry_after_ms) |after| bucket.reset_ms = now_ms + @as(i64, @intCast(after));
            }
        }
    }

    pub fn acquire(self: *Limiter, route_key: []const u8, now_ms: i64) Error!Admission {
        if (self.canceled) return error.Canceled;
        if (self.pending >= self.max_pending) return error.QueueFull;
        if (self.global_until_ms > now_ms) {
            return .{ .wait_ms = @intCast(self.global_until_ms - now_ms) };
        }

        const route = try self.ensureRoute(route_key);
        const bucket = try self.bucketFor(route);
        if (bucket.remaining == 0) {
            if (bucket.reset_ms > now_ms) return .{ .wait_ms = @intCast(bucket.reset_ms - now_ms) };
            bucket.remaining = bucket.limit;
        }
        bucket.remaining -= 1;
        self.pending += 1;
        return .granted;
    }

    pub fn release(self: *Limiter) void {
        if (self.pending > 0) self.pending -= 1;
    }
};

/// Parses a fractional seconds header into conservative milliseconds. Invalid
/// input returns null rather than guessing.
pub fn parseSecondsToMs(text: []const u8) ?u64 {
    if (text.len == 0) return null;
    var index: usize = 0;
    var whole: u64 = 0;
    while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {
        whole = whole * 10 + (text[index] - '0');
    }
    if (index == 0) return null;

    var millis = whole * 1000;
    if (index < text.len and text[index] == '.') {
        index += 1;
        var digits: usize = 0;
        var fraction: u64 = 0;
        var remainder = false;
        while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {
            if (digits < 3) {
                fraction = fraction * 10 + (text[index] - '0');
                digits += 1;
            } else if (text[index] != '0') {
                remainder = true;
            }
        }
        while (digits < 3) : (digits += 1) fraction *= 10;
        millis += fraction;
        if (remainder) millis += 1;
    }
    if (index != text.len) return null;
    return millis;
}

test "two routes that discover the same bucket share one budget" {
    var limiter = Limiter.init(4);
    try limiter.learn("GET /a guild=1", .{ .bucket_id = "shared", .limit = 1, .remaining = 1, .reset_after_ms = 1000 }, 0);
    try limiter.learn("GET /b guild=1", .{ .bucket_id = "shared" }, 0);
    try std.testing.expectEqual(@as(usize, 1), limiter.bucket_count);

    try std.testing.expect(limiter.acquire("GET /a guild=1", 0) == .granted);
    limiter.release();
    const admission = try limiter.acquire("GET /b guild=1", 0);
    try std.testing.expect(admission == .wait_ms);
}

test "global 429 pauses every governed queue" {
    var limiter = Limiter.init(4);
    try limiter.learn("GET /a", .{ .status = 429, .global = true, .retry_after_ms = 1500 }, 1000);
    const admission = try limiter.acquire("GET /b", 1200);
    try std.testing.expect(admission == .wait_ms);
}

test "queue full and cancellation are explicit" {
    var limiter = Limiter.init(1);
    try std.testing.expect(limiter.acquire("GET /a", 0) == .granted);
    try std.testing.expectError(error.QueueFull, limiter.acquire("GET /b", 0));
    limiter.cancelPending();
    try std.testing.expectError(error.Canceled, limiter.acquire("GET /a", 0));
}

test "fractional seconds round up conservatively" {
    try std.testing.expectEqual(@as(?u64, 1500), parseSecondsToMs("1.5"));
    try std.testing.expectEqual(@as(?u64, 1), parseSecondsToMs("0.0001"));
    try std.testing.expectEqual(@as(?u64, 64_570), parseSecondsToMs("64.570"));
    try std.testing.expectEqual(@as(?u64, null), parseSecondsToMs("1.2x"));
}

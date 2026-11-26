//! Explicit cursor pagination with bounded pages and duplicate detection.
//!
//! There is no universal before/after iterator: the caller chooses a direction
//! and supplies the last ID from the previous page for that endpoint.

const std = @import("std");

pub const Direction = enum { before, after };

pub const PageRequest = struct {
    before: ?u64 = null,
    after: ?u64 = null,
    limit: u16,
};

pub const Error = error{
    DuplicateCursor,
    PageLimit,
    ItemLimit,
    Canceled,
};

pub const Paginator = struct {
    direction: Direction,
    limit: u16,
    max_pages: u16 = 100,
    max_items: u32 = 10_000,
    pages: u16 = 0,
    items: u32 = 0,
    seen: [64]u64 = undefined,
    seen_len: usize = 0,
    canceled: bool = false,

    pub fn init(direction: Direction, limit: u16) Paginator {
        return .{ .direction = direction, .limit = limit };
    }

    pub fn cancel(self: *Paginator) void {
        self.canceled = true;
    }

    fn remember(self: *Paginator, cursor: u64) Error!void {
        for (self.seen[0..self.seen_len]) |value| {
            if (value == cursor) return error.DuplicateCursor;
        }
        if (self.seen_len == self.seen.len) {
            // The ring is full; forget the oldest cursor but keep the page bound
            // as the primary stop condition.
            var index: usize = 1;
            while (index < self.seen.len) : (index += 1) self.seen[index - 1] = self.seen[index];
            self.seen_len -= 1;
        }
        self.seen[self.seen_len] = cursor;
        self.seen_len += 1;
    }

    /// Returns the next request, or null when the last page was empty or the
    /// bounds were reached. A repeated last ID is an explicit error.
    pub fn next(self: *Paginator, last_id: ?u64, last_page_len: usize) Error!?PageRequest {
        if (self.canceled) return error.Canceled;
        if (self.pages == 0) {
            self.pages = 1;
            return .{ .limit = self.limit };
        }
        if (last_page_len == 0) return null;
        if (self.pages >= self.max_pages) return error.PageLimit;
        if (self.items >= self.max_items) return error.ItemLimit;

        const id = last_id orelse return error.DuplicateCursor;
        try self.remember(id);

        self.pages += 1;
        self.items +|= @intCast(last_page_len);
        return switch (self.direction) {
            .before => .{ .before = id, .limit = self.limit },
            .after => .{ .after = id, .limit = self.limit },
        };
    }
};

test "repeated cursor stops explicitly" {
    var pager = Paginator.init(.after, 50);
    _ = try pager.next(null, 0);
    _ = try pager.next(10, 2);
    try std.testing.expectError(error.DuplicateCursor, pager.next(10, 2));
}

test "empty final page terminates" {
    var pager = Paginator.init(.before, 50);
    _ = try pager.next(null, 0);
    _ = try pager.next(10, 1);
    try std.testing.expectEqual(@as(?PageRequest, null), try pager.next(0, 0));
}

test "cancellation prevents another request" {
    var pager = Paginator.init(.after, 50);
    pager.cancel();
    try std.testing.expectError(error.Canceled, pager.next(null, 0));
}

test "page bound is finite" {
    var pager = Paginator.init(.after, 50);
    pager.max_pages = 2;
    _ = try pager.next(null, 0);
    _ = try pager.next(10, 1);
    try std.testing.expectError(error.PageLimit, pager.next(11, 1));
}

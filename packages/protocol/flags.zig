//! Generic integer bit flags that preserve unknown bits.
//!
//! Discord sends permissions and other flag values as decimal strings. Unknown
//! bits are kept as-is so a compatible reader does not discard a future flag.

const std = @import("std");

pub fn Flags(comptime Int: type) type {
    return struct {
        bits: Int,

        pub const empty: @This() = .{ .bits = 0 };
        pub const all: @This() = .{ .bits = std.math.maxInt(Int) };

        pub fn init(bits: Int) @This() {
            return .{ .bits = bits };
        }

        pub fn has(self: @This(), flag: Int) bool {
            return self.bits & flag != 0;
        }

        pub fn hasAll(self: @This(), mask: Int) bool {
            return self.bits & mask == mask;
        }

        pub fn hasAny(self: @This(), mask: Int) bool {
            return self.bits & mask != 0;
        }

        pub fn add(self: *@This(), flag: Int) void {
            self.bits |= flag;
        }

        pub fn remove(self: *@This(), flag: Int) void {
            self.bits &= ~flag;
        }

        pub fn toggle(self: *@This(), flag: Int) void {
            self.bits ^= flag;
        }

        pub fn unionWith(self: @This(), other: @This()) @This() {
            return .{ .bits = self.bits | other.bits };
        }

        pub fn intersect(self: @This(), other: @This()) @This() {
            return .{ .bits = self.bits & other.bits };
        }

        pub fn eql(self: @This(), other: @This()) bool {
            return self.bits == other.bits;
        }

        pub fn parseDecimal(text: []const u8) error{ Empty, InvalidCharacter, Overflow }!@This() {
            if (text.len == 0) return error.Empty;
            for (text) |c| {
                if (!std.ascii.isDigit(c)) return error.InvalidCharacter;
            }
            const value = std.fmt.parseInt(Int, text, 10) catch |err| switch (err) {
                error.Overflow => return error.Overflow,
                error.InvalidCharacter => return error.InvalidCharacter,
            };
            return .{ .bits = value };
        }

        pub fn writeDecimal(self: @This(), writer: *std.Io.Writer) std.Io.Writer.Error!void {
            try writer.print("{d}", .{self.bits});
        }
    };
}

test "unknown high bits survive union and decimal round trip" {
    const Bits = Flags(u64);
    const future = Bits{ .bits = 1 << 63 };
    const current = Bits{ .bits = 0b1010 };
    const combined = current.unionWith(future);
    try std.testing.expect(combined.has(1 << 63));
    try std.testing.expect(combined.has(1 << 1));

    var buffer: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try combined.writeDecimal(&writer);
    const parsed = try Bits.parseDecimal(writer.buffered());
    try std.testing.expect(parsed.eql(combined));
}

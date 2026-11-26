//! Discord Snowflake identifiers.
//!
//! Snowflakes are unsigned 64-bit values but are always sent as decimal strings
//! by the HTTP API. Parsing is strict decimal only; formatting is decimal.

const std = @import("std");

pub const Snowflake = struct {
    value: u64,

    /// First second of 2015, in Unix milliseconds.
    pub const epoch_ms: u64 = 1420070400000;

    pub const ParseError = error{
        Empty,
        InvalidCharacter,
        Overflow,
    };

    pub const TimestampError = error{
        BeforeEpoch,
        OutOfRange,
    };

    pub fn fromU64(value: u64) Snowflake {
        return .{ .value = value };
    }

    pub fn toU64(self: Snowflake) u64 {
        return self.value;
    }

    pub fn parse(text: []const u8) ParseError!Snowflake {
        if (text.len == 0) return error.Empty;
        for (text) |c| {
            if (!std.ascii.isDigit(c)) return error.InvalidCharacter;
        }
        const value = std.fmt.parseInt(u64, text, 10) catch |err| switch (err) {
            error.Overflow => return error.Overflow,
            error.InvalidCharacter => return error.InvalidCharacter,
        };
        return .{ .value = value };
    }

    pub fn writeDecimal(self: Snowflake, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{d}", .{self.value});
    }

    /// Milliseconds since the Unix epoch encoded in the upper 42 bits.
    pub fn timestampMs(self: Snowflake) u64 {
        return (self.value >> 22) + epoch_ms;
    }

    /// Builds a Snowflake whose timestamp is `unix_ms` and whose worker,
    /// process and increment bits are zero.
    pub fn fromTimestampMs(unix_ms: u64) TimestampError!Snowflake {
        if (unix_ms < epoch_ms) return error.BeforeEpoch;
        const delta = unix_ms - epoch_ms;
        const max_delta = std.math.maxInt(u64) >> 22;
        if (delta > max_delta) return error.OutOfRange;
        return .{ .value = delta << 22 };
    }

    pub fn workerId(self: Snowflake) u5 {
        return @truncate((self.value & 0x3E0000) >> 17);
    }

    pub fn processId(self: Snowflake) u5 {
        return @truncate((self.value & 0x1F000) >> 12);
    }

    pub fn increment(self: Snowflake) u12 {
        return @truncate(self.value & 0xFFF);
    }
};

test "maximum u64 decimal parses losslessly" {
    const id = try Snowflake.parse("18446744073709551615");
    try std.testing.expectEqual(std.math.maxInt(u64), id.toU64());
}

test "one past u64 maximum overflows" {
    try std.testing.expectError(
        error.Overflow,
        Snowflake.parse("18446744073709551616"),
    );
}

test "non-decimal and empty input are rejected" {
    try std.testing.expectError(error.Empty, Snowflake.parse(""));
    try std.testing.expectError(error.InvalidCharacter, Snowflake.parse(" 1"));
    try std.testing.expectError(error.InvalidCharacter, Snowflake.parse("1 "));
    try std.testing.expectError(error.InvalidCharacter, Snowflake.parse("+1"));
    try std.testing.expectError(error.InvalidCharacter, Snowflake.parse("-1"));
    try std.testing.expectError(error.InvalidCharacter, Snowflake.parse("1x"));
}

test "decimal formatting round trips" {
    const id = try Snowflake.parse("175928847299117063");
    var buffer: [32]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try id.writeDecimal(&writer);
    try std.testing.expectEqualStrings("175928847299117063", writer.buffered());
}

test "timestamp round trip and epoch rejection" {
    const epoch = try Snowflake.fromTimestampMs(Snowflake.epoch_ms);
    try std.testing.expectEqual(@as(u64, 0), epoch.toU64());
    try std.testing.expectEqual(Snowflake.epoch_ms, epoch.timestampMs());

    const one_ms = try Snowflake.fromTimestampMs(Snowflake.epoch_ms + 1);
    try std.testing.expectEqual(@as(u64, 1) << 22, one_ms.toU64());
    try std.testing.expectEqual(Snowflake.epoch_ms + 1, one_ms.timestampMs());

    try std.testing.expectError(error.BeforeEpoch, Snowflake.fromTimestampMs(Snowflake.epoch_ms - 1));
}

test "worker, process and increment bits match the documented layout" {
    const id = Snowflake.fromU64((@as(u64, 7) << 17) | (@as(u64, 9) << 12) | 42);
    try std.testing.expectEqual(@as(u5, 7), id.workerId());
    try std.testing.expectEqual(@as(u5, 9), id.processId());
    try std.testing.expectEqual(@as(u12, 42), id.increment());
}

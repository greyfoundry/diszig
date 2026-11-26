//! Discord ISO8601 timestamps.
//!
//! Wire values are UTC instants such as `2021-01-01T00:00:00.000000+00:00`.
//! Parsing is strict: a full date, time and timezone are required. Fractions
//! are truncated to milliseconds. Formatting emits UTC with milliseconds.

const std = @import("std");

pub const Timestamp = struct {
    unix_ms: i64,

    pub const ParseError = error{
        InvalidFormat,
        InvalidDate,
        InvalidTime,
        OutOfRange,
    };

    pub fn fromUnixMs(unix_ms: i64) Timestamp {
        return .{ .unix_ms = unix_ms };
    }

    pub fn toUnixMs(self: Timestamp) i64 {
        return self.unix_ms;
    }

    pub fn toUnixSeconds(self: Timestamp) i64 {
        return @divFloor(self.unix_ms, 1000);
    }

    pub fn parse(text: []const u8) ParseError!Timestamp {
        if (text.len < 20) return error.InvalidFormat;
        if (!std.ascii.isDigit(text[0]) or !std.ascii.isDigit(text[1]) or
            !std.ascii.isDigit(text[2]) or !std.ascii.isDigit(text[3]))
            return error.InvalidFormat;
        if (text[4] != '-' or text[7] != '-' or text[10] != 'T' or
            text[13] != ':' or text[16] != ':')
            return error.InvalidFormat;

        const year = parseFix(text[0..4]) orelse return error.InvalidFormat;
        const month = parseFix(text[5..7]) orelse return error.InvalidFormat;
        const day = parseFix(text[8..10]) orelse return error.InvalidFormat;
        const hour = parseFix(text[11..13]) orelse return error.InvalidFormat;
        const minute = parseFix(text[14..16]) orelse return error.InvalidFormat;
        const second = parseFix(text[17..19]) orelse return error.InvalidFormat;

        if (year < 1 or year > 9999) return error.InvalidDate;
        if (month < 1 or month > 12) return error.InvalidDate;
        const max_day = daysInMonth(year, month);
        if (day < 1 or day > max_day) return error.InvalidDate;
        if (hour > 23 or minute > 59 or second > 59) return error.InvalidTime;

        var index: usize = 19;
        var millis: i64 = 0;
        if (index < text.len and text[index] == '.') {
            index += 1;
            const start = index;
            while (index < text.len and std.ascii.isDigit(text[index])) : (index += 1) {}
            const digits = index - start;
            if (digits == 0 or digits > 9) return error.InvalidFormat;
            var value: i64 = 0;
            var count: usize = 0;
            while (count < 3) : (count += 1) {
                value *= 10;
                if (start + count < index) {
                    value += text[start + count] - '0';
                }
            }
            millis = value;
        }

        if (index >= text.len) return error.InvalidFormat;

        var offset_seconds: i64 = 0;
        if (text[index] == 'Z' or text[index] == 'z') {
            index += 1;
        } else if (text[index] == '+' or text[index] == '-') {
            const sign: i64 = if (text[index] == '+') 1 else -1;
            index += 1;
            if (index + 5 > text.len or text[index + 2] != ':') return error.InvalidFormat;
            const off_hour = parseFix(text[index..][0..2]) orelse return error.InvalidFormat;
            const off_minute = parseFix(text[index + 3 ..][0..2]) orelse return error.InvalidFormat;
            if (off_hour > 23 or off_minute > 59) return error.InvalidFormat;
            offset_seconds = sign * (@as(i64, off_hour) * 3600 + @as(i64, off_minute) * 60);
            index += 5;
        } else {
            return error.InvalidFormat;
        }
        if (index != text.len) return error.InvalidFormat;

        const days = daysFromCivil(year, month, day);
        const seconds = days * 86400 + @as(i64, hour) * 3600 + @as(i64, minute) * 60 + second - offset_seconds;
        const unix_ms = std.math.mul(i64, seconds, 1000) catch return error.OutOfRange;
        return .{ .unix_ms = std.math.add(i64, unix_ms, millis) catch return error.OutOfRange };
    }

    pub fn writeIso8601(self: Timestamp, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const seconds = @divFloor(self.unix_ms, 1000);
        const millis: i64 = @mod(self.unix_ms, 1000);
        const days = @divFloor(seconds, 86400);
        var day_seconds = @mod(seconds, 86400);
        if (day_seconds < 0) day_seconds += 86400;

        const civil = civilFromDays(days);
        const hour: u8 = @intCast(@divFloor(day_seconds, 3600));
        const minute: u8 = @intCast(@divFloor(@mod(day_seconds, 3600), 60));
        const second: u8 = @intCast(@mod(day_seconds, 60));

        try writePadded(writer, @intCast(civil.year), 4);
        try writer.writeByte('-');
        try writePadded(writer, civil.month, 2);
        try writer.writeByte('-');
        try writePadded(writer, civil.day, 2);
        try writer.writeByte('T');
        try writePadded(writer, hour, 2);
        try writer.writeByte(':');
        try writePadded(writer, minute, 2);
        try writer.writeByte(':');
        try writePadded(writer, second, 2);
        try writer.writeByte('.');
        try writePadded(writer, @intCast(millis), 3);
        try writer.writeByte('Z');
    }
};

fn writePadded(writer: *std.Io.Writer, value: u32, width: usize) std.Io.Writer.Error!void {
    var buffer: [4]u8 = undefined;
    var remaining = value;
    var index = width;
    while (index > 0) {
        index -= 1;
        buffer[index] = '0' + @as(u8, @intCast(remaining % 10));
        remaining /= 10;
    }
    try writer.writeAll(buffer[0..width]);
}

fn parseFix(text: []const u8) ?u16 {
    var value: u16 = 0;
    for (text) |c| {
        if (!std.ascii.isDigit(c)) return null;
        value = value * 10 + (c - '0');
    }
    return value;
}

fn isLeapYear(year: u16) bool {
    return (year % 4 == 0 and year % 100 != 0) or year % 400 == 0;
}

fn daysInMonth(year: u16, month: u16) u16 {
    return switch (month) {
        1, 3, 5, 7, 8, 10, 12 => 31,
        4, 6, 9, 11 => 30,
        2 => if (isLeapYear(year)) 29 else 28,
        else => 0,
    };
}

/// Days since 1970-01-01, proleptic Gregorian calendar.
fn daysFromCivil(year_in: u16, month: u16, day: u16) i64 {
    var year: i64 = year_in;
    const m: i64 = month;
    year -= if (m <= 2) 1 else 0;
    const era = @divFloor(year, 400);
    const yoe = year - era * 400;
    const mp = if (m > 2) m - 3 else m + 9;
    const doy = @divFloor(153 * mp + 2, 5) + @as(i64, day) - 1;
    const doe = yoe * 365 + @divFloor(yoe, 4) - @divFloor(yoe, 100) + doy;
    return era * 146097 + doe - 719468;
}

const Civil = struct { year: i64, month: u16, day: u16 };

fn civilFromDays(days: i64) Civil {
    const z = days + 719468;
    const era = @divFloor(z, 146097);
    const doe = z - era * 146097;
    const yoe = @divFloor(doe - @divFloor(doe, 1460) + @divFloor(doe, 36524) - @divFloor(doe, 146096), 365);
    var year = yoe + era * 400;
    const doy = doe - (365 * yoe + @divFloor(yoe, 4) - @divFloor(yoe, 100));
    const mp = @divFloor(5 * doy + 2, 153);
    const day = doy - @divFloor(153 * mp + 2, 5) + 1;
    const month = if (mp < 10) mp + 3 else mp - 9;
    year += if (month <= 2) 1 else 0;
    return .{ .year = year, .month = @intCast(month), .day = @intCast(day) };
}

test "epoch and UTC round trip" {
    const epoch = try Timestamp.parse("1970-01-01T00:00:00Z");
    try std.testing.expectEqual(@as(i64, 0), epoch.unix_ms);

    var buffer: [40]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try epoch.writeIso8601(&writer);
    try std.testing.expectEqualStrings("1970-01-01T00:00:00.000Z", writer.buffered());
}

test "fractions truncate to milliseconds and offsets normalize to UTC" {
    const with_micros = try Timestamp.parse("2021-01-01T00:00:00.123456+00:00");
    try std.testing.expectEqual(@as(i64, 1609459200123), with_micros.unix_ms);

    const offset = try Timestamp.parse("2021-01-01T01:00:00+01:00");
    try std.testing.expectEqual(@as(i64, 1609459200000), offset.unix_ms);
}

test "date formatting round trips across leap day" {
    const leap = try Timestamp.parse("2020-02-29T23:59:59.999Z");
    var buffer: [40]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try leap.writeIso8601(&writer);
    const again = try Timestamp.parse(writer.buffered());
    try std.testing.expectEqual(leap.unix_ms, again.unix_ms);
}

test "malformed timestamps fail explicitly" {
    try std.testing.expectError(error.InvalidFormat, Timestamp.parse(""));
    try std.testing.expectError(error.InvalidFormat, Timestamp.parse("2021-01-01T00:00:00"));
    try std.testing.expectError(error.InvalidFormat, Timestamp.parse("2021-01-01 00:00:00Z"));
    try std.testing.expectError(error.InvalidDate, Timestamp.parse("2021-13-01T00:00:00Z"));
    try std.testing.expectError(error.InvalidDate, Timestamp.parse("2021-02-29T00:00:00Z"));
    try std.testing.expectError(error.InvalidTime, Timestamp.parse("2021-01-01T24:00:00Z"));
    try std.testing.expectError(error.InvalidFormat, Timestamp.parse("2021-01-01T00:00:00+1:00"));
    try std.testing.expectError(error.InvalidFormat, Timestamp.parse("2021-01-01T00:00:00Zjunk"));
}

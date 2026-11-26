//! Audit-log reason encoding.
//!
//! Discord accepts the reason in the `X-Audit-Log-Reason` header, URL-encoded.
//! The documented limit is 512 characters; this module uses a conservative
//! 512-byte bound because reason input is UTF-8.

const std = @import("std");

pub const max_reason_bytes = 512;

pub const Error = error{
    EmptyReason,
    ReasonTooLong,
    WriteFailed,
};

fn isUnreserved(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '-' or c == '.' or c == '_' or c == '~';
}

pub fn encode(writer: *std.Io.Writer, reason: []const u8) Error!void {
    if (reason.len == 0) return error.EmptyReason;
    if (reason.len > max_reason_bytes) return error.ReasonTooLong;

    const hex = "0123456789ABCDEF";
    for (reason) |c| {
        if (isUnreserved(c)) {
            writer.writeByte(c) catch return error.WriteFailed;
        } else {
            writer.writeAll(&[_]u8{ '%', hex[c >> 4], hex[c & 0x0f] }) catch return error.WriteFailed;
        }
    }
}

test "unicode audit reasons are percent encoded" {
    var buffer: [128]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try encode(&writer, "test \u{2713}");
    try std.testing.expectEqualStrings("test%20%E2%9C%93", writer.buffered());
}

test "empty and oversized reasons fail" {
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    try std.testing.expectError(error.EmptyReason, encode(&writer, ""));

    var long: [max_reason_bytes + 1]u8 = undefined;
    @memset(&long, 'a');
    try std.testing.expectError(error.ReasonTooLong, encode(&writer, &long));
}

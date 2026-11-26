//! Inbound field presence: absent, explicit null and a concrete value are
//! distinct wire states. Outbound request structs must not reuse this type.

const std = @import("std");

pub fn Presence(comptime T: type) type {
    return union(enum) {
        absent: void,
        null: void,
        value: T,

        pub fn jsonParse(
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) !@This() {
            switch (try source.peekNextTokenType()) {
                .null => {
                    _ = try source.next();
                    return .null;
                },
                else => return .{ .value = try std.json.innerParse(T, allocator, source, options) },
            }
        }

        pub fn isAbsent(self: @This()) bool {
            return switch (self) {
                .absent => true,
                else => false,
            };
        }

        pub fn isNull(self: @This()) bool {
            return switch (self) {
                .null => true,
                else => false,
            };
        }

        pub fn get(self: @This()) ?T {
            return switch (self) {
                .value => |value| value,
                else => null,
            };
        }
    };
}

test "absent, null and zero are distinct" {
    const Field = Presence(i64);
    try std.testing.expect((Field{ .absent = {} }).isAbsent());
    try std.testing.expect((Field{ .null = {} }).isNull());
    try std.testing.expectEqual(@as(?i64, 0), (Field{ .value = 0 }).get());
}

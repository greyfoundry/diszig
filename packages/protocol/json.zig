//! JSON mapping helpers for tolerant inbound decoding and strict outbound
//! validation.
//!
//! Zig's `std.json` already handles unknown fields, optional values and
//! allocator lifetimes. These helpers add the Discord-specific distinctions
//! that a plain `?T` cannot express:
//!
//! - absent, explicit null and a value are separate states;
//! - an unknown inbound enum value is retained and recoverable;
//! - a one-of object must contain exactly one branch;
//! - input size can be bounded before parsing.

const std = @import("std");

/// Inbound-only presence. A field of this type must have a `.absent` default
/// so a missing key is distinguishable from an explicit `null` and a value.
///
/// Do not use this type for outbound requests: it intentionally has no
/// stringify implementation. Request structs should omit fields or use `?T`
/// according to the endpoint contract.
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
    };
}

/// Inbound integer enum that keeps an unknown value instead of failing the
/// whole payload. `known()` maps a recognized value or returns null.
///
/// Outbound code must use the strict enum type, not this wrapper.
pub fn InboundEnum(comptime E: type) type {
    return struct {
        raw: std.json.Value,

        pub fn jsonParse(
            allocator: std.mem.Allocator,
            source: anytype,
            options: std.json.ParseOptions,
        ) !@This() {
            return .{ .raw = try std.json.innerParse(std.json.Value, allocator, source, options) };
        }

        pub fn known(self: @This()) ?E {
            return switch (self.raw) {
                .integer => |value| std.enums.fromInt(E, value),
                else => null,
            };
        }
    };
}

/// Enforces an OpenAPI `x-discord-union: oneOf` object shape: exactly one of
/// the named keys must be present. Used after `std.json` has produced an
/// object, before the caller interprets the branch.
pub fn requireExactlyOne(object: std.json.ObjectMap, names: []const []const u8) !void {
    var count: usize = 0;
    for (names) |name| {
        if (object.get(name) != null) count += 1;
    }
    if (count != 1) return error.InvalidUnionBranch;
}

/// Parses only after checking the raw byte length. This bounds untrusted input
/// before the parser allocates.
pub fn parseBounded(
    comptime T: type,
    allocator: std.mem.Allocator,
    bytes: []const u8,
    max_bytes: usize,
    options: std.json.ParseOptions,
) !std.json.Parsed(T) {
    if (bytes.len > max_bytes) return error.InputTooLarge;
    return std.json.parseFromSlice(T, allocator, bytes, options);
}

const ChannelType = enum(u8) {
    text = 0,
    voice = 2,
};

const Patch = struct {
    name: Presence([]const u8) = .absent,
    topic: Presence([]const u8) = .absent,
};

test "missing, null and value are distinct" {
    var missing = try std.json.parseFromSlice(Patch, std.testing.allocator,
        \\{"name":"general"}
    , .{});
    defer missing.deinit();
    try std.testing.expect(missing.value.name == .value);
    try std.testing.expectEqualStrings("general", missing.value.name.value);
    try std.testing.expect(missing.value.topic == .absent);

    var explicit_null = try std.json.parseFromSlice(Patch, std.testing.allocator,
        \\{"name":null}
    , .{});
    defer explicit_null.deinit();
    try std.testing.expect(explicit_null.value.name == .null);
    try std.testing.expect(explicit_null.value.topic == .absent);

    var absent = try std.json.parseFromSlice(Patch, std.testing.allocator,
        \\{}
    , .{});
    defer absent.deinit();
    try std.testing.expect(absent.value.name == .absent);
}

test "unknown inbound enum is retained and recoverable" {
    var known = try std.json.parseFromSlice(InboundEnum(ChannelType), std.testing.allocator, "0", .{});
    defer known.deinit();
    try std.testing.expectEqual(ChannelType.text, known.value.known().?);

    var unknown = try std.json.parseFromSlice(InboundEnum(ChannelType), std.testing.allocator, "99", .{});
    defer unknown.deinit();
    try std.testing.expectEqual(@as(?ChannelType, null), unknown.value.known());
    try std.testing.expectEqual(@as(i64, 99), unknown.value.raw.integer);
}

test "one-of object requires exactly one branch" {
    var one = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"string":"x"}
    , .{});
    defer one.deinit();
    try requireExactlyOne(one.value.object, &.{ "string", "number" });

    var two = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"string":"x","number":2}
    , .{});
    defer two.deinit();
    try std.testing.expectError(
        error.InvalidUnionBranch,
        requireExactlyOne(two.value.object, &.{ "string", "number" }),
    );

    var none = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{}
    , .{});
    defer none.deinit();
    try std.testing.expectError(
        error.InvalidUnionBranch,
        requireExactlyOne(none.value.object, &.{ "string", "number" }),
    );
}

test "bounded parse rejects oversize input before allocation" {
    const bytes = "{\"name\":\"general\"}";
    try std.testing.expectError(
        error.InputTooLarge,
        parseBounded(Patch, std.testing.allocator, bytes, 4, .{}),
    );

    var parsed = try parseBounded(Patch, std.testing.allocator, bytes, 1024, .{});
    defer parsed.deinit();
    try std.testing.expect(parsed.value.name == .value);
}

test "unknown inbound fields are ignored only when requested" {
    const bytes =
        \\{"name":"general","future_field":{"nested":true}}
    ;
    var parsed = try std.json.parseFromSlice(Patch, std.testing.allocator, bytes, .{
        .ignore_unknown_fields = true,
    });
    defer parsed.deinit();
    try std.testing.expect(parsed.value.name == .value);
}

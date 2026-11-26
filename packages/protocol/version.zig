//! Explicit Discord protocol versions.
//!
//! REST, Gateway, Voice Gateway, voice encryption, OpenAPI and Diszig SDK
//! versions are independent. This module currently defines only the REST API
//! version because that is the implemented transport.

const std = @import("std");

pub const ApiVersion = enum(u8) {
    v9 = 9,
    v10 = 10,

    pub const default: ApiVersion = .v10;

    pub fn path(self: ApiVersion) []const u8 {
        return switch (self) {
            .v9 => "v9",
            .v10 => "v10",
        };
    }

    pub fn baseUrl(self: ApiVersion) []const u8 {
        return switch (self) {
            .v9 => "https://discord.com/api/v9",
            .v10 => "https://discord.com/api/v10",
        };
    }

    /// Parses an explicit version. No fallback or implicit upgrade is applied.
    pub fn parse(text: []const u8) ?ApiVersion {
        if (std.mem.eql(u8, text, "v9") or std.mem.eql(u8, text, "9")) return .v9;
        if (std.mem.eql(u8, text, "v10") or std.mem.eql(u8, text, "10")) return .v10;
        return null;
    }

    pub fn isDefault(self: ApiVersion) bool {
        return self == default;
    }
};

test "v10 is the default and versions parse explicitly" {
    try std.testing.expectEqual(ApiVersion.v10, ApiVersion.default);
    try std.testing.expectEqualStrings("https://discord.com/api/v10", ApiVersion.default.baseUrl());
    try std.testing.expectEqual(@as(?ApiVersion, .v9), ApiVersion.parse("v9"));
    try std.testing.expectEqual(@as(?ApiVersion, .v10), ApiVersion.parse("10"));
    try std.testing.expectEqual(@as(?ApiVersion, null), ApiVersion.parse("v8"));
}

//! Commands wire contracts, dependency layer 0, batch 1.

const std = @import("std");
const json = @import("../json.zig");

pub const Error = error{
    InvalidName,
    TooManyLocalizations,
    InvalidLocalization,
    StringValueTooLong,
};

pub const ApplicationCommandHandler = enum(u8) {
    app_handler = 1,
    discord_launch_activity = 2,
};

pub const InboundApplicationCommandHandler = json.InboundEnum(ApplicationCommandHandler);

pub const ApplicationCommandOptionType = enum(u8) {
    sub_command = 1,
    sub_command_group = 2,
    string = 3,
    integer = 4,
    boolean = 5,
    user = 6,
    channel = 7,
    role = 8,
    mentionable = 9,
    number = 10,
    attachment = 11,
};

pub const InboundApplicationCommandOptionType = json.InboundEnum(ApplicationCommandOptionType);

pub const ApplicationCommandPermissionType = enum(u8) {
    role = 1,
    user = 2,
    channel = 3,
};

pub const InboundApplicationCommandPermissionType = json.InboundEnum(ApplicationCommandPermissionType);

pub const ApplicationCommandType = enum(u8) {
    chat = 1,
    user = 2,
    message = 3,
    primary_entry_point = 4,
};

pub const InboundApplicationCommandType = json.InboundEnum(ApplicationCommandType);

pub const ApplicationCommandOptionNumberChoice = struct {
    name: []const u8,
    /// Raw map for batch 1; validated for count and string values.
    name_localizations: ?std.json.Value = null,
    value: f64,

    pub fn validate(self: ApplicationCommandOptionNumberChoice) Error!void {
        try validateName(self.name);
        try validateLocalizations(self.name_localizations);
    }
};

pub const ApplicationCommandOptionNumberChoiceResponse = struct {
    name: []const u8,
    name_localized: ?[]const u8 = null,
    name_localizations: ?std.json.Value = null,
    value: f64,
};

pub const ApplicationCommandOptionStringChoice = struct {
    name: []const u8,
    name_localizations: ?std.json.Value = null,
    value: []const u8,

    pub fn validate(self: ApplicationCommandOptionStringChoice) Error!void {
        try validateName(self.name);
        try validateLocalizations(self.name_localizations);
        if (self.value.len > 6000) return error.StringValueTooLong;
    }
};

pub const ApplicationCommandOptionStringChoiceResponse = struct {
    name: []const u8,
    name_localized: ?[]const u8 = null,
    name_localizations: ?std.json.Value = null,
    value: []const u8,
};

fn validateName(name: []const u8) Error!void {
    if (name.len == 0 or name.len > 100) return error.InvalidName;
}

fn validateLocalizations(value: ?std.json.Value) Error!void {
    const map = value orelse return;
    switch (map) {
        .object => |object| {
            if (object.count() > 34) return error.TooManyLocalizations;
            var iterator = object.iterator();
            while (iterator.next()) |entry| {
                switch (entry.value_ptr.*) {
                    .string => |text| {
                        if (text.len == 0 or text.len > 100) return error.InvalidLocalization;
                    },
                    else => return error.InvalidLocalization,
                }
            }
        },
        .null => {},
        else => return error.InvalidLocalization,
    }
}

test "command enum values" {
    try std.testing.expectEqual(@as(u8, 2), @backingInt(ApplicationCommandHandler.discord_launch_activity));
    try std.testing.expectEqual(@as(u8, 11), @backingInt(ApplicationCommandOptionType.attachment));
    try std.testing.expectEqual(@as(u8, 3), @backingInt(ApplicationCommandPermissionType.channel));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(ApplicationCommandType.primary_entry_point));
}

test "choice validation enforces name, localization and value bounds" {
    var parsed = try std.json.parseFromSlice(ApplicationCommandOptionStringChoice, std.testing.allocator,
        \\{"name":"choice","name_localizations":{"fr":"choix"},"value":"v"}
    , .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    try parsed.value.validate();

    const long_value: [6001]u8 = @splat('x');
    try std.testing.expectError(
        error.StringValueTooLong,
        (ApplicationCommandOptionStringChoice{ .name = "n", .value = &long_value }).validate(),
    );
    try std.testing.expectError(
        error.InvalidName,
        (ApplicationCommandOptionStringChoice{ .name = "", .value = "v" }).validate(),
    );
}

test "unknown inbound command enum is retained" {
    var parsed = try std.json.parseFromSlice(InboundApplicationCommandType, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?ApplicationCommandType, null), parsed.value.known());
    try std.testing.expectEqual(@as(i64, 99), parsed.value.raw.integer);
}

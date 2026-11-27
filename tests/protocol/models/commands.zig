//! Commands model batch 1 contracts.

const std = @import("std");
const diszig = @import("diszig");
const commands = diszig.protocol.models.commands;

test "every listed schema is exported" {
    _ = commands.ApplicationCommandHandler;
    _ = commands.ApplicationCommandOptionNumberChoice;
    _ = commands.ApplicationCommandOptionNumberChoiceResponse;
    _ = commands.ApplicationCommandOptionStringChoice;
    _ = commands.ApplicationCommandOptionStringChoiceResponse;
    _ = commands.ApplicationCommandOptionType;
    _ = commands.ApplicationCommandPermissionType;
    _ = commands.ApplicationCommandType;
}

test "enum values match the pinned schema" {
    try std.testing.expectEqual(@as(u8, 1), @backingInt(commands.ApplicationCommandHandler.app_handler));
    try std.testing.expectEqual(@as(u8, 2), @backingInt(commands.ApplicationCommandHandler.discord_launch_activity));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(commands.ApplicationCommandOptionType.sub_command));
    try std.testing.expectEqual(@as(u8, 10), @backingInt(commands.ApplicationCommandOptionType.number));
    try std.testing.expectEqual(@as(u8, 11), @backingInt(commands.ApplicationCommandOptionType.attachment));
    try std.testing.expectEqual(@as(u8, 1), @backingInt(commands.ApplicationCommandPermissionType.role));
    try std.testing.expectEqual(@as(u8, 4), @backingInt(commands.ApplicationCommandType.primary_entry_point));
}

test "choice requests enforce documented bounds" {
    try (commands.ApplicationCommandOptionStringChoice{
        .name = "choice",
        .value = "value",
    }).validate();
    try (commands.ApplicationCommandOptionNumberChoice{
        .name = "number",
        .value = 1.5,
    }).validate();

    try std.testing.expectError(
        error.InvalidName,
        (commands.ApplicationCommandOptionStringChoice{ .name = "", .value = "v" }).validate(),
    );
    const long_value: [6001]u8 = @splat('x');
    try std.testing.expectError(
        error.StringValueTooLong,
        (commands.ApplicationCommandOptionStringChoice{ .name = "n", .value = &long_value }).validate(),
    );

    var too_many = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"a":"1","b":"2","c":"3","d":"4","e":"5","f":"6","g":"7","h":"8","i":"9","j":"10","k":"11","l":"12","m":"13","n":"14","o":"15","p":"16","q":"17","r":"18","s":"19","t":"20","u":"21","v":"22","w":"23","x":"24","y":"25","z":"26","aa":"27","bb":"28","cc":"29","dd":"30","ee":"31","ff":"32","gg":"33","hh":"34","ii":"35"}
    , .{});
    defer too_many.deinit();
    try std.testing.expectError(
        error.TooManyLocalizations,
        (commands.ApplicationCommandOptionStringChoice{
            .name = "n",
            .value = "v",
            .name_localizations = too_many.value,
        }).validate(),
    );
}

test "choice responses parse value and optional localization" {
    var number = try std.json.parseFromSlice(commands.ApplicationCommandOptionNumberChoiceResponse, std.testing.allocator,
        \\{"name":"n","name_localized":"N","name_localizations":{"fr":"N"},"value":2.5}
    , .{ .ignore_unknown_fields = true });
    defer number.deinit();
    try std.testing.expectEqual(@as(f64, 2.5), number.value.value);
    try std.testing.expectEqualStrings("N", number.value.name_localized.?);

    var string = try std.json.parseFromSlice(commands.ApplicationCommandOptionStringChoiceResponse, std.testing.allocator,
        \\{"name":"s","value":"v"}
    , .{ .ignore_unknown_fields = true });
    defer string.deinit();
    try std.testing.expectEqualStrings("v", string.value.value);
    try std.testing.expect(string.value.name_localized == null);
}

test "unknown inbound command enum is retained" {
    var parsed = try std.json.parseFromSlice(commands.InboundApplicationCommandOptionType, std.testing.allocator, "99", .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(?commands.ApplicationCommandOptionType, null), parsed.value.known());
}

fn parseChoice(allocator: std.mem.Allocator, payload: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const value = try std.json.parseFromSliceLeaky(commands.ApplicationCommandOptionStringChoice, arena.allocator(), payload, .{
        .ignore_unknown_fields = true,
    });
    try value.validate();
}

test "allocation failure while parsing localizations is leak free" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        parseChoice,
        .{"{\"name\":\"choice\",\"name_localizations\":{\"fr\":\"choix\",\"de\":\"auswahl\"},\"value\":\"v\"}"},
    );
}

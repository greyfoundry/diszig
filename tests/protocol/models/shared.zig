const std = @import("std");
const diszig = @import("diszig");

test "public shared models decode and expose documented constants" {
    const bytes =
        \\{"max_concurrency":16,"remaining":1000,"reset_after":5000,"total":1000}
    ;
    var parsed = try std.json.parseFromSlice(
        diszig.protocol.models.shared.GatewayBotSessionStartLimitResponse,
        std.testing.allocator,
        bytes,
        .{},
    );
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u32, 16), parsed.value.max_concurrency);
    try std.testing.expectEqual(@as(u64, 5000), parsed.value.reset_after);
}

test "public shared enums and wire strings" {
    try std.testing.expectEqual(@as(i32, 900), @backingInt(diszig.protocol.models.shared.AfkTimeouts.fifteen_minutes));
    try std.testing.expectEqualStrings("bot", diszig.protocol.models.shared.AuthorType.bot.wireName());
}

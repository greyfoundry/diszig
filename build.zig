const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protocol = b.addModule("protocol", .{
        .root_source_file = b.path("packages/protocol/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const diszig = b.addModule("diszig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protocol", .module = protocol },
        },
    });

    const test_step = b.step("test", "Run unit tests");

    const protocol_tests = b.addTest(.{ .root_module = protocol });
    test_step.dependOn(&b.addRunArtifact(protocol_tests).step);

    const root_tests = b.addTest(.{ .root_module = diszig });
    test_step.dependOn(&b.addRunArtifact(root_tests).step);
}

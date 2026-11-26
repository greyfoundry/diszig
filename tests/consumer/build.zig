const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const diszig = b.dependency("diszig", .{ .target = target, .optimize = optimize });

    const exe = b.addExecutable(.{
        .name = "consumer",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig.module("diszig") },
            },
        }),
    });
    b.installArtifact(exe);

    const run_step = b.step("run", "Run the external consumer");
    run_step.dependOn(&b.addRunArtifact(exe).step);
}

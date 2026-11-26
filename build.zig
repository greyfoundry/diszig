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

    const package_check = b.addSystemCommand(&.{ "python", "tools/check_package.py" });
    const package_self_test = b.addSystemCommand(&.{ "python", "tools/check_package.py", "--self-test" });
    const repository_check = b.addSystemCommand(&.{ "python", "tools/check_repository.py" });
    const coverage_check = b.addSystemCommand(&.{ "python", "tools/check_coverage.py" });
    const coverage_self_test = b.addSystemCommand(&.{ "python", "tools/check_coverage.py", "--self-test" });

    const consumer_step = b.step("consumer", "Build and run the external archive consumer");
    const consumer = b.addSystemCommand(&.{ "python", "tests/consumer/fetch_test.py" });
    consumer_step.dependOn(&consumer.step);

    const check_step = b.step("check", "Run tests and repository/package gates");
    check_step.dependOn(test_step);
    check_step.dependOn(&package_check.step);
    check_step.dependOn(&package_self_test.step);
    check_step.dependOn(&repository_check.step);
    check_step.dependOn(&coverage_check.step);
    check_step.dependOn(&coverage_self_test.step);
    check_step.dependOn(&consumer.step);

    const docs_step = b.step("docs", "Validate the Mintlify handbook");
    const docs = b.addSystemCommand(&.{ "mint", "validate" });
    docs.setCwd(b.path("docs"));
    docs_step.dependOn(&docs.step);
}

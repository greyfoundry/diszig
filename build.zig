const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const protocol = b.addModule("protocol", .{
        .root_source_file = b.path("packages/protocol/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const rest = b.addModule("rest", .{
        .root_source_file = b.path("packages/rest/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protocol", .module = protocol },
        },
    });

    // Vendored client-only websocket.zig. See third_party/websocket/VENDOR.md.
    const websocket_options = b.addOptions();
    websocket_options.addOption(bool, "zlib", true);
    const websocket = b.addModule("websocket", .{
        .root_source_file = b.path("third_party/websocket/src/websocket.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    websocket.addOptions("build", websocket_options);

    const gateway = b.addModule("gateway", .{
        .root_source_file = b.path("packages/gateway/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "protocol", .module = protocol },
            .{ .name = "websocket", .module = websocket },
        },
    });

    const zlib = addZlib(b, target, optimize);
    websocket.linkLibrary(zlib.lib);
    websocket.addIncludePath(zlib.include);
    gateway.linkLibrary(zlib.lib);
    gateway.addIncludePath(zlib.include);
    if (target.result.os.tag == .windows) {
        websocket.linkSystemLibrary("ws2_32", .{});
        gateway.linkSystemLibrary("ws2_32", .{});
    }

    const diszig = b.addModule("diszig", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protocol", .module = protocol },
            .{ .name = "rest", .module = rest },
            .{ .name = "gateway", .module = gateway },
        },
    });

    const test_step = b.step("test", "Run unit tests");
    const protocol_tests = b.addTest(.{ .root_module = protocol });
    test_step.dependOn(&b.addRunArtifact(protocol_tests).step);
    const root_tests = b.addTest(.{ .root_module = diszig });
    test_step.dependOn(&b.addRunArtifact(root_tests).step);

    const public_protocol_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/permissions.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_protocol_tests).step);

    const public_json_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/json.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_json_tests).step);

    const public_rest_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/errors.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_rest_tests).step);

    const public_transport_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/transport.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_transport_tests).step);

    const public_routes_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/routes.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_routes_tests).step);

    const public_limiter_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/limiter.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_limiter_tests).step);

    const public_retry_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/retry.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_retry_tests).step);

    const public_upload_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/uploads.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_upload_tests).step);

    const public_pagination_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/pagination.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_pagination_tests).step);

    const public_shared_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/shared.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_shared_models_tests).step);

    const gateway_tests = b.addTest(.{ .root_module = gateway });
    test_step.dependOn(&b.addRunArtifact(gateway_tests).step);

    const public_framing_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/framing.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_framing_tests).step);

    const public_heartbeat_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/heartbeat.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_heartbeat_tests).step);

    const public_recovery_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/recovery.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_recovery_tests).step);

    const public_dispatch_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/dispatch.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_dispatch_tests).step);

    const public_send_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/send.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_send_tests).step);

    const public_channel_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/channels.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_channel_event_tests).step);

    const public_command_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/commands.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_command_event_tests).step);

    const public_guild_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/guilds.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_guild_event_tests).step);

    const public_integration_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/integrations.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_integration_event_tests).step);

    const public_interaction_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/interactions.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_interaction_event_tests).step);

    const public_invite_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/invites.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_invite_event_tests).step);

    const public_member_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/members.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_member_event_tests).step);

    const package_check = b.addSystemCommand(&.{ "python", "tools/check_package.py" });
    const package_self_test = b.addSystemCommand(&.{ "python", "tools/check_package.py", "--self-test" });
    const repository_check = b.addSystemCommand(&.{ "python", "tools/check_repository.py" });
    const coverage_check = b.addSystemCommand(&.{ "python", "tools/check_coverage.py" });
    const coverage_self_test = b.addSystemCommand(&.{ "python", "tools/check_coverage.py", "--self-test" });
    const drift_self_test = b.addSystemCommand(&.{ "python", "tools/check_api_drift.py", "--self-test" });
    const compiler_check = b.addSystemCommand(&.{ "python", "tools/check_compiler.py" });

    const consumer_step = b.step("consumer", "Build and run the external archive consumer");
    const consumer = b.addSystemCommand(&.{ "python", "tests/consumer/fetch_test.py" });
    consumer_step.dependOn(&consumer.step);

    const transport_step = b.step("transport", "Run the local REST transport fixture");
    const transport_check = b.addSystemCommand(&.{ "python", "tests/rest/transport_fixture.py" });
    transport_step.dependOn(&transport_check.step);

    const gateway_probe_step = b.step("gateway-probe", "Build the local Gateway transport probe");
    const gateway_probe = b.addExecutable(.{
        .name = "gateway_probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/transport_probe.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    gateway_probe_step.dependOn(&b.addInstallArtifact(gateway_probe, .{}).step);

    const gateway_fixture_step = b.step("gateway-fixture", "Run the local Gateway framing fixture");
    const gateway_fixture = b.addSystemCommand(&.{ "python", "tests/gateway/transport_fixture.py" });
    gateway_fixture_step.dependOn(&gateway_fixture.step);

    const session_probe_step = b.step("session-probe", "Build the local Gateway session probe");
    const session_probe = b.addExecutable(.{
        .name = "session_probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/session_probe.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    session_probe_step.dependOn(&b.addInstallArtifact(session_probe, .{}).step);

    const heartbeat_fixture_step = b.step("heartbeat-fixture", "Run the local Gateway heartbeat fixture");
    const heartbeat_fixture = b.addSystemCommand(&.{ "python", "tests/gateway/heartbeat_fixture.py" });
    heartbeat_fixture_step.dependOn(&heartbeat_fixture.step);

    const check_step = b.step("check", "Run tests and repository/package gates");
    check_step.dependOn(test_step);
    check_step.dependOn(&package_check.step);
    check_step.dependOn(&package_self_test.step);
    check_step.dependOn(&repository_check.step);
    check_step.dependOn(&coverage_check.step);
    check_step.dependOn(&coverage_self_test.step);
    check_step.dependOn(&drift_self_test.step);
    check_step.dependOn(&compiler_check.step);
    check_step.dependOn(&consumer.step);
    check_step.dependOn(&transport_check.step);
    check_step.dependOn(&gateway_fixture.step);
    check_step.dependOn(&heartbeat_fixture.step);

    const probe_step = b.step("transport-probe", "Build the local REST transport probe");
    const probe = b.addExecutable(.{
        .name = "transport_probe",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/transport_probe.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    probe_step.dependOn(&b.addInstallArtifact(probe, .{}).step);

    const cross_step = b.step("cross-check", "Compile protocol and REST tests without executing");
    const cross_protocol = b.addTest(.{ .root_module = protocol });
    const cross_rest = b.addTest(.{ .root_module = rest });
    cross_step.dependOn(&cross_protocol.step);
    cross_step.dependOn(&cross_rest.step);

    const docs_step = b.step("docs", "Validate the Mintlify handbook");
    const docs = b.addSystemCommand(&.{ "mint", "validate" });
    docs.setCwd(b.path("docs"));
    docs_step.dependOn(&docs.step);
}

/// Build the pinned zlib sources once and link them into the modules that need
/// it. `zlib-stream` needs an inflate context that survives WebSocket message
/// boundaries, which the Zig standard library cannot provide; the vendored
/// websocket client also uses zlib for its (disabled) deflate backend.
fn addZlib(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) struct {
    lib: *std.Build.Step.Compile,
    include: std.Build.LazyPath,
} {
    const zlib_dep = b.dependency("zlib", .{ .target = target, .optimize = optimize });
    const include = zlib_dep.path(".");
    const zlib_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    zlib_mod.addIncludePath(include);
    zlib_mod.addCSourceFiles(.{
        .root = include,
        .files = &.{
            "adler32.c",
            "crc32.c",
            "deflate.c",
            "inffast.c",
            "inflate.c",
            "inftrees.c",
            "trees.c",
            "zutil.c",
        },
        .flags = &.{},
    });
    return .{
        .lib = b.addLibrary(.{
            .name = "diszig-zlib",
            .root_module = zlib_mod,
        }),
        .include = include,
    };
}

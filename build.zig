const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const libdave_dir = b.option(
        []const u8,
        "libdave-dir",
        "Path to an extracted official libdave release (include/, lib/, bin/) for the optional voice-probe step",
    );
    const opus_dir = b.option(
        []const u8,
        "opus-dir",
        "Path to the extracted pinned Opus source (opus-1.5.2) for the optional voice-audio-probe step",
    );

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

    const builders = b.addModule("builders", .{
        .root_source_file = b.path("packages/builders/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protocol", .module = protocol },
        },
    });

    // Optional voice capability report. It intentionally has no dependencies;
    // see packages/voice/root.zig and .private/reports/decisions/voice.md.
    const voice = b.addModule("voice", .{
        .root_source_file = b.path("packages/voice/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "protocol", .module = protocol },
        },
    });

    // Optional libdave ABI probe. Nothing here runs unless -Dlibdave-dir is set;
    // default builds remain free of native voice dependencies.
    const voice_probe_step = b.step("voice-probe", "Build and run the optional libdave ABI probe");
    if (libdave_dir) |dir| {
        const dave_module = b.createModule(.{
            .root_source_file = b.path("packages/voice/dave.zig"),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        const include_dir = b.pathJoin(&.{ dir, "include" });
        const translate = b.addTranslateC(.{
            .root_source_file = lazyPath(b, b.pathJoin(&.{ include_dir, "dave", "dave.h" })),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        translate.addIncludePath(lazyPath(b, include_dir));
        const dave_c = translate.createModule();
        dave_module.addImport("dave_c", dave_c);

        dave_module.addLibraryPath(lazyPath(b, b.pathJoin(&.{ dir, "lib" })));
        if (target.result.os.tag == .windows) {
            dave_module.linkSystemLibrary("libdave", .{});
        } else {
            dave_module.linkSystemLibrary("dave", .{});
        }

        const probe = b.addExecutable(.{
            .name = "dave_probe",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/voice/dave_probe.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "voice_dave", .module = dave_module },
                },
            }),
        });
        const install_probe = b.addInstallArtifact(probe, .{});
        voice_probe_step.dependOn(&install_probe.step);

        const library_dir = b.pathJoin(&.{ dir, "bin" });
        const run = b.addRunArtifact(probe);
        switch (target.result.os.tag) {
            .windows => run.setEnvironmentVariable("PATH", library_dir),
            .macos => run.setEnvironmentVariable("DYLD_LIBRARY_PATH", library_dir),
            else => run.setEnvironmentVariable("LD_LIBRARY_PATH", library_dir),
        }
        voice_probe_step.dependOn(&run.step);
    } else {
        const fail = b.addSystemCommand(&.{
            "python",
            "-c",
            "import sys; print('voice-probe requires -Dlibdave-dir=<extracted official libdave release>'); sys.exit(2)",
        });
        voice_probe_step.dependOn(&fail.step);
    }

    // Optional Opus audio probe. Nothing links a codec without -Dopus-dir.
    const voice_audio_step = b.step("voice-audio-probe", "Build and run the optional Opus encode/decode probe");
    if (opus_dir) |dir| {
        const opus_c_module = opusCMacroModule(b, target, optimize, dir);
        const translate_opus = b.addTranslateC(.{
            .root_source_file = lazyPath(b, b.pathJoin(&.{ dir, "include", "opus.h" })),
            .target = target,
            .optimize = optimize,
            .link_libc = true,
        });
        translate_opus.addIncludePath(lazyPath(b, b.pathJoin(&.{ dir, "include" })));
        const opus_c = translate_opus.createModule();

        const opus_lib = b.addLibrary(.{
            .name = "diszig-opus",
            .root_module = opus_c_module,
        });

        const voice_opus = b.createModule(.{
            .root_source_file = b.path("packages/voice/opus.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "voice", .module = voice },
                .{ .name = "opus_c", .module = opus_c },
            },
        });
        voice_opus.linkLibrary(opus_lib);

        const probe = b.addExecutable(.{
            .name = "opus_probe",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/voice/opus_probe.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "voice_opus", .module = voice_opus },
                },
            }),
        });
        const run = b.addRunArtifact(probe);
        voice_audio_step.dependOn(&run.step);
    } else {
        const fail = b.addSystemCommand(&.{
            "python",
            "-c",
            "import sys; print('voice-audio-probe requires -Dopus-dir=<extracted pinned Opus source>'); sys.exit(2)",
        });
        voice_audio_step.dependOn(&fail.step);
    }

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
            .{ .name = "builders", .module = builders },
            .{ .name = "voice", .module = voice },
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

    const public_oauth2_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/rest/oauth2.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_oauth2_tests).step);

    const public_voice_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/voice/root.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_voice_tests).step);

    const public_voice_gateway_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/voice/gateway.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_voice_gateway_tests).step);

    const public_voice_transport_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/voice/transport.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_voice_transport_tests).step);

    const public_voice_transition_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/voice/transitions.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_voice_transition_tests).step);

    const public_voice_recovery_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/voice/recovery.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_voice_recovery_tests).step);

    const public_voice_session_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/voice/session.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_voice_session_tests).step);

    const public_voice_media_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/voice/media.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_voice_media_tests).step);

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

    const public_users_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/users.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_users_models_tests).step);

    const public_guilds_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/guilds.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_guilds_models_tests).step);

    const public_applications_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/applications.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_applications_models_tests).step);

    const public_channels_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/channels.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_channels_models_tests).step);

    const public_commands_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/commands.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_commands_models_tests).step);

    const public_components_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/components.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_components_models_tests).step);

    const public_interactions_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/interactions.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_interactions_models_tests).step);

    const public_messages_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/messages.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_messages_models_tests).step);

    const public_monetization_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/monetization.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_monetization_models_tests).step);

    const public_resources_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/resources.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_resources_models_tests).step);

    const public_voice_control_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/voice_control.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_voice_control_models_tests).step);

    const public_social_models_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/protocol/models/social.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_social_models_tests).step);

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

    const public_message_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/messages.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_message_event_tests).step);

    const public_role_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/roles.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_role_event_tests).step);

    const public_thread_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/threads.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_thread_event_tests).step);

    const public_reaction_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/reactions.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_reaction_event_tests).step);

    const public_poll_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/polls.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_poll_event_tests).step);

    const public_user_event_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/gateway/events/users.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_user_event_tests).step);

    const public_builder_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/builders/message.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    test_step.dependOn(&b.addRunArtifact(public_builder_tests).step);

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

    const examples_step = b.step("examples", "Compile public examples");
    const oauth2_example = b.addExecutable(.{
        .name = "oauth2_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/oauth2.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    examples_step.dependOn(&b.addInstallArtifact(oauth2_example, .{}).step);
    check_step.dependOn(&oauth2_example.step);

    const voice_example = b.addExecutable(.{
        .name = "voice_example",
        .root_module = b.createModule(.{
            .root_source_file = b.path("examples/voice.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "diszig", .module = diszig },
            },
        }),
    });
    examples_step.dependOn(&b.addInstallArtifact(voice_example, .{}).step);
    check_step.dependOn(&voice_example.step);

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

fn lazyPath(b: *std.Build, text: []const u8) std.Build.LazyPath {
    return if (std.fs.path.isAbsolute(text)) .{ .cwd_relative = text } else b.path(text);
}

fn opusCMacroModule(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    dir: []const u8,
) *std.Build.Module {
    const module = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    module.addIncludePath(lazyPath(b, b.pathJoin(&.{ dir, "include" })));
    module.addIncludePath(lazyPath(b, dir));
    module.addIncludePath(lazyPath(b, b.pathJoin(&.{ dir, "celt" })));
    module.addIncludePath(lazyPath(b, b.pathJoin(&.{ dir, "silk" })));
    module.addIncludePath(lazyPath(b, b.pathJoin(&.{ dir, "silk", "float" })));
    module.addCMacro("OPUS_BUILD", "1");
    module.addCMacro("VAR_ARRAYS", "1");
    module.addCMacro("DISABLE_DEBUG_FLOAT", "1");

    var files: std.ArrayList([]const u8) = .empty;
    const io = b.graph.io;
    const subtrees = [_][]const u8{ "src", "celt", "silk", "silk/float" };
    for (subtrees) |sub| {
        var directory = std.Io.Dir.cwd().openDir(io, b.pathJoin(&.{ dir, sub }), .{ .iterate = true }) catch {
            @panic("opus-dir does not contain the expected source tree; run tools/fetch_opus.py");
        };
        defer directory.close(io);
        var iterator = directory.iterate();
        while (iterator.next(io) catch @panic("failed to read opus sources")) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".c")) continue;
            if (isExcludedOpusSource(entry.name)) continue;
            files.append(b.allocator, b.pathJoin(&.{ sub, entry.name })) catch @panic("out of memory collecting opus sources");
        }
    }
    module.addCSourceFiles(.{
        .root = lazyPath(b, dir),
        .files = files.items,
        .flags = &.{"-std=c99"},
    });
    return module;
}

fn isExcludedOpusSource(name: []const u8) bool {
    return std.mem.eql(u8, name, "opus_demo.c") or
        std.mem.eql(u8, name, "repacketizer_demo.c") or
        std.mem.eql(u8, name, "opus_compare.c");
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

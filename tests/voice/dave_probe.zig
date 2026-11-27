//! libdave C ABI probe. Run with:
//!   python tools/fetch_libdave.py
//!   zig build voice-probe -Dlibdave-dir=third_party/libdave/v1.3.0/windows
//!
//! It creates a DAVE session, initializes an MLS group, requests a key package
//! and destroys the session. It does not connect to Discord or send audio.

const std = @import("std");
const dave = @import("voice_dave");

pub fn main() !void {
    const version = try dave.abiVersion();
    var session = try dave.Session.create("diszig-voice-probe");
    defer session.destroy();

    session.initGroup(version, 1, "1");
    if (session.protocolVersion() != version) return error.ProtocolVersionMismatch;

    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const key_package = try session.keyPackage(arena.allocator());
    if (key_package.len == 0) return error.EmptyKeyPackage;

    std.debug.print(
        "libdave ABI ok: protocol={d} key_package_bytes={d}\n",
        .{ version, key_package.len },
    );
}

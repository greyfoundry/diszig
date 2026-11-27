//! libdave C ABI probe. Run with:
//!   python tools/fetch_libdave.py
//!   zig build voice-probe -Dlibdave-dir=third_party/libdave/v1.3.0/windows-x64
//!
//! It creates a DAVE session, initializes an MLS group, requests a key package,
//! then exercises the encryptor/decryptor in passthrough mode and destroys
//! everything. It does not connect to Discord, join a call or send audio.

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

    // The public release does not expose the test-only external-sender helper,
    // so a real MLS commit/welcome round-trip needs voice-server payloads. The
    // media frames can still be exercised in passthrough mode.
    var encryptor = try dave.Encryptor.create();
    defer encryptor.destroy();
    encryptor.setPassthrough(true);
    encryptor.assignOpusSsrc(1);
    if (!encryptor.isPassthrough() or encryptor.hasKeyRatchet()) return error.PassthroughStateMismatch;

    var decryptor = try dave.Decryptor.create();
    defer decryptor.destroy();
    decryptor.setPassthrough(true);

    const frame = "dave-probe-frame";
    var ciphertext: [128]u8 = undefined;
    const encrypted = try encryptor.encrypt(&ciphertext, 1, frame);
    var plaintext: [128]u8 = undefined;
    const decrypted = try decryptor.decrypt(&plaintext, encrypted);
    if (!std.mem.eql(u8, frame, decrypted)) return error.PassthroughMismatch;

    std.debug.print(
        "libdave ABI ok: protocol={d} key_package_bytes={d} passthrough_bytes={d}\n",
        .{ version, key_package.len, decrypted.len },
    );
}

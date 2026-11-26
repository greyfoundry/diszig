const std = @import("std");
const Certificate = std.crypto.Certificate;

pub fn distrust(bundle: *Certificate.Bundle) void {
    var iterator = bundle.map.iterator();
    while (iterator.next()) |entry| {
        const cert: Certificate = .{ .buffer = bundle.bytes.items, .index = entry.value_ptr.* };
        const parsed = cert.parse() catch unreachable;
        const start = parsed.subject_slice.end;
        const spki = Certificate.der.Element.parse(cert.buffer, start) catch unreachable;
        var digest: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(cert.buffer[start..spki.slice.end], &digest, .{});
        for (blocked_keys) |blocked| {
            if (std.mem.eql(u8, &digest, &blocked)) {
                bundle.map.removeByPtr(entry.key_ptr);
                break;
            }
        }
    }
}

const blocked_keys = [_][32]u8{
    hex("C619E4780ED8E0ABEDA24AD732567DE4383A7EA941338F6D1A7D1B49AC792FE9"),
    hex("0A6C2B2CA5B364207954171987AC9D2178561569D8205457E77CA90C32EDE282"),
    hex("BD153ED7B0434F6886B17BCE8BBE84ED340C7132D702A8F4FA318F756ECBD6F3"),
    hex("8D417DB2DD8BF5E3084D1E3F196D583849D81BDD4C00C70B9D39369E96B8C782"),
    hex("EBED6475C2C2D80FCB199F3FE8DD6E6B3CE60B77EB15D4E42C3DEC0C6F5B5105"),
    hex("43BFFA19D6EF651451F6841E019931E96F6F2EAEFF28AB4B6F1CE4576DE2717B"),
    hex("E0254C7FCDC265E2F0F8A428DABB75AB4AE039B4872D62F5EE57F0877D5A8A41"),
    hex("49DD353DC2B919A3770645117D0E60C16115E7D1BC259EEFE734B00EA434FE5F"),
    hex("63ECEFEE431D49523BC1136C4E72D0206A477086CAF606CD5CF025686C109CF8"),
    hex("5C0660A2B164910D8FF589C18E14552E9E0EC237DCEFE2CB736D41A4811F81A0"),
    hex("EC4FFA1AD0AC88081314B7AAFFEF6A91F97CD57291BB5BA686C5415F5EB4F6B6"),
    hex("92C063D67E8F14DB71D288E11266FFDAF69CBF115F7BAB14F3BC2F68D25E0E30"),
};

// Vendored: the upstream test-only import of `trust_test.zig` and its DER
// fixtures is omitted. See `third_party/websocket/VENDOR.md`.

fn hex(comptime value: []const u8) [32]u8 {
    @setEvalBranchQuota(10000);
    var bytes: [32]u8 = undefined;
    _ = std.fmt.hexToBytes(&bytes, value) catch unreachable;
    return bytes;
}

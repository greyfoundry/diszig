//! permessage-deflate codec.
//!
//! Vendored modification: Diszig always links C zlib and never vendors
//! pmdeflate, so only the zlib backend is imported. See
//! `third_party/websocket/VENDOR.md`.

pub const uses_zlib = true;
const impl = @import("deflate_zlib.zig");

pub const Error = impl.Error;
pub const Compressor = impl.Compressor;
pub const Decompressor = impl.Decompressor;

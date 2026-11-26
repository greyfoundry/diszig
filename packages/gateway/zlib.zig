//! Hand-written ABI declarations for the slice of zlib used by the Gateway
//! transport.
//!
//! Zig 0.17 does not provide `@cImport`, and `std.compress.flate.Decompress`
//! cannot be paused between input chunks: it treats input exhaustion as a
//! terminal error, while Discord's `zlib-stream` keeps one inflate context for
//! the whole connection. These declarations bind directly to zlib's documented
//! C interface instead of reimplementing a codec.
//!
//! Layout note: `z_stream` must match the vendored zlib exactly. zlib's
//! `inflateInit2_` rejects a mismatched version or `sizeof(z_stream)` at
//! initialisation, so a wrong layout fails loudly rather than corrupting
//! memory. `uLong` is `unsigned long`, which is 32-bit on Windows and 64-bit
//! on LP64 Unix; `c_ulong` tracks that in Zig.

pub const uInt = c_uint;
pub const uLong = c_ulong;

pub const ZLIB_VERSION = "1.3.2";
pub const MAX_WBITS = 15;

pub const Z_SYNC_FLUSH = 2;
pub const Z_OK = 0;
pub const Z_STREAM_END = 1;
pub const Z_BUF_ERROR = -5;

pub const z_stream = extern struct {
    next_in: ?[*]u8,
    avail_in: uInt,
    total_in: uLong,
    next_out: ?[*]u8,
    avail_out: uInt,
    total_out: uLong,
    msg: ?[*:0]const u8,
    state: ?*anyopaque,
    zalloc: ?*const fn (?*anyopaque, uInt, uInt) callconv(.c) ?*anyopaque,
    zfree: ?*const fn (?*anyopaque, ?*anyopaque) callconv(.c) void,
    @"opaque": ?*anyopaque,
    data_type: c_int,
    adler: uLong,
    reserved: uLong,
};

extern fn inflateInit2_(strm: *z_stream, window_bits: c_int, version: [*:0]const u8, stream_size: c_int) c_int;

pub extern fn inflate(strm: *z_stream, flush: c_int) c_int;
pub extern fn inflateEnd(strm: *z_stream) c_int;
pub extern fn inflateReset(strm: *z_stream) c_int;

pub fn inflateInit2(strm: *z_stream, window_bits: c_int) c_int {
    return inflateInit2_(strm, window_bits, ZLIB_VERSION, @sizeOf(z_stream));
}

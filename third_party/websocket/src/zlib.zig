// Hand-written bindings for the slice of zlib.h that deflate.zig uses.
// Zig 0.17 removed @cImport; this keeps the build free of a translate-c step.
// Must track the vendored zlib in build.zig.zon: deflateInit2_/inflateInit2_
// reject a mismatched major version or z_stream size at init.

pub const uInt = c_uint;
pub const uLong = c_ulong;

pub const ZLIB_VERSION = "1.3.2";
pub const MAX_WBITS = 15;

pub const Z_NO_FLUSH = 0;
pub const Z_SYNC_FLUSH = 2;
pub const Z_OK = 0;
pub const Z_BUF_ERROR = -5;
pub const Z_DEFAULT_COMPRESSION = -1;
pub const Z_DEFAULT_STRATEGY = 0;
pub const Z_DEFLATED = 8;

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

extern fn deflateInit2_(strm: *z_stream, level: c_int, method: c_int, window_bits: c_int, mem_level: c_int, strategy: c_int, version: [*:0]const u8, stream_size: c_int) c_int;
extern fn inflateInit2_(strm: *z_stream, window_bits: c_int, version: [*:0]const u8, stream_size: c_int) c_int;
pub extern fn deflate(strm: *z_stream, flush: c_int) c_int;
pub extern fn deflateEnd(strm: *z_stream) c_int;
pub extern fn deflateReset(strm: *z_stream) c_int;
pub extern fn inflate(strm: *z_stream, flush: c_int) c_int;
pub extern fn inflateEnd(strm: *z_stream) c_int;
pub extern fn inflateReset(strm: *z_stream) c_int;

pub fn deflateInit2(strm: *z_stream, level: c_int, method: c_int, window_bits: c_int, mem_level: c_int, strategy: c_int) c_int {
    return deflateInit2_(strm, level, method, window_bits, mem_level, strategy, ZLIB_VERSION, @sizeOf(z_stream));
}

pub fn inflateInit2(strm: *z_stream, window_bits: c_int) c_int {
    return inflateInit2_(strm, window_bits, ZLIB_VERSION, @sizeOf(z_stream));
}

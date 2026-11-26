# Vendored websocket.zig (client)

Upstream: https://tangled.org/zzstoatzz.io/websocket.zig
Upstream project: a Zig 0.17 fork of https://github.com/karlseguin/websocket.zig
Revision: tag `v0.3.1`, commit `34e98f7ee276f94837e6b14e2e291f9db87ba016`
Licence: MIT (`LICENSE` in this directory)
Selected: 2026-11-26, after the evaluation recorded in
`.private/reports/decisions/websocket.md`.

## Why this is vendored

The upstream `build.zig.zon` declares a lazy `zlib` dependency pinned to a
GitHub **auto-generated** archive (`archive/refs/tags/v1.3.2.tar.gz`). GitHub
regenerated that archive, so the declared package hash no longer matches what
is served. Zig verifies the full dependency graph, so any project that adds
`websocket` as a dependency now fails during `zig build` with a hash mismatch
for a dependency it never uses. Pinning a broken third-party manifest is not
reproducible for consumers or CI, so the reviewed source is vendored here and
the unused dependency entry is simply absent.

## What is copied

Only the client path plus what it imports:

```text
src/websocket.zig          replacement root (client-only, written for Diszig)
src/proto.zig
src/buffer.zig
src/net_io.zig
src/shutdown.zig
src/trust.zig
src/t.zig                   test helper used by copied tests
src/deflate.zig
src/deflate_zlib.zig
src/zlib.zig                hand-written C bindings (deflate side)
src/client/client.zig
src/server/handshake.zig    only for the client handshake's extension parser
```

The server, thread pool, fallback allocator, examples, benchmarks, test runner
and the 52 DER trust fixtures are not copied.

## Local modifications

1. `src/websocket.zig` is a Diszig-written client-only root. Upstream's root
   also exported the server and called `std.testing.refAllDecls`, which forces
   the whole server into every consumer.
2. `src/trust.zig` drops the test-only `@import("trust_test.zig")`, because the
   DER fixtures are not vendored. The `distrust` function is unchanged.
3. The module always builds with `build.zlib = true`. `deflate.zig` therefore
   imports only `deflate_zlib.zig` and links the same zlib as the Gateway
   transport. This removes the pmdeflate dependency and its import entirely;
   Diszig never negotiates `permessage-deflate` (the upstream client disables
   it too).

Nothing else in the copied files is edited. Client framing, masking,
fragmentation, TLS and error mapping are upstream code.

A mechanical replacement of Unicode em dashes with plain hyphens was applied to
comments in `client.zig` and `server/handshake.zig` to satisfy the repository's
staged-content check. No code, string literal or behaviour changed.

## Updating

Re-apply the copy from the pinned commit, re-check the three modifications
above, and run `zig build check`. A new revision must be recorded here and in
`THIRD_PARTY_NOTICES.md`, and the decision record updated. Do not add upstream
dependencies to `build.zig.zon` without verifying their pins are reproducible.

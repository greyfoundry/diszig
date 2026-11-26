# Compatibility policy

The research baseline is Zig 0.17.1, listed as stable on the [official download page](https://ziglang.org/download/) when checked on 2026-11-26. The initial supported compiler and range will be set after compiler-tested feasibility. No verified SDK platform support is claimed yet.

## Verified compiler facts

The official x86-64 Windows archive for 0.17.1 was checked against the SHA-256 in the download index and its minisign signature was verified. A focused probe using the installed standard library passes in Debug and ReleaseSafe on Windows 11 x86-64. The root package and its protocol module also build and pass `zig build test` in both modes on that host, and an external package consumer imports the root module.

This establishes compiler usability for the first implementation slice. It does not establish a supported compiler range, Linux or macOS runtime support, ARM64 support, CI coverage or live Discord behaviour.

Target operating systems are Linux, Windows and macOS; target architectures x86-64 and ARM64 where available. Distinguish compilation from native runtime tests. Required CI covers the declared current stable compiler; previous stable support is added only when tested and maintainable. Development compiler checks are advisory until explicitly supported. Zig's API is evolving; isolate actual version-sensitive boundaries and migrate deliberately towards Zig 1.0. No promise about unreleased compiler versions.

Initial Discord target: documented v10 REST and Gateway; additional versions only when explicitly supported. Track operation/event coverage, raw vs typed functionality, gated/experimental features, deprecations and optional voice separately. Discord OpenAPI preview is an inventory aid, not a production contract. Official docs and verified protocol behaviour govern.

Diszig uses independent semantic versioning. Pre-1.0 APIs may change; record breaking changes and migration instructions. A stable Diszig API is declared only after its own release gates are met. Dependencies, optional features and platform limits must be published by release.

---
name: zig-compatibility
description: Change compiler support, stdlib calls, build graphs or Zig package metadata.
---

# zig-compatibility

Read root AGENTS.md first; its invariants apply.

Record `zig version` and official stable source; inspect actual stdlib APIs and compiler release notes. Compile focused probes for changed I/O, allocator, networking or build features. Use a pinned stable toolchain; previous stable only if tested, master advisory. Isolate real unstable edges, avoid compatibility macros for hypothetical Zig 1.0. Verify root package manifest allowlist and external consumer fetch/import. Report native tests versus cross-builds, and update COMPATIBILITY.md only with evidence.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

---
name: test-and-fault-injection
description: Design or run meaningful tests, regression checks, mocks and fuzzing.
---

# test-and-fault-injection

Read root AGENTS.md first; its invariants apply.

Identify behavioral contract and failure modes; add a test that fails before the fix. Use deterministic time and local mock servers where appropriate; test negative paths, allocation and cancellation. Use native subprocess tests for hybrid. Test actual Zig compiler/build modes and compile examples. Keep offline default; live tests opt-in with authorization. Do not modify tests to hide failures. Report command, environment, result, skipped check and reason. Fuzz untrusted parsers with actual supported toolchain; no fake coverage claims.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

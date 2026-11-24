---
name: memory-concurrency-review
description: Review ownership, allocator behavior, error paths, caching and concurrency.
---

# memory-concurrency-review

Read root AGENTS.md first; its invariants apply.

Trace lifetime from allocation to cleanup, including errdefer, partial init, borrowed event buffer, callbacks, cache eviction and retained values. Document ownership and thread-safety contracts. Look for dangling slices, races, reentrancy, deadlocks, lock-held network calls, runaway queues and cancellation leaks. Test allocation failure, concurrent shutdown and cache miss/invalidation. Prefer standard primitives and bounded resources; no speculative generic abstractions. Report concrete code paths and failure evidence.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

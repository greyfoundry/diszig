---
name: native-hybrid-sharding
description: Implement or review native sharding, hybrid process supervision and IPC.
---

# native-hybrid-sharding

Read root AGENTS.md first; its invariants apply.

Read local SHARDING.md when available, or public sharding design. Native and hybrid share Gateway code. Validate exact assignment, guild formula, identify bucket and session budgets across workers, one managed owner, generation and termination. Prototype local subprocess and IPC on pinned Zig; bounded typed frames, no eval, credentials outside argv, parent EOF and crash/drain behavior. Coordinate REST limits across workers; fail closed if coordinator lost. Test multi-worker allocation, simultaneous identify, restart budget, stale replies, crash/timeout, no duplicate owner, cross-worker global 429 and cancellation. Distinguish local first release from multi-host integration.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

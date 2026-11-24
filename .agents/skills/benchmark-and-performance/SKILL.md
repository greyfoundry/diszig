---
name: benchmark-and-performance
description: Measure resource use, latency, throughput or compare competing Discord SDKs.
---

# benchmark-and-performance

Read root AGENTS.md first; its invariants apply.

Define representative workload and equivalent cache/shard/compression/feature settings. Record hardware, compiler/runtime/dependencies, mode, warmup, repetition, distributions and error bars where meaningful. Measure startup, RSS, allocation counts, dispatch/REST overhead, recovery, hybrid IPC, build/size and soak leaks as relevant. Use mock workloads instead of flooding Discord. Change only measured hot paths; rerun correctness tests. No cherry-picking or fastest claims without evidence.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

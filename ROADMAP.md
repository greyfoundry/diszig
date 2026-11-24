# Roadmap

This is a direction, not a release schedule. No feature below is currently verified as shipped.

1. Confirm compiler, transport and package feasibility; establish root build and first protocol tests.
2. Implement typed protocol primitives and a standalone REST client, including rate limiting and safe errors.
3. Implement Gateway sessions, recovery and event dispatch.
4. Deliver native sharding and local hybrid clustering with shared budgets, bounded IPC and recovery.
5. Deliver the first functional client with commands, interactions, legacy message components and Components V2. The first functional release must include both sharding modes; earlier standalone packages may be labelled previews.
6. Expand typed and raw coverage against the current documented Discord API, with coverage evidence, builders and managers.
7. Harden caches, compatibility, resource bounds, native platform tests, benchmarks and security/release processes.
8. Add optional modern voice with DAVE and Opus; evaluate multi-host coordination once local sharding is reliable.
9. Continue compiler upgrades, protocol drift review and the migration towards Zig 1.0. Diszig stability is a separate decision.

See the handbook for scope and the compatibility policy for verified support. Experimental or gated APIs are marked separately; private endpoints and self-bots are out of scope.

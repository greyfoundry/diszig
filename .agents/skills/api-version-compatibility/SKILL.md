---
name: api-version-compatibility
description: Add or change Discord REST, Gateway, Voice or protocol version support and compatibility claims.
---

# api-version-compatibility

Read the root AGENTS.md first. Its invariants apply.

1. Inspect the pinned official version table, changelog and relevant prose before choosing a version. Record the exact source and date. Do not infer availability from another SDK.
2. Audit existing version assumptions: base URLs, route prefixes, Gateway query/version, voice handshake, DAVE, IPC and package/service versions. Treat each as independent.
3. Reuse the shared implementation. Add version-specific behavior only at the serialization, validation, routing or handshake boundary where behaviour genuinely differs. Do not duplicate the SDK or add a speculative plugin framework.
4. Make selection explicit and validated before transmission. Defaults must target the verified stable version. Unsupported versions return actionable errors; never fall back, downgrade or retry against another version.
5. Add deterministic tests for the default, each supported opt-in version, unsupported versions and version-specific fields. Use shared fixtures with version-specific expectations where possible.
6. Update the public compatibility matrix, migration guidance, capability status and evidence records. Distinguish implemented, tested, documented and live-verified. A selectable version is not a coverage claim.
7. Run the compiler, test, package, drift, docs and cross-target checks. Do not publish, merge, release or expand support without current authorization.

Return concrete changes, versions covered, evidence, remaining gaps and decisions needing maintainer review.

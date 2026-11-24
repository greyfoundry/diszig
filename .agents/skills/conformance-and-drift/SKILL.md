---
name: conformance-and-drift
description: Audit API coverage or compare official schema revisions and fixtures.
---

# conformance-and-drift

Read root AGENTS.md first; its invariants apply.

Lock upstream commit and input hashes; distinguish standard and experimental spec. Generate deterministic operation inventory; compare baseline, review semantic changes and docs manually. Track each method/path/event/opcode/type/builder with auth, gating, symbols, tests, docs and live evidence. Do not count raw escape path as typed parity. Test missing/null/value, unknown flags/enums and schema override behavior. If generation is introduced, pin inputs, document overrides, regenerate/diff and forbid external ref fetching. Never auto-release on drift.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

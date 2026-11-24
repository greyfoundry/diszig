---
name: plan-and-bootstrap
description: Plan a scoped implementation or initialize the native Zig monorepo.
---

# plan-and-bootstrap

Read root AGENTS.md first; its invariants apply.

Read AGENTS.md and existing tree, including local plans if present. Identify prerequisites and inspect current compiler. Write independently executable plans with scope, dependency order, acceptance criteria, risk and rollback. Start with one real module and a root consumer package; prove external import before adding packages. Run small transport/IPC/build probes rather than designing hypothetical shims. Do not add empty directories, remote workflows or unverified install commands. Record actual results and blocked work.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

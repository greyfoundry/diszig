---
name: release-and-package
description: Prepare a release candidate, package archive or compiler compatibility update.
---

# release-and-package

Read root AGENTS.md first; its invariants apply.

Read compatibility and release criteria. Confirm clean source revision, exact Zig version, changelog, supported targets and feature claims. Inspect actual source archive and package paths (including nested modules); reject .private, references, secrets, caches and unexpected files. Test fetch/import/build in fresh consumer with verified hash. Run relevant tests/examples, inspect notices and dependency inventory/SBOM, checksums and provenance where supported. Prepare release evidence and rollback; never publish/push/tag remotely without approval. Do not claim supported signing or scanning without proof.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

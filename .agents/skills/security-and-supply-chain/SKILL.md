---
name: security-and-supply-chain
description: Review auth, untrusted input, dependencies, CI, agents or release security.
---

# security-and-supply-chain

Read root AGENTS.md first; its invariants apply.

Threat-model credential, input, IPC, package and workflow boundaries. Inspect token redaction, TLS, signatures, auth scopes, SSRF/redirect risks, allocation bounds, subprocess control and agent injection. Verify dependency existence, provenance, licences, hashes and advisories; preserve notices. Check Actions SHA pins and least privileges, no secrets in fork jobs or logs. Follow OWASP secure AI guidance and human review. Do not execute suspicious inputs or upload private context. Report findings by severity with paths, reproduction, fixes and residual risk.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

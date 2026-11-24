# Contributing to Diszig

Thanks for taking a look. We're building a native Zig SDK that people can depend on, and useful bug reports, tests, documentation and small improvements are as welcome as new features.

## Before starting

Check existing issues and the roadmap. For changes to public APIs, transports, sharding, ownership, dependencies or architecture, discuss the approach with maintainers before starting a substantial implementation. For small fixes, a focused PR is fine. Please don't open a large generated PR just to demonstrate activity.

Use the compiler listed in COMPATIBILITY.md. Follow the repository's actual build instructions once available; this initial seed has no verified SDK build. Use `zig fmt`, root build/test steps and relevant examples after they are implemented. Check the exact compiler version and installed stdlib, rather than relying on a snippet written for another version.

## Making a change

Keep the diff focused. Read the relevant code and tests. Prefer the existing implementation and native tooling before adding packages or dependencies. Public API naming should be idiomatic Zig; document allocator ownership, errors, lifetimes, cancellation and synchronization. For Discord protocol changes, link the applicable official docs, add fixtures and negative cases, update coverage and document permission/intents requirements. Handle unknown inbound fields and validate outbound requests. For bugs, add a regression test that would have failed before the fix.

Run the relevant tests and compiled examples; state exactly which commands ran and which did not. Don't disable assertions, skip security checks or widen CI exclusions to obtain a green result. Don't submit untested generated code as finished. Live tests need a dedicated test bot/guild and permission; do not put tokens in PRs or CI from forks. Native vs cross-compiled test results are separate.

## Pull requests and review

The default branch is `master`. Contributors use pull requests with at least one approving review; new commits dismiss stale approvals, and review conversations must be resolved. Repository administrators can bypass these requirements for urgent direct pushes, including security fixes. That exception does not replace responsibility for verification and follow-up human review. CI status checks will become required only after real workflows are implemented and verified.

Explain the problem, approach, compatibility, evidence and remaining risks in your own words. Keep unrelated refactors separate. Reviewers consider correctness, design, complexity, tests, names, docs, security, maintainability and code health. Address review comments directly; avoid unattended AI-generated discussions. A maintainer may request smaller scope or more evidence. Human approval is required before merge; high-risk changes (auth, crypto, ownership, concurrency, networking, sharding, release/security) need additional qualified review. If only one maintainer is available, record actual human review; do not fabricate an independent approval. Never bypass branch protections to ship.

## AI-assisted work

We welcome it. You remain responsible for the complete diff: read it, understand it, check provenance, and run tests yourself before opening a PR or clearly mark it as draft/unverified. Disclose material AI use in the PR template, including tool/model where known, scope and verification. AI review is supplementary, not human approval. See AI_POLICY.md and AI_DISCLOSURE.md. This applies to maintainers too.

## Licensing

Contributions are under Apache-2.0 unless a separately identified compatible third-party licence applies. Only submit material you have rights to contribute; preserve copyright and licence notices. Check all generated and reused code. DCO sign-off enforcement is not configured in this seed; do not claim it is. If adopted, human contributors must knowingly sign their own work. Do not commit private research or reference clones.

## Security and conduct

Use SECURITY.md for vulnerabilities rather than a public issue. Follow CODE_OF_CONDUCT.md in project discussions. Don't post tokens, private Discord data or unredacted logs. Maintainers can close unreviewed, insecure, duplicated or unsupported submissions regardless of whether AI was used.

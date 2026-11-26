# Diszig

[![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
![Language: Zig](https://img.shields.io/badge/Zig-native-F7A41D?logo=zig&logoColor=white)

**Discord, the Zig way.**

Diszig is a native Discord SDK for Zig. We're building the kind of library Zig developers should be able to reach for when they want to write a Discord bot: a client that handles the connection, typed events, builders for the things you send to Discord, and direct access to the API when you need it.

> Early implementation. A Zig build and protocol module exist (Snowflake, error context, tolerant JSON helpers). REST, Gateway, client, builders, sharding and voice are not implemented. There is no installable release or supported public client API yet. The features below describe the direction of the project.

## Why Diszig?

Discord has a well-established library ecosystem in JavaScript, Rust and Go. Zig has had several interesting implementations too, but we want to build one that stays maintained as both Discord and Zig change.

The public interface takes inspiration from discord.js. Underneath, it's Zig: explicit allocation and ownership, errors that callers can handle, and a build that doesn't need another language runtime.

## What we're building

- REST and Gateway support, with typed requests and events and direct access to documented APIs.
- Application commands, interactions, embeds, legacy message components and Components V2.
- Native sharding for a single process and hybrid sharding for bots that need several workers, without requiring Redis.
- Configurable caching, predictable resource lifetimes and documented recovery behaviour.
- Optional voice support, including modern Discord voice encryption.
- A compatibility and coverage matrix that tells you what actually works.

See [ROADMAP.md](ROADMAP.md) and [COMPATIBILITY.md](COMPATIBILITY.md) for scope and status. The [handbook](docs/index.mdx) covers the project design and current limitations. [Protocol references](docs/references.mdx) records the pinned official Discord documentation baseline.

## Development

The SDK uses Zig's native build and package system. The current package targets Zig 0.17.1 and exposes a `diszig` module plus a lower-level `protocol` module. Run:

```bash
zig build test
```

Tests pass in Debug and ReleaseSafe on Windows x86-64. Linux, macOS and ARM64 remain unverified targets. The package allowlist is checked with `python tools/check_package.py`, and `python tests/consumer/fetch_test.py` builds a fresh consumer from a hashed source archive. Examples and CI will be compiled rather than maintained as disconnected snippets.

The current repository contains:

```text
build.zig, build.zig.zon  Root package and module graph
src/root.zig              Public entrypoint
packages/protocol/        Snowflake, error context and JSON helpers
.agents/skills/          Shared project workflows
.claude/skills/          Claude pointers to the shared workflows
.cursor/rules/          Cursor pointer to AGENTS.md
.github/                Issue/PR templates and Copilot instructions
.vscode/                Editor settings and extension recommendation
docs/                   Mintlify handbook source
tools/                  Repository metadata check
AGENTS.md               Canonical engineering instructions
```

The root Markdown files cover licensing, contribution, security, AI assistance, compatibility and the roadmap. See [architecture](docs/architecture.mdx) for the package layout and implemented surfaces. REST, Gateway, client and examples will be added with tested implementation.

With Python 3.10+ and Git available, run `python tools/check_repository.py` to check tracked-path exclusions, documentation navigation and skill metadata. This checks repository metadata only. Python is for maintenance tooling; it is not an SDK runtime requirement. The handbook validates locally with `mint validate` and `mint broken-links` in `docs/`.

## Contributing

Issues, pull requests and design discussions are welcome. If you're planning a substantial change, open a discussion first; it's easier to agree on the design before either of us spends a weekend implementing it.

AI-assisted contributions are welcome. Read, understand and test the changes before submitting them, and disclose material AI involvement. See [CONTRIBUTING.md](CONTRIBUTING.md), [AI_POLICY.md](AI_POLICY.md) and [AI_DISCLOSURE.md](AI_DISCLOSURE.md).

## Security

Please report vulnerabilities privately using the process in [SECURITY.md](SECURITY.md).

## License

[Apache-2.0](LICENSE). Diszig is an independent Greyfoundry project and is not affiliated with or endorsed by Discord.

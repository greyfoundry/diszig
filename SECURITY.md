# Security policy

Diszig is in early development and has no supported production release yet. Supported releases and compiler versions will be listed in COMPATIBILITY.md once available.

Report suspected vulnerabilities privately through GitHub's private vulnerability reporting feature if enabled on the repository. If unavailable, contact a maintainer through a private channel they have explicitly published; do not post sensitive details publicly. Maintainers must enable or document a real private reporting channel before the first release. No response-time guarantee is made.

Include affected versions, impact, minimal reproduction, environment, and any suggested fix. Redact bot tokens, webhook and interaction tokens, OAuth secrets, user data and logs. Do not test against other people's bots or guilds without permission. Coordinate disclosure with maintainers.

We treat TLS, credential handling, memory safety, untrusted inputs, Discord signatures/rate limits, sharding IPC and release integrity as security boundaries. Do not disable them for convenience. See CONTRIBUTING.md and AI_POLICY.md for review expectations.

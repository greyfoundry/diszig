# Test fixtures

Fixtures are synthetic, deterministic inputs for protocol and failure tests.
They are not captured production traffic.

## Rules

- Use invented IDs, names, tokens and email addresses. Email domains must be
  `example.com`, `example.invalid` or `example.org`.
- Never commit a real bot token, webhook token, OAuth secret, private key,
  production guild/channel/user ID or personal data. A fixture that looks like a
  credential is rejected by `python tools/check_coverage.py`.
- Keep JSON UTF-8 with LF newlines and a trailing newline. Prefer stable literal
  values over generated random data so failures are reproducible.
- Do not depend on the wall clock. Tests that need time inject a clock or use a
  fixed timestamp.
- Mock transport locally. Live Discord tests are separate, opt-in, and require
  explicit authorization and a dedicated test application.
- Allocation-failure coverage uses `std.testing.checkAllAllocationFailures` and
  verifies every partially acquired resource is released.
- Each fixture should have one clear purpose. Name files after the surface and
  case, for example `gateway/hello-missing-heartbeat.json`.

## Layout

```text
tests/fixtures/<surface>/<case>.json
tests/fixtures/<surface>/<case>.bin
```

Surface names follow the coverage manifest (`protocol`, `rest`, `gateway`,
`components`, `interactions`, `sharding`).

## Changing a fixture

State the protocol question, the authoritative source, the expected behaviour
and the test that consumes it. If the fixture encodes an undocumented Discord
behaviour, record a decision and keep the fixture reviewable. Do not update a
fixture merely to make a failing test pass.

## Current fixtures

There are no data fixtures yet. The protocol tests use inline literal values
covering Snowflake boundaries, JSON presence, unknown enums and allocation
failure. Add files only when a second test or a shared consumer needs them.

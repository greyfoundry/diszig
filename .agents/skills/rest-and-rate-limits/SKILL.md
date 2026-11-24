---
name: rest-and-rate-limits
description: Implement or review Discord REST, rate limiting, retries, uploads and API errors.
---

# rest-and-rate-limits

Read root AGENTS.md first; its invariants apply.

Check documented rate limits, normalized routes, major parameters, auth scope, global/shared buckets, retry-after and invalid request limits. Design a bounded cancellable scheduler using monotonic time. Never blindly replay ambiguous non-idempotent requests. Redact token-bearing paths and headers; validate TLS and redirects. Test bucket discovery/collision, 429 across workers, cancellation, timeout, malformed response, streaming and overload with a local mock server. Document coordination across hybrid workers. Verify raw requests use the same safeguards.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

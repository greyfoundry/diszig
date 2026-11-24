---
name: gateway-recovery
description: Implement or review Gateway sessions, reconnects, dispatch and compression.
---

# gateway-recovery

Read root AGENTS.md first; its invariants apply.

Model connection states and documented close codes. Check Hello, heartbeat jitter/ACK, sequence, resume URL/session, invalid session, reconnect opcode, identify budget and send limits. Keep heartbeat progress independent of application callbacks; bound queues/decompression/frames. Test missing ACK, delayed callback, malformed frames, resume/reidentify, fatal close, cancellation and partial init. Verify per-shard isolation and document ordering/replay. Do not claim exactly-once delivery.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

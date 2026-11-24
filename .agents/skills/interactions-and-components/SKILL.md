---
name: interactions-and-components
description: Implement application commands, HTTP interactions, legacy components or Components V2.
---

# interactions-and-components

Read root AGENTS.md first; its invariants apply.

Verify current docs for component contexts, counts, flag restrictions, legacy/V2 transition rules and interaction response deadlines. Maintain separate typed validation with raw escape path; never silently rewrite or strip user fields. Track unacknowledged/deferred/replied states and concurrent acknowledgement. HTTP signature checks use original raw bytes and verified timestamp/signature; bound inputs. Test invalid flag/content mixes, nested components, modal restrictions, attachment references, mention policy, deferral/edit/followup/autocomplete, duplicate ACK and bad signatures. Compile usage examples.

Return concrete findings or actual changes, tests, limitations and next action. Do not claim completion without evidence.

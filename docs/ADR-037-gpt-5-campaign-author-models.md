# ADR-037: Sanction gpt-5 and openai-codex-gpt-5 as Traditional Campaign Authors

**Date:** 2026-10-01  
**Status:** Accepted (owner decision)

**Context:** ADR-036 sanctions `gpt-5.6-sol` as a Traditional author for the
Bible PAL length-expansion campaign, IDs 3000–3258. Packet 012 stories
3050–3054 were accepted and committed in `cd0127dc` with
`createdByModel: gpt-5`. Uncommitted packets 005, 006, 007, 010, and 011 record
`gpt-5` or `openai-codex-gpt-5`. These are text-only Traditional campaign
stories; the Dart story engine compliance check did not recognize either
string.

**Decision:** Sanction `gpt-5` and `openai-codex-gpt-5` as Traditional text
author/writer model strings for this campaign only. Each writer must be paired
with an independent reviewer from a different provider and model. Existing
owner gates remain in force.

**Rationale:** Accepted campaign metadata must pass app compliance without
rewriting the recorded author. The strings differ from ADR-036's only in how
the writer run labelled itself inside the same bounded campaign.

**Consequences:** The Dart `createdByModel` compliance check accepts `gpt-5`
and `openai-codex-gpt-5` only for Traditional stories with numeric IDs
3000–3258. They remain rejected outside that range, in Creative mode, and for
non-numeric story directories. ADR-036 and the existing allowlists are
unchanged. This decision changes neither story metadata nor the
writer/reviewer independence rule. It does not authorize audio, manifest
promotion, controller transitions, publication, or owner-gate bypass.

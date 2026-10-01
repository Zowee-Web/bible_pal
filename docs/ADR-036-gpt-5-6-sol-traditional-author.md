# ADR-036: Sanction gpt-5.6-sol as a Traditional Campaign Author

**Date:** 2026-09-30  
**Status:** Accepted (owner decision)

**Context:** Packet 009 stories 3035–3039 were accepted and committed in
`21717640`. Their metadata records `createdByModel: gpt-5.6-sol`, but the Dart
story engine compliance check did not recognize that model. The current Bible
PAL length-expansion campaign covers IDs 3000–3258.

**Decision:** Sanction `gpt-5.6-sol` as a Traditional text author/writer model
for this campaign, including Packet 009 and future manual or mailbox-assisted
packets. Each writer must be paired with an independent reviewer from a
different provider and model. Existing owner gates remain in force.

**Rationale:** The accepted Packet 009 metadata must pass app compliance.
Changing writer/reviewer roles would broaden production work during the Factory
Hardening Freeze.

**Consequences:** The Dart `createdByModel` compliance check accepts
`gpt-5.6-sol` only for Traditional stories with IDs 3000–3258. This decision
changes neither story metadata nor the writer/reviewer independence rule. It
does not authorize audio, manifest promotion, or controller transitions.

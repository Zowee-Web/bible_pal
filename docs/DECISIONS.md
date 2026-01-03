# Bible PAL - Architecture Decision Records

This document logs key design decisions and trade-offs made during development.

---

## ADR-001: History Limit Reduced to 20 Entries

**Date:** 2026-01-03
**Status:** Accepted
**Context:** SPEC.md originally specified 100 history entries, but INVARIANTS.md enforced 20 entries. Code implementation followed INVARIANTS (20 entries).

**Decision:** Align SPEC.md with INVARIANTS.md by changing History limit from 100 to 20.

**Rationale:**
- 20 entries provides sufficient history for user needs
- Reduces storage footprint on mobile devices
- Aligns with existing code implementation
- INVARIANTS document takes precedence for safety-critical limits

**Consequences:**
- SPEC.md §11 updated: "Stores last **20 entries only**"
- No code changes required (already implemented correctly)

---

## ADR-002: Multi-Voice Playback Deferred

**Date:** 2026-01-03
**Status:** Deferred
**Context:** SPEC.md §17 originally specified "Multiple voices per story" as a feature. Testing revealed quality issues with child voices (Grant, Abilene) and multi-voice coordination complexity.

**Decision:** Defer multi-voice playback. Use single narrator voice per story.

**Rationale:**
- Child voices (Grant, Abilene) did not sound natural in stories
- Multi-voice coordination adds production complexity
- Single narrator provides consistent, high-quality experience
- Feature can be revisited when voice quality improves

**Consequences:**
- SPEC.md §17 updated: "Single narrator voice per story (multi-voice deferred)"
- Multi-voice generation scripts disabled (.DISABLED suffix)
- Existing multi-voice test story removed from manifest
- Grant and Abilene voices commented out in .env

---

## Template for Future Decisions

```
## ADR-XXX: [Title]

**Date:** YYYY-MM-DD
**Status:** [Proposed | Accepted | Deprecated | Superseded]
**Context:** [What is the issue?]

**Decision:** [What was decided?]

**Rationale:** [Why was this decided?]

**Consequences:** [What are the effects?]
```

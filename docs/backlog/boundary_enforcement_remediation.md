# Backlog — Traditional Boundary Enforcement Remediation

**Discovered:** 2026-05-30 during CI repair triage finalization.
**Status:** Deferred. Per-story editorial review needed.
**Test failing:** `test/critical/traditional_boundary_enforcement_test.dart::Post-ADR-025 stories (>= 826) have no boundary drift`
**Scope:** 81 violations across 35 stories with 9 unique drifted phrases.

## What the test checks

Post-ADR-025 (story IDs ≥ 826) stories must not extend their narrative beyond the scriptural anchor's boundary. Phrases that introduce events, time-passage, or aftermath not present in the anchor passage are flagged as "boundary drift."

## Drifted phrases found (9 unique)

- "From that day forward"
- "Later that day"
- "as dusk"
- "as the evening"
- "from that day forward"
- "from then on"
- "in the days that followed"
- "long after"
- "when they departed"

These look like editorial flourishes that nudge the story past its anchor — closing with "from that day forward" implies post-event continuation that the anchor passage doesn't specify, etc.

## Why this is editorial, not mechanical

Each occurrence needs a per-story call:
- **Rewrite** to stay within the anchor (most common case)
- **Accept** if the phrase is itself scriptural ("from that day forward" appears in some passages)
- **Re-anchor** if the story's actual scriptural scope was wider than the registered `bibleSourceRef`

Bulk-stripping would lose the editorial intent and possibly introduce sentence-fragment artifacts.

## Related craft memory

- `feedback_complete_arcs`: "Single literary units (psalm, oracle, patterned list) must include the full arc; never truncate at the turning point." So the anchor itself defines the boundary — extending past it violates that contract.
- `feedback_story_settles_endings`: Endings must "settle" (life continues) — but the "settle" should be within the anchor's frame, not imported from outside it.

## Recommended remediation path

1. Triage CSV: each violation tagged as DRIFT (rewrite), SCRIPTURAL (accept), or RE-ANCHOR.
2. For DRIFT: per-story rewrite of the closing 1-2 sentences.
3. For SCRIPTURAL: update the test to allow specific phrases if their containing sentence is a direct scripture quote.
4. For RE-ANCHOR: update `bibleSourceRef` to the wider passage that actually covers the story.

## Estimated effort

- 35 stories to triage. ~1 hour editorial review.
- Per-story edits: ~10 min each = ~6 hours if most are DRIFT.

Total: half-day focused editorial session.

## What to do for now

Test stays red. Same backlog pattern as theme-tag, word-count, relatability.

## Related still-open

These four content-quality remediations could be done in the same session:
- theme-tag remediation
- word-count compliance
- relatability/emotional tag remediation
- boundary enforcement (this doc)

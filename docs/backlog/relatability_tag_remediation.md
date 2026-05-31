# Backlog — Relatability/Emotional Tag Remediation

**Discovered:** 2026-05-30 during CI repair triage.
**Status:** Deferred. Same shape as theme-tag remediation (`docs/backlog/theme_tag_remediation.md`).
**Test failing:** `test/services/relatability_tag_compliance_test.dart`

## Three failure categories

1. **754 invalid emotionalTags** across many stories — vocabulary mismatch against the locked allowed vocabulary. Examples of invalid (but semantically rich) tags found: `brave`, `resolute`, `settled`, `trusting`, `reverent`, `vindicated`, `encouraged`, `tender`, `awed`, `calm`, `earnest`, `longing`, `weary`.

2. **132 stories with >3 emotionalTags** — the schema enforces max 3, but many stories have 6.

3. **Coverage at 49.6%** vs required 50% — barely under threshold.

## Why this is the same problem as theme-tag

Just like `themeTags`, someone (or a batch generator) populated `emotionalTags` with descriptive vocabulary that wasn't in the locked allowed list. The current tags are valuable editorial signal — they describe the actual emotional registers each story carries. Bulk-stripping loses information.

## Recommended remediation

Same structural fix as the theme-tag plan:

1. Add a parallel `emotionTags` (or rename existing `emotionalTags` to a richer
   field) for storing the full descriptive vocabulary.
2. Map only the locked-vocabulary terms back into the test-validated field.
3. Cap to 3 per story for the validated field; preserve the rich set elsewhere.
4. Backfill the ~50.4% of stories missing entries.

## Scope estimate

- 754 invalid tag instances → likely 30-60 unique vocabulary terms needing mapping.
- 132 stories needing prioritization down to top-3.
- ~50 stories needing tag backfill to cross the coverage threshold.
- Test code change: update vocabulary set or add the dual-field pattern.

Total effort: 2-4 hours focused editorial session.

## What to do for now

Test stays red. Same as theme-tag and word-count backlogs: documented, not auto-fixed.

## Related backlogs

- `theme_tag_remediation.md` — same root pattern (curatorial overflow into a taxonomy field).
- These two tag remediations could be done in the same editorial session.

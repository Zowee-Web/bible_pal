# Backlog — Story Word Count Compliance Remediation

**Discovered:** 2026-05-30 during CI repair triage.
**Status:** Deferred. Same shape as theme-tag remediation — editorial pass per story, not a quick metadata fix.
**Test failing:** `test/core/story_word_count_compliance_test.dart::all production story text files meet word count ranges`
**Scope:** 196 violations across 160 stories.

## What the test checks

Every story file must fit its bucket:
- Short: 300-500 words
- Full:  501-900 words
- Long:  901-1500 words

## Why it's failing

A mix of intentional and unintentional drift:

### Intentional — exempt per locked craft memory

- **Psalm floor** (memory: `feedback_psalm_word_floor`): "Psalms allowed below 300w if full passage is included; don't extend with framing." Many of the <300w short violations are short psalms with the full passage rendered — not under-written.
- **Lyric long benchmark**: Story 1067 (Isaiah throne vision) at 1569w is locked as the lyric calibration reference (memory: `feedback_long_discipline`). Editorial decision to allow lyric expansion past 1500.
- **Bucket gate is CI-WARN-only**: Per memory `project_phase1_ci`, the pre-commit hook treats bucket out-of-range as WARN, not blocking. The standalone test treats it as failure — schema drift between gates.

### Unintentional — real word-count drift

Many <300w shorts are NOT Psalms but procedural narrative that simply ran short. Roughly half of the 196 violations fall here and would warrant either:
- Editorial expansion to hit 300w
- Or relaxing the floor to 250w (the smaller bucket is rarely audio-meaningful)

## Recommended remediation path

1. Per-story triage CSV: each violation tagged as PSALM-FLOOR, LYRIC-LONG, REAL-DRIFT.
2. For PSALM-FLOOR + LYRIC-LONG entries: add an `editorialBucketException: "<reason>"` field in meta, and update the test to skip stories carrying that field. Preserves the data signal.
3. For REAL-DRIFT entries: editorial expand/trim per story.
4. Update CI to align test + pre-commit hook so both gates agree.

## Estimated effort

- 196 entries to triage. ~30 minutes of editorial review by anchor pattern.
- Test code change to honor `editorialBucketException`: small.
- REAL-DRIFT expansion work depends on how many fall in this bucket (probably 60-100 stories).

Total: a multi-hour focused session, akin to the theme-tag remediation.

## What to do for now

Test stays red on this assertion. Same pattern as theme-tag and missing-reflection backlogs: tracked, not auto-fixed.

## Related still-open

- `feedback_length_buckets` (memory): the strict bucket lock from Batch 23 forward. New content honors it; legacy content (pre-B23) varies.
- The `editorialFlag: "exceptional"` field on some stories may overlap with this; review whether to unify the exception schema.

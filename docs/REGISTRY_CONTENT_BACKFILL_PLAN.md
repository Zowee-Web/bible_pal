# Registry & Content Backfill Plan

## Context

After PR #6 (`integrate/story-corpus-1287`) lands, master will carry the
1101–1287 story corpus. The integration deliberately deferred 16 known
content/registry failures rather than mixing structural-content edits into
the corpus-import PR. This document plans how those failures get resolved
across a sequence of focused follow-up PRs.

This plan is itself non-executable: it does **not** change code, content,
audio, or story text. It only inventories failures and proposes the PR
breakdown.

**Per Adam's directive on this plan PR:**
- ❌ No audio regeneration
- ❌ No story text edits
- ❌ No reflection text authoring (treated as content)
- ✅ Registry/metadata JSON edits OK in follow-up PRs
- ✅ Test/spec allowlist updates OK in follow-up PRs
- ✅ Vocabulary decisions OK in follow-up PRs (with Adam approval)

## Failure inventory (16 content/registry failures)

These are the failures NOT covered by PR #3 (`fix/pal-onboarding-wip`).
PR #3 covers the 22 PAL/onboarding refactor failures separately.

| # | Test | Failures | Root cause |
|---|------|----------|------------|
| 1 | `biblical_figure_registry_test` | 1 | ~165 manifest `bibleStoryKey`s lacking entries in `biblical_figure_registry.json` |
| 2 | `traditional_canonical_story_map_test` | 2 | (a) manifest keys missing from registry (overlaps with #1); (b) story moods don't match anchor `moodTags` (831, 1115, 1163) |
| 3 | `traditional_bible_story_test` | 2 | Duplicate root cause of #2 (ADR-022 invariant) |
| 4 | `manifest_annotation_integrity_test` | 2 | (a) `primaryCharacterId` not in `character_registry.json` (~25 ids: hannah, thomas, philip, stephen, ezra, ezekiel, habakkuk, hosea, joel, naboth, haggai, etc.); (b) `themeTags` outside the locked 8-tag vocab (`prayer`, `presence`, `transformation`, `calling`, `humility`, etc.) |
| 5 | `relatability_tag_compliance_test` | 1 | 88 `emotionalTags` outside the allowed vocabulary (`patience`, `desperation`, `fear`, `danger`, `uncertainty`, etc.) across 1101+ |
| 6 | `narrator_voice_validation_test` | 2 | (a) Server scripts (`generate_pal_framing_audio_batch.sh`) use `VOICE_SHEPHERD/HOPE/STILLWATER` not in `voices.json` allowlist; (b) Manifest entries reference banned `VOICE_JOHN_DOE` / `VOICE_CHRIS_DEFAULT` |
| 7 | `story_engine_compliance_test` | 1 | `createdByModel="claude-opus-4-7"` for 1100s+/1200s — not in expected allowlist `{gpt-4.1, claude-opus-4-6}` |
| 8 | `reflection_consistency_test` | 3 | (a) `reflectionText` missing from meta JSON for many 1100s+ stories; (b) `reflection_*.txt` files missing for many 1100s+ stories; (c) `reflection_*.txt` content mismatch with `meta.reflectionText` (1080–1085) |
| 9 | `traditional_boundary_enforcement_test` | 1 | Boundary-drift phrases (`from that day forward`, `long after`, `in the days that followed`) in 12 spots across 6 stories (1022, 1030, 1069, 1087, 1093, 1197) |
| 10 | `story_word_count_compliance_test` | 1 | ~30 Creative 2000s stories outside their declared word ranges |

## Categorization by fix type

| Category | Failures | Risk | Adam approval needed? |
|---|---|---|---|
| **A — Registry additive backfill** (pure JSON, no rewrites) | #1, #2(a), #3(a), #4(a) | Low | No |
| **B — Vocabulary decision** (expand allowlist OR remap content) | #4(b), #5, #7 | Medium | **Yes — needs decision** |
| **C — Test allowlist / voices.json update** | #6 | Low | No (or minor decision) |
| **D — Mood-anchor metadata corrections** | #2(b), #3(b) | Low | No (small JSON edits) |
| **E — Content / text edits** (out of scope per Adam's rule) | #8, #9, #10 | — | Deferred |

## Proposed PR breakdown

### PR α — Registry additive backfill (Category A) — Low risk

**Scope:** JSON-only edits to bring `biblical_figure_registry.json` and
`character_registry.json` in line with the manifest.

**Files touched:**
- `assets/stories/biblical_figure_registry.json` — add missing entries for ~165 bibleStoryKeys (most already have framing audio + canonical metadata; this is just the registry plumbing)
- `assets/stories/character_registry.json` — add ~25 missing characters

**Tests targeted:** #1, #2(a), #3(a), #4(a)

**Expected outcome:** ~6 of 16 failures resolved. No content changes.

**Verification:** run `flutter test test/core/biblical_figure_registry_test.dart test/critical/traditional_canonical_story_map_test.dart test/critical/traditional_bible_story_test.dart test/features/paths/manifest_annotation_integrity_test.dart`. All four files should drop their cross-validation failures, though the **manifest_annotation_integrity** test still fails on `themeTags` until PR β.

### PR β — Vocabulary decisions (Category B) — Needs Adam decision

**Three connected decisions:**

1. **`emotionalTags` allowlist (Category B, #5):** the corpus uses 88 tags outside the current vocabulary. Two options:
   - β.i — Expand allowlist to cover the new tags (faster, accepts existing content)
   - β.ii — Remap stories to existing tags (preserves narrow vocab, requires per-story metadata edits)
2. **`themeTags` allowlist (#4(b)):** locked 8-tag vocab (`faith`, `hope`, `mercy`, `courage`, `obedience`, `provision`, `patience`, `forgiveness`) vs. corpus tags (`prayer`, `presence`, `transformation`, `calling`, `humility`, `service`, `guidance`, `trust`, ~10 more). Same options as above.
3. **`createdByModel` allowlist (#7):** add `claude-opus-4-7` to the allowlist in `test/core/story_engine_compliance_test.dart`. This is a one-line test fix (this batch was authored by claude-opus-4-7 intentionally; the model allowlist needs to catch up).

**Files touched (β.i path — minimal):**
- `lib/core/relatability_tag_registry.dart` (or wherever `emotionalTags` allowlist lives) — add the new tags
- The themeTag locked-vocab source-of-truth file — expand vocab
- `test/core/story_engine_compliance_test.dart` — add `claude-opus-4-7` to allowed model list

**Tests targeted:** #4(b), #5, #7

**Expected outcome:** ~3 of 16 failures resolved.

**Decision request to Adam:** β.i (expand vocab) vs β.ii (remap stories)?
The expansion path is much smaller and lets stories ship with the words
that fit them; the remap path keeps a tight vocab but means ~88 metadata
edits and risks dropping evocative tags.

### PR γ — Voice allowlist + manifest narrator fixes (Category C, #6)

**Scope:**
- `server/voices.json` — confirm whether `VOICE_SHEPHERD`/`VOICE_HOPE`/`VOICE_STILLWATER` belong in the story-narrator allowlist OR whether the test scope should exclude PAL-only voice scripts
- Manifest narrator swaps for legacy entries using banned `VOICE_JOHN_DOE` / `VOICE_CHRIS_DEFAULT` (those entries cover stories 1003, 1005, 2000s — the 1003/1005 ones may need a decision; the 2000s are Creative legacy that might just need a voice rotation)

**Files touched:**
- `server/voices.json` (or test scope filter)
- Selected manifest entries (small swaps, no story text)

**Tests targeted:** #6

**Expected outcome:** ~2 of 16 failures resolved. Some manifest edits but no story content edits.

### PR δ — Mood-anchor metadata corrections (Category D, #2(b)+#3(b))

**Scope:** three stories whose `mood` doesn't match their anchor's
`moodTags`:
- `story_831_calm_peaceful_*` (anchor `joseph_interprets_pharaohs_dreams` moodTags=[encouraging])
- `story_1115_calm_peaceful_*` (anchor `road_to_emmaus` moodTags=[encouraging])
- `story_1163_calm_peaceful_*` (anchor `annunciation_to_mary` moodTags=[anxious, joyful])

**Two options per story:**
- δ.i — expand the anchor's moodTags in `scripture_anchor_registry.json` to include `calm_peaceful`
- δ.ii — change the manifest entries' mood (this affects serving — discuss before doing)

**Recommend δ.i for 831/1115** (those passages CAN evoke calm peace as a secondary read), and δ.ii **probably** for 1163 (annunciation is anxious-resolved-by-grace, not calm-peaceful — but the story version may have leaned into peaceful).

**Files touched:** `assets/stories/scripture_anchor_registry.json` only (per
δ.i) — no story content.

**Tests targeted:** #2(b), #3(b)

**Expected outcome:** ~2 of 16 failures resolved (the mood-mismatch parts of
the two duplicate ADR-022 tests).

### PRs deferred — Category E (content/text)

Three failure types are explicitly **out of scope per Adam's "no audio /
no story text" rule** and will land in separate later PRs:

- **#8 reflection_consistency** — generating ~150+ `reflection_*.txt` files for the 1100s+ corpus, plus reconciling 1080–1085 meta-vs-file mismatches. This is content authoring; will need a dedicated authoring batch.
- **#9 traditional_boundary_enforcement** — 12 surgical phrase edits across 6 story texts (1022, 1030, 1069, 1087, 1093, 1197). Tiny content edits but Adam's rule excludes them from this plan.
- **#10 story_word_count_compliance** — 30 Creative 2000s stories outside word range. Either trimming/expanding text or relaxing the test's per-bucket bounds. Content-side decision.

These deferred items are tracked here so they aren't lost — each gets its
own focused PR when Adam is ready to spend that authoring budget.

## What this plan PR does NOT include

- No registry edits (this is a planning doc only)
- No vocabulary changes
- No test/spec updates
- No voices.json changes
- No content edits
- No audio
- Just `docs/REGISTRY_CONTENT_BACKFILL_PLAN.md` and this overview

## Decisions needed from Adam

1. **Vocab strategy (β.i vs β.ii):** expand `emotionalTags` and `themeTags` allowlists to fit corpus, or remap stories' tags to the locked vocabs?
2. **Mood-anchor (δ.i vs δ.ii):** expand anchor `moodTags` to include calm_peaceful for 831/1115, or change story moods? Same question for 1163 (annunciation).
3. **Voice allowlist scope (γ):** are `VOICE_SHEPHERD/HOPE/STILLWATER` story-narrator-eligible or PAL-only? The test currently flags them as not allowed for narration.
4. **Reflection text authoring (deferred):** when to schedule the ~150-file reflection authoring batch?
5. **Boundary drift (deferred):** approve the 12 surgical phrase edits, or relax the test for legacy stories?

## Verification approach

Each follow-up PR should run only its targeted failing test files and
confirm zero net-new failures elsewhere. Sample command for PR α:

```bash
flutter test \
  test/core/biblical_figure_registry_test.dart \
  test/critical/traditional_canonical_story_map_test.dart \
  test/critical/traditional_bible_story_test.dart \
  test/features/paths/manifest_annotation_integrity_test.dart
```

After all 4 PRs (α, β, γ, δ) merge, expect failure count to drop from 16
to 3 (the deferred Category E items). Combined with PR #3 (PAL/onboarding,
22 failures), the path to a fully green master is then: PR #3 + PRs α/β/γ/δ
+ later content-authoring PRs for #8/#9/#10.

## Sequencing recommendation

1. **PR α (registry backfill)** — independent, low-risk, ship first
2. **PR β (vocabulary)** — needs Adam's decision; ship second
3. **PR γ (voice cleanup)** — minor; ship third
4. **PR δ (mood-anchor metadata)** — needs Adam's decision on 831/1115/1163; ship fourth
5. **Deferred content-authoring PRs** — schedule when Adam is ready to author reflection texts and (optionally) edit boundary phrases / Creative 2000s word counts

PRs α through δ are all independent of each other (no overlapping files except possibly the manifest in γ); they can be opened concurrently and merged in any order.

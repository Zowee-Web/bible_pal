# Handoff Prompt — Bible PAL Next Session

Copy everything below this line into a fresh Claude window. The user is Adam Lipps. This brief is self-contained — assume no prior conversation.

---

You're picking up Bible PAL — a Flutter app that delivers personalized audio Bible-story narration based on user mood. The corpus is dual-lane (WEB primary + KJV companion translations only — both are public-domain). Working directory: `/Users/adamlipps/bible_pal`. Branch: `master`.

This session has three focused tracks. **Do them in this order. Do not start audio generation; audio is gated until Adam explicitly says go.**

## Track 1 (start here) — Editorial backlog: 6 reflection-drift stories

This is the smallest deferred backlog item from the previous session. Spec is in `docs/backlog/reflection_drift_six_stories.md` — read it first. Summary:

Five stories (**1096, 1097, 1098, 1099, 1100**) have a schema mistake: `meta.reflectionText` contains scripture paraphrase instead of reflection prose. The reflection prose lives correctly in `reflection_<id>_traditional_web.txt`. Recommended fix: sync `reflection_<id>_traditional_web.txt` content → `meta.reflectionText` for those five (mechanical, no editorial judgment needed).

One story (**1515**) has real word-level prose drift between meta and KJV file (~265 chars match, then diverge). Needs an editorial judgment: which side is canonical? Likely the file (it's user-facing), so sync file → meta — but confirm with Adam before touching.

Verification: `flutter test test/core/reflection_consistency_test.dart`. The failing assertion is "reflection .txt content exactly matches meta.reflectionText" — expect it to drop from 6 mismatches to 0 once these are synced.

Commit separately as `fix(corpus): sync reflectionText for the 6 drifted stories` (or similar). Do not touch the other deferred reflection categories (149 missing field + 144 missing file — that's the known 364-story retrofit project per `feedback_every_story_needs_reflection` memory; out of scope here).

## Track 2 — Scripture text-file coverage audit

Audio is blocked until this is verified. The question: does every Traditional story have a usable `scripture_<id>_<lang>.txt` file in its directory?

Inspection points:
- `scripts/backfill_scripture_text.py` is the canonical generator. It walks every story dir, reads `meta_<id>.json` for `scriptureAnchor`, parses the reference, extracts verses from `server/data/bible_<lang>.json`, and writes `scripture_<id>_<lang>.txt`. It will fail loudly on parse errors.
- `scripts/lib/bible_ref_parser.py` is the reference parser (handles single verse, ranges, multi-chapter, comma-separated discontinuous like "John 14:1-3, 18-19, 27").
- Both bundled bibles (`server/data/bible_web.json`, `server/data/bible_kjv.json`) cover full Protestant 66-book canon (~31K verses each, sourced from eBible.org + scrollmapper/bible_databases on 2026-05-30).

What to do:
1. `python3 scripts/backfill_scripture_text.py --dry-run` — see what would be regenerated. Tracks any parse failures.
2. If clean, run it for real to refresh every file. Compare diff (`git diff --stat`) to confirm scope.
3. Spot-check 5-10 random stories: scripture file exists, contains the right passage, matches `meta.scriptureAnchor`.
4. Report any anomalies to Adam. Don't auto-fix scripture content drift without confirmation.

If everything passes, that unblocks the audio gate (subject to Adam's explicit approval still).

## Track 3 — Tier 3 careful review (NOT generation-first)

Adam flagged 6 stories for editorial review BEFORE generating Full/Long variants. His exact framing: "These have more exposition/theology risk and are harder to keep in Daniel-standard narrative form."

The 6 stories:

| ID | Title | Anchor | Mood |
|----|-------|--------|------|
| 1228 | Now Faith Is Assurance | Hebrews 11:1-22 | encouraging |
| 1224 | More Than Conquerors | Romans 8:18-39 | encouraging |
| 1230 | Have You Not Known? Have You Not Heard? | Isaiah 40:12-31 | encouraging |
| 1194 | I Will Pour Out My Spirit | Joel 2:12-32 | encouraging |
| 1212 | Be Strong, and Work | Haggai 2:1-23 | encouraging |
| 1506 | The Ancient of Days | Daniel 7:1-14 | anxious |

Your job is **not** to start writing prose. Your job is:

1. **Read the Short text of each.** The existing Short is in `assets/stories/traditional/<id>/story_<id>_traditional_web_short.txt`. Understand the editorial frame already established.
2. **Read the scripture text.** `assets/stories/traditional/<id>/scripture_<id>_web.txt`. Note the genre (epistolary doxology vs apocalyptic vision vs prophetic oracle).
3. **Classify each one.** For each story, write 2-3 sentences answering: *Can this grow Full+Long while staying scripture-faithful and Daniel-standard (dramatic progression, not exposition)?* The honest answers might be:
   - **GROW** — the passage has enough narrative scaffolding (e.g., Hebrews 11's roll call is patterned-list, can stage one figure per beat).
   - **SKIP** — the passage is fundamentally theological exposition; a Long variant would padding-pad-pad to bucket.
   - **MAYBE** — could go either way; needs Adam's per-story call.
4. **Surface to Adam as a table.** Do not start writing Full/Long for any until he approves. Use the format of Tier 1 / Tier 2 proposal tables from prior sessions (see git log for `4d8b8d6` and `0ff1e25` for examples).

If you do end up generating Full/Long for any approved subset, use the locked calibration standards (see "Critical context" below) and the same 3-story autonomous block cadence used for Tiers 1 and 2.

## Critical context — read before starting any track

### Where the locked craft rules live

`/Users/adamlipps/.claude/projects/-Users-adamlipps-bible-pal/memory/` contains Adam's persistent craft instructions across sessions. The relevant files for this session (read these first):

- `feedback_long_grows_via_drama.md` — Long variants must grow through dramatic progression, NOT environmental padding. The **gold-standard calibration story is 1117 Red Sea Long** (`assets/stories/traditional/1117/story_1117_traditional_web_long.txt`). Read it before writing any prose.
- `feedback_genre_aware_narrator.md` — Procedural anchors (Daniel court, Acts narrative) stay strictly observable. Lyric anchors (Psalms, Isaiah poetics, apocalyptic visions) allow interpretive narrator clauses and image-bearing similes drawn from scripture's own imagery. **Lyric benchmark stories: 1067 Isaiah throne vision, 1069 Psalm 139, 1077 Psalm warmth**. Both Hebrews 11 and Daniel 7 from Tier 3 are lyric-leaning — the lyric brief applies.
- `feedback_no_inline_reflection.md` — Story files contain prose only. Reflections live in `reflection_*.txt` files. Never append a "Reflection." paragraph to story files.
- `feedback_audio_end_clip.md` — Soft-consonant endings (n/m/ng/l/soft-sh/voiced-z). Hard plosives (p/t/k) get clipped by the v3 TTS.
- `feedback_pause_before_audio.md` — Always pause for Adam's confirmation before audio generation. Even in autonomous flow, this is a hard checkpoint.
- `feedback_autonomous_generation.md` — In active flow, ship 3-story blocks autonomously with condensed reports. Don't ask permission for voice/anchor picks. But always pause before audio.

Skim `MEMORY.md` in that same dir for the full index — there are many more locked feedback memories you'll want to be aware of.

### Project documentation

- `CLAUDE.md` (repo root) — workflow rules and key file pointers.
- `docs/SPEC.md` and `docs/INVARIANTS.md` — product/behavior contracts (highest authority).
- `docs/BIBLE_TRANSLATION_COMPLIANCE.md` — only WEB, KJV, ASV, YLT, DRA are allowed. NIV/ESV/NRSV/NLT/NASB/CSB/MSG/HCSB/AMP/GNT are BANNED. Don't use them, don't reference them.

### Recent session backlog docs (read these to avoid duplicating triage work)

- `docs/backlog/theme_tag_remediation.md` — 1001 invalid tags / 219 stories. DEFERRED.
- `docs/backlog/word_count_compliance_remediation.md` — 196 violations / 160 stories. DEFERRED.
- `docs/backlog/relatability_tag_remediation.md` — 754 invalid + 132 over-cap. DEFERRED.
- `docs/backlog/reflection_drift_six_stories.md` — Track 1 work.
- `docs/backlog/boundary_enforcement_remediation.md` — 81 violations / 35 stories. DEFERRED.

### Corpus state

- 47 stories have Full+Long across both WEB and KJV lanes (25 Phase 2 GROW + 12 Tier 1 + 10 Tier 2). Committed in `61befb7`, `4d8b8d6`, `0ff1e25`.
- The 6 Tier 3 stories (track 3) currently have only Short.
- Audio has NOT been rendered for any of the 47 newly-grown stories. The audio render pipeline is gated.

### The 1117 calibration discipline (most important craft rule)

Adam approved `1117_traditional_web_long.txt` as the gold-standard Long. The rhythm to match:

- panic → Moses speaks → Lord's command → pillar shift → sea opens → crossing → pursuit → wheel failure → waters return → aftermath
- Each paragraph either advances the story or develops character reaction. NONE just dresses the room.
- The reference test before writing each paragraph: "Does this advance the story or develop a reaction? Or does it just dress the room?" If it dresses the room, cut it.

If you generate any prose, that test gates every paragraph.

## Adam's communication preferences

- He's terse. Match that. Brief updates, short summaries, no preamble.
- He likes punch lists, tables, and clear status (✓ / ⚠ / 📋 / ❌).
- He pushes back hard when something's off — don't be defensive, absorb and adjust.
- He often asks "what do you think of this?" — that's an exploratory question, not a request for action. Answer in 2-3 sentences with a recommendation and the main tradeoff.
- He says "push it" or "go" when he wants you to commit/push/launch. Don't wait for more permission.
- He says "what do you think" to invite pushback. If a plan has a flaw, surface it before executing.
- He never wants you to delete audio files. Move/organize only.
- He explicitly says when he wants a separate commit vs combined. Default to separate commits per logical unit.

## What to NOT do

- Do NOT render audio. Period. (ElevenLabs costs are real; gate is explicit.)
- Do NOT start theme-tag, word-count, relatability, or boundary remediation — those are larger backlog projects waiting on dedicated sessions.
- Do NOT modify the 364-story missing-reflection backlog without explicit approval.
- Do NOT modify the 1117 Red Sea calibration story or the 1067/1069 lyric benchmarks. They're locked references.
- Do NOT use any Bible translation outside the 5-translation allowlist (WEB, KJV, ASV, YLT, DRA).
- Do NOT bypass `BibleTranslationRegistry` runtime guards.
- Do NOT push to origin without Adam's explicit "push" command.
- Do NOT generate prose for Tier 3 until Adam approves a specific subset.

## Suggested opening sequence

1. Read `CLAUDE.md`, the memory directory's `MEMORY.md` index, and the five backlog docs.
2. Skim `1117_traditional_web_long.txt`, `1067_traditional_web_long.txt`, `1069_traditional_web_long.txt` to anchor the craft register.
3. Start Track 1 (6-reflection-drift sync) — it's the cleanest win and clears one CI test toward green.
4. Surface findings + commit + ask for push approval.
5. Move to Track 2 (scripture coverage audit).
6. Then Track 3 (Tier 3 classification table).

Each track should produce: clear findings → recommendation → explicit pause for Adam's call. Don't string them together autonomously.

## Quick verification commands

- `flutter test` — full suite. Expect ~11 failures, all in documented backlog categories.
- `flutter test test/core/reflection_consistency_test.dart` — gates Track 1.
- `python3 scripts/backfill_scripture_text.py --dry-run` — gates Track 2.
- `git log --oneline -15` — recent context: `0e175f8`, `246a0e3`, `44f752f`, `1444086`, `d44752e`, `40cbea8` are this session's CI repair commits; `0ff1e25`, `4d8b8d6`, `61befb7` are Tier 2 / Tier 1 / Phase 2 GROW corpus expansion.
- `git status -sb` — start clean (working tree should be empty on session start).

Good luck. Adam is detail-oriented and will catch drift fast, so default to surfacing rather than guessing.

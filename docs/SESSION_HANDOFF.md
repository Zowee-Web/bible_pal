# Bible PAL — Project Handoff

> **Date:** 2026-07-18 · **Purpose:** Self-contained handoff for a fresh Claude session (e.g. after switching development machines). Assumes the repo is already at latest `master`. No prior chat history required.

---

## 0. Orientation

Bible PAL is a Flutter/Dart app for faith-based storytelling: it generates personalized audio Bible stories ("parables") narrated with ElevenLabs TTS. Stack: Flutter, Riverpod, just_audio, ElevenLabs, SQLite + SharedPreferences. Delivery is R2-served (the app reads a remote catalog derived from `assets/stories/manifest.json`).

**Authoritative docs (read these; they win over any summary):**
- `CLAUDE.md` — workflow rules + document hierarchy
- `docs/INVARIANTS.md` (#1) — non-negotiables
- `docs/SPEC.md` (#2) — product spec
- `docs/BIBLE_TRANSLATION_COMPLIANCE.md` (#3) — public-domain translations only
- `docs/STORY_NARRATION_STYLE_GUIDE.md` (#7) — **now opens with §0 Two Governing Laws (see §4 below)**
- `docs/REFLECTION_VOICE.md` (#6), `docs/JOURNEY_TRANSITION_VOICE.md` (#9), `docs/DOCTRINE_OF_DOCTRINES.md`
- `docs/editorial/FULL_CANON_PRODUCTION_GATE.md` + `assets/stories/canon_production_gate.json` — the production plan

---

## 1. What this session accomplished

1. **Authored & shipped Wave 1a** — three Traditional-lane stories (John 1 Prologue, Peter's Confession, David at En-gedi), WEB + KJV short + reflection each, rendered to audio and merged (**PR #87**).
2. **Discovered and codified a narration doctrine** while rewriting the John 1 story — the "human register / Dual Faithfulness" laws (**PR #88**).
3. **Fixed a script safety bug** — `step4a_bible_order_backfill.py` executed a full backfill on any invocation including `--help` (**PR #89**).
4. **Recovered from a CI failure** caused by locked-vocabulary violations that targeted local test runs missed (see §5).

---

## 2. Merged PRs & key commits (all on `master`)

| PR | Title | Merge commit | Content commits |
|----|-------|--------------|-----------------|
| **#87** | Wave 1a Traditional (1562–1564) | `c544a95a` | `0314b3aa` (stories + audio), `cf2c030b` (vocab/registry compliance fix) |
| **#88** | §0 Two Governing Laws (narration doctrine) | `c3a5c93b` | `f8971d9c` |
| **#89** | step4a `--help` safety fix | `d44e4ed2` | `a722e697` |

**Wave 1a stories (final state):**

| ID | Title | Anchor | Gate | Mood | Narrator |
|----|-------|--------|------|------|----------|
| 1562 | The Word Became Flesh | John 1:1–18 | CG05 | encouraging | **VOICE_JAMES_HUSKY** |
| 1563 | You Are the Christ | Matthew 16:13–20 | CG04 | encouraging | VOICE_REVEREND_MICHAEL_C_VINCENT |
| 1564 | The Hem of the Robe | 1 Samuel 24 | CG06 | calm_peaceful | VOICE_DAVID_SHEPHERD |

Each is short-only (`lengths: ["short"]`), dual-lane (web + kjv), with a reflection per lane. Audio MP3s are git-tracked and on master (12 live files + archived superseded takes).

---

## 3. Important editorial decisions this session

- **1562 (John 1) was rewritten from a "creed" into testimony.** First draft was a complete, accurate doctrinal summary — and emotionally inert. It was rewritten in the register the passage is already in (an eyewitness looking back: *"we saw his glory"*), with the incarnation set as a standalone hinge (`And the Word became flesh. / He lived among us.`) and the opening establishing the cosmic height it falls from. Nothing was invented — the change was entirely register. Word floor cleared honestly by restoring v13 (not padding); **no `editorialBucketException`, no `shortScripture` flag.**
- **1562 narrator changed JOHN_BELOVED → JAMES_HUSKY.** JOHN_BELOVED (light/tenor, ~140 Hz) read the testimony flat (max ~0.9 s pause, no held beats). JAMES_HUSKY (~107 Hz, "wise elder") delivered the deeper, spacious read with real held beats (1.4–1.8 s). Owner-approved by ear. **Lesson: a script can create the space for wonder, but the voice must breathe it — TTS ignores paragraph breaks; a held "beat" comes from voice choice or explicit markup, not layout.**
- **Word-count floors:** 1562 (302w) and 1563 (WEB 311/KJV 315) — the correct fix for a thin idea-passage is faithful expansion or spare selection, **not** an exception field. The 300-word bucket is fine; how it's filled is what matters.
- **Audio archiving:** superseded 1562 takes were moved (never deleted) to `assets/stories/rejected/2026-07-18_1562_*`.

---

## 4. The narration doctrine (PR #88) — memorize this

Added as **§0 at the top of `docs/STORY_NARRATION_STYLE_GUIDE.md`**. Two laws, ordered by how authoring actually goes:

**Law 1 — Find the human register already inside the text.** Before writing, ask *"what kind of human speech is this Scripture?"* — testimony, prayer, lament, praise, warning, wonder, confession, exhortation, remembrance — and write in that register. Do not flatten to a summary; do not invent a scene. Register comes from **selection, emphasis, spacing, and the text's own voice**, never an added frame. Wrong question: "How do I turn this into a story?" Right question: "What experience is this Scripture already producing, and how do I let the listener have it?"

**Law 2 — Dual Faithfulness.** A story must be faithful **both** to what Scripture says **and** to the experience through which it reaches the listener; neither bought by sacrificing the other. This is the guardrail on Law 1 — the register must be the passage's *own*, surfaced, never one imported to make it land.
- Faithful-to-text but not-to-experience → *complete but emotionally distant* (an accurate summary no one finishes).
- Faithful-to-experience but not-to-text → *invention*.

**Acceptance audit (human-run gate — not machine-checkable):** (1) name the register in one word; (2) every image/emotion/frame traces to the passage; (3) residue test — an hour later, what does a first-time listener remember? A *realization* ("God came and lived with us") beats a line beats "there was something about the Word"; (4) keep-listening test — would someone who once found the Bible inaccessible press play on the next story?

Law 2 is cross-cutting: one-line cross-references were added to `REFLECTION_VOICE.md` and `JOURNEY_TRANSITION_VOICE.md`. It was kept in the narration guide (Option A) rather than elevated to its own hierarchy rank — promote later if cited across many systems.

---

## 5. The CI failure — record & lesson

**What happened:** PR #87's first push failed CI (1813 passed, 3 failed). Three locked-vocabulary/registry violations in the new metadata:
1. **themeTags** must be members of the `ThemeTag` enum (`lib/features/paths/theme_vocabulary.dart`). Invented tags (incarnation/light/grace/identity/restraint/conscience) were rejected. → remapped to valid members (presence, salvation, love, kingdom, righteousness, humility, …).
2. **emotionalTags** must be in the relatability `tagOrder` (`lib/core/relatability_tags.dart`), max 7. `assured`/`restrained`/`merciful` were invalid. → remapped (reassured, humbled, convicted).
3. Every traditional **bibleStoryKey** needs an entry in `assets/stories/biblical_figure_registry.json` (`test/core/biblical_figure_registry_test.dart`). → ran `scripts/backfill_figure_registry.py` (adds stub entries).

**Why it happened:** local validation ran a *curated subset* of test files, not the full suite. The vocabulary/registry tests weren't in that subset.

**How fixed:** remapped tags at the source (metas) + regenerated manifest, ran the figure-registry backfill, then ran the **full** `flutter test` locally (green) before re-pushing (`cf2c030b`). CI passed; PR merged.

**THE LESSON (do this every batch):** **Run the full `flutter test` — or let CI gate — before declaring a batch complete. Never a hand-picked subset.** That single habit would have caught all three.

---

## 6. Repository conventions, workflow rules & production gates

### Translation compliance (INVARIANT — never violate)
Only public-domain translations: **WEB** (default), **KJV**, **ASV**, **YLT**, **DRA**. All others banned (NIV, ESV, NRSV, NLT, NASB, CSB, MSG, HCSB, AMP, GNT, …). Enforced by `test/core/bible_translation_compliance_test.dart` + `repo_wide_compliance_scan_test.dart` (CI hard-gated). WEB prose uses "Yahweh"; KJV prose uses "the Lord."

### Story file layout (per story, `assets/stories/traditional/<id>/`)
`meta_<id>.json`, `story_<id>_traditional_{web,kjv}_short.txt`, `reflection_<id>_traditional_{web,kjv}.txt`, `scripture_<id>_{web,kjv}.txt`, and audio `audio_<id>_story_{,kjv_}short.mp3` + `audio_<id>_reflection{,_kjv}.mp3`.

### Metadata (`meta.schema.json`, schemaVersion 2) — LOCKED vocabularies
- **mood** (enum, 8): `encouraging, calm_peaceful, grateful, brave_courage, hurting, anxious, joyful, weary`.
- **timelineEra** (enum): `patriarchs, exodus, conquest, judges, kingdom, exile, return, wisdom, prophets, jesus_ministry, early_church`.
- **themeTags**: members of the `ThemeTag` enum only (`lib/features/paths/theme_vocabulary.dart`, ~146 values).
- **emotionalTags**: members of relatability `tagOrder` only (`lib/core/relatability_tags.dart`), ≤7.
- **storyVoiceKey**: from the approved narrator pool (`scripts/story_factory/story_voice_registry.py`; banned voices enforced). **Gender labels are unreliable — verify by ear.** Session-verified male: JAMES_BRITISH_PROFESSIONAL, REVEREND_MICHAEL_C_VINCENT, JAMES_HUSKY. Do not use banned voices (e.g. PETER_BOLD, MARCUS_ANCHOR, LILY_WOLFF, ELIJAH_SAGE, JOHN_DOE, CHRIS_DEFAULT, and PAL voices).
- **createdByModel**: `claude-opus-4-8` (current sanctioned model; `test/core/story_engine_compliance_test.dart`).
- **bibleStoryKey**: unique; must have a `biblical_figure_registry.json` entry (backfill script exists).
- **reflectionText**: must match the reflection file for `languageStyle` (`reflection_consistency_test.dart`).

### Word-count buckets (blocking)
Adult Traditional authoring bands: short 300–500, full 501–900, long 901–1500 (`test/core/story_word_count_compliance_test.dart`, checks WEB). These are **authoring bands** — distinct from the runtime bucket ranges in `lib/core/story_length_bucket.dart` (Short ≤600, Full 601–1200, Long >1200), which only label and serve what exists. Authoritative policy: [STORY_FACTORY.md §5](STORY_FACTORY.md#5-story-length-system-revised-2026-07-19--adr-030).

**Short is the default expected version. Full and Long are conditional** on what the approved anchor honestly supports — neither is universally required (ADR-030). Omit an unsupported length and document why in `editorialNotes`.

Carve-outs: `editorialBucketException` is **legacy only**. `shortScripture:true` is **available to new content as an explicit, owner-approved exception** when the complete approved passage is faithfully rendered but cannot honestly reach 300 words (first new-content use: story 1565, Luke 22:54-62, owner-approved 2026-07-19). Default remains faithful expansion or spare selection — never padding, invention, or commentary to reach a floor.

### Scripture boundary (ADR-025)
Stay inside the declared anchor; don't drift into adjacent pericopes. `test/critical/traditional_boundary_enforcement_test.dart` scans for post-boundary drift phrases.

### Audio
- Render: `bash scripts/generate_opus_audio.sh --story <id>` (reads `meta.storyVoiceKey`; model `eleven_turbo_v2_5`; `--dry-run` supported). Reflections render in the story's voice.
- **Skip logic is existence-based** — to re-render a changed file you must first move the old MP3 aside. **Never delete audio; archive to `assets/stories/rejected/<date>_<desc>/`.**
- Audio QA before shipping: integrity (valid mp3, sensible duration), no clipping (trailing silence present), no long dropouts (acoustic check via ffmpeg `silencedetect`, not whisper). Reflections target 10–30 s.

### Promotion / wiring pipeline (manual scripts, run after authoring)
1. `python3 scripts/promote_traditional_stories.py --ids <ids> --write` — appends manifest entries + scripture-anchor-registry entries; backfills `meta.scriptureAnchorId`. Idempotent (skips existing storyIds). Dry-run by default.
2. `python3 scripts/step4a_bible_order_backfill.py --write` — assigns `bibleOrderIndex`. **NOW dry-run by default (fixed this session); pass `--write` to apply.** Note: it re-encodes the whole manifest with `ensure_ascii=True` — beware of em-dash mangling.
3. `python3 scripts/backfill_figure_registry.py` — ensures every traditional bibleStoryKey has a figure-registry entry.
4. `python3 scripts/validate_corpus.py --paths <metas>` — schema + word-count bucket check.
5. **Full `flutter test`** — the gate that matters.

### Git workflow
Branch-first (never commit to `master` directly) → PR → wait for CI ("Test and Analyze") green → `gh pr merge --merge --delete-branch`. Commit-message trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. PR body footer: `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

### Delivery (separate from git)
Audio committed to git ≠ published to users. Reaching production requires refreshing the **R2 catalog** (`scripts/upload_r2_catalog.sh`) — a separate release step, not done this session.

### Production gate (content roadmap)
`docs/editorial/FULL_CANON_PRODUCTION_GATE.md` — 22 approved candidates in waves. **Wave 1a (CG04/05/06) is DONE.** Wave 1 remainder: The Fall (CG01), Cain & Abel (CG02), Peter's Denial (CG03), Bronze Serpent (CG07). The "both"-lane stories' **kid-lane versions are a later wave** (Wave 1a shipped Traditional/adult only). Journey Beat work is paused per `docs/JOURNEY_DOCTRINE.md` — do not author journey/arc JSON without direction.

### Machine setup (not shipped by git)
`.env` at repo root (gitignored) with `ELEVENLABS_API_KEY`, `ANTHROPIC_API_KEY`, `CLOUDFLARE_API_TOKEN`. Install pre-commit hook: `ln -sf ../../scripts/git_hooks/pre-commit .git/hooks/pre-commit`. Tools: Flutter (`flutter pub get`), Python 3 (`pip install jsonschema`), ffmpeg/ffprobe, jq, gh (`gh auth login`). Bundled Bible JSON (`server/data/bible_{web,kjv}.json`) IS tracked.

---

## 7. Next planned story — Peter's Denial (CG03)

**Why next:** it completes Peter's Gospel arc. The corpus already has the *restoration* (story **1130**, "Three Times by the Sea," John 21) — the healing without the wound. Authoring the denial retroactively charges that restoration: the denial's charcoal fire (John 18:18) is what the restoration's charcoal fire (John 21:9) answers. It also applies this session's new register method to a very different register — **grief / failure**.

**Agreed anchor decision (do not re-litigate):**
- **Narrative spine = Luke 22:54–62** — it holds the emotional payoff: the three denials, the rooster, *"The Lord turned and looked at Peter"* (v61), and *"He went out, and wept bitterly"* (v62).
- **Charcoal fire: draw ONLY the "fire of coals" detail from John 18:18** — same historical fire; enables the seam to the restoration (1130). Both passages are inside the gate's declared anchor, so this is not an out-of-bounds import.
- **Exclude John 18:19–24** (Jesus' interrogation before Annas) — different focus; dilutes Peter's story.
- **Register:** grief / failure — a man breaking under a question, then met by a look he can't escape.
- **Residue to aim for:** *the rooster, and the look — the instant his failure became undeniable, from the very one he'd sworn he didn't know.* (Not "Peter denied three times.")

**Proposed metadata (to be finalized at authoring):** ID **1565**; anchor recorded as `Luke 22:54-62` (charcoal-fire detail from parallel John noted in editorialNotes); mood likely `hurting`; narrator TBD (a male voice fitting grief/failure — verify by ear; keep batch voice diversity). Dual-lane WEB+KJV short + reflection, short-only.

**No drafting has begun.** No files created for 1565.

---

## 8. Current Status

- `master` is clean and fully pushed; PRs **#87, #88, #89 merged**. Local == `origin/master`.
- Wave 1a (1562/1563/1564) authored, rendered, wired, validated, merged. Audio on master.
- Narration doctrine (§0) and the step4a safety fix are on master.
- **Next available Traditional story ID: `1565`.**
- Open delivery thread: R2 catalog publish for Wave 1a (separate release step) — **not established/done**.
- CI is green on `master`.

## 9. Next Immediate Task

Author **Peter's Denial (story 1565, CG03)** per the anchor decision in §7:
1. Draft the **WEB short** first, in the **grief/failure register**, with the register named — spine from Luke 22:54–62, the "fire of coals" detail from John 18:18, Annas's interrogation excluded. Aim the residue at the rooster + the look.
2. **Pause and present the draft for approval before rendering anything** (this is the established workflow — writing is judged on the page first, audio second).
3. On approval: KJV mirror → metadata (run the vocabulary check against `ThemeTag` enum + relatability `tagOrder`) → promote/wire → figure-registry backfill → **full `flutter test`** → render (archive-then-render) → audio QA → branch/PR/CI-green/merge.

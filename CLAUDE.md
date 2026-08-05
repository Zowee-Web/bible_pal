# Claude Code Instructions for Bible PAL

Bible PAL is a Flutter app for faith-based storytelling. It generates personalized audio parables based on user mood using AI content and ElevenLabs TTS narration. [SPEC.md](docs/SPEC.md) and [INVARIANTS.md](docs/INVARIANTS.md) define product behavior. This file defines Claude workflow rules only.

**Stack:** Flutter/Dart, Riverpod, just_audio, ElevenLabs v3 API, SQLite + SharedPreferences

---

## Document Hierarchy

If CLAUDE.md conflicts with the official docs, **the official docs win**.

1. [docs/INVARIANTS.md](docs/INVARIANTS.md) — Non-negotiable rules (highest authority)
2. [docs/SPEC.md](docs/SPEC.md) — Product specification
3. [docs/BIBLE_TRANSLATION_COMPLIANCE.md](docs/BIBLE_TRANSLATION_COMPLIANCE.md) — Compliance details
4. [docs/PAL_VOICE.md](docs/PAL_VOICE.md) — Locked conversational voice for PAL (Five Pillars, eight principles, eight-question audit)
5. [docs/PAL_MEMORY_DOCTRINE.md](docs/PAL_MEMORY_DOCTRINE.md) — What PAL may remember, observe, and say from memory (four levels: Silence/Facts/Patterns/Meaning; silence floor)
6. [docs/REFLECTION_VOICE.md](docs/REFLECTION_VOICE.md) — Locked editorial voice for reflections (paste-test, six-point audit, benchmarks)
7. [docs/STORY_NARRATION_STYLE_GUIDE.md](docs/STORY_NARRATION_STYLE_GUIDE.md) — Locked editorial voice for story narration prose
8. [docs/JOURNEY_DOCTRINE.md](docs/JOURNEY_DOCTRINE.md) — Journeys: continuation cascade, silence floor, entry-point split, authoring discipline (parent of the transition voice)
9. [docs/JOURNEY_TRANSITION_VOICE.md](docs/JOURNEY_TRANSITION_VOICE.md) — Locked editorial voice for journey transition beats (relational-center rule, three signature tests, benchmark = coverage map)
10. [docs/AUDIO_LOUDNESS.md](docs/AUDIO_LOUDNESS.md) — Locked -18 LUFS loudness pipeline and per-lane audio treatment
11. [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — System architecture
12. [docs/DOCTRINE_OF_DOCTRINES.md](docs/DOCTRINE_OF_DOCTRINES.md) — Meta-standard: every locked standard needs an enforcement gate, a revision/demotion path, and a hierarchy rank (governs process, not content authority)
13. **CLAUDE.md** — This file (workflow guide only)

---

## CRITICAL: Bible Translation Compliance (NON-NEGOTIABLE)

**This is the most important rule in the project. It must NEVER be violated.**

Bible PAL must ONLY use public-domain Bible translations. Using copyrighted translations violates copyright law and exposes the project to legal liability.

**Allowed translations (EXHAUSTIVE — all others are BANNED):**
- **WEB** (World English Bible) — Default
- **KJV** (King James Version)
- **ASV** (American Standard Version)
- **YLT** (Young's Literal Translation)
- **DRA** (Douay-Rheims American Edition)

**Banned:** NIV, ESV, NRSV, NLT, NASB, CSB, MSG, HCSB, AMP, GNT, and ALL others not listed above.

**Enforcement:**
- Code-level allowlist: [lib/core/bible_translation_registry.dart](lib/core/bible_translation_registry.dart)
- Runtime guards reset to WEB if violation detected
- Build-failing tests and CI enforcement

**When working on translation-related code:**
- ALWAYS validate through `BibleTranslationRegistry`
- NEVER bypass the registry or runtime guards
- NEVER weaken or remove compliance tests
- Run compliance tests before committing:
  ```bash
  flutter test test/core/bible_translation_compliance_test.dart test/core/repo_wide_compliance_scan_test.dart
  ```
- If you see a violation, FIX it immediately

---

## Workflow Rules

### SPEC.md is Law
- All features and behavior must align with [docs/SPEC.md](docs/SPEC.md)
- Do not add features not in the spec
- Behavior changes require a SPEC.md update FIRST (with owner approval)

### Minimal Diff Discipline
- Only change code necessary for the requested task
- **Do not make "while I'm here" edits** — no reformatting, no renaming, no "improvements" to nearby code
- Remove unused code cleanly — no stubs, no `// removed` comments

### Stop and Ask Before Proceeding If:
- The request conflicts with an invariant
- A new data model or dependency is required
- User-facing behavior would change beyond what SPEC.md defines
- Architectural restructuring is needed
- You're unsure whether the change is in scope

### Phased Implementation
If a task is large or risky:
1. State the plan before coding
2. Identify files to change and relevant spec/invariants
3. Implement the smallest safe slice first
4. Verify before proceeding to the next slice

### Testing
```bash
# All tests (MUST PASS — diagnostics-gated tests auto-skip)
flutter test

# Diagnostics-gated tests (separate flag)
flutter test --run-skipped --tags=requires_diagnostics_define --dart-define=DIAGNOSTICS_ENABLED=true

# Static analysis (MUST PASS)
flutter analyze
```

Never hide failing tests. If tests fail, investigate and fix.

---

## Key Files

| Purpose | File |
|---------|------|
| Translation allowlist | [lib/core/bible_translation_registry.dart](lib/core/bible_translation_registry.dart) |
| PAL voice registry | [lib/core/pal_voice_registry.dart](lib/core/pal_voice_registry.dart) |
| Scripture anchor registry | [assets/stories/scripture_anchor_registry.json](assets/stories/scripture_anchor_registry.json) |
| Parable model | [lib/models/parable.dart](lib/models/parable.dart) |
| User preferences | [lib/models/user_preferences.dart](lib/models/user_preferences.dart) |
| Story selection | [lib/services/parable_service.dart](lib/services/parable_service.dart) |
| Audio playback | [lib/services/audio_service.dart](lib/services/audio_service.dart) |
| Ambient sound types | [lib/core/ambient_sound_type.dart](lib/core/ambient_sound_type.dart) |
| Ambient audio playback | [lib/services/ambient_audio_service.dart](lib/services/ambient_audio_service.dart) |
| ElevenLabs TTS | [lib/services/eleven_labs_tts.dart](lib/services/eleven_labs_tts.dart) |
| Mood detection | [lib/services/mood_service.dart](lib/services/mood_service.dart) |
| App state | [lib/providers/app_state_notifier.dart](lib/providers/app_state_notifier.dart) |
| Structured logging | [lib/core/app_logger.dart](lib/core/app_logger.dart) |
| Scripture Sources panel | [lib/widgets/scripture_sources_panel.dart](lib/widgets/scripture_sources_panel.dart) |
| Scripture bottom sheet | [lib/widgets/scripture_bottom_sheet.dart](lib/widgets/scripture_bottom_sheet.dart) |
| Scripture text backfill | [scripts/backfill_scripture_text.py](scripts/backfill_scripture_text.py) |
| Bible reference parser | [scripts/lib/bible_ref_parser.py](scripts/lib/bible_ref_parser.py) |

### Scripture Sources Feature (SPEC Feature 12)

Each Traditional story carries its own `scripture_{id}_{lang}.txt` file containing the actual public-domain Bible passage (WEB). The app does NOT bundle the full Bible — only per-story extracts.

**Architecture:**
- `Parable.scriptureTextFilePath` — path to scripture text file (set in manifest.json)
- `ParableService.getScriptureText()` — lazy-loads scripture text on demand (same pattern as `getParableText()`)
- `ScriptureSourcesPanel` — collapsible panel on player screen, collapsed by default, shows reference + translation
- `ScriptureBottomSheet` — scrollable bottom sheet with actual verse text, opened via "Read Scripture" button after playback completes
- Hidden for Creative stories (no scripture reference)
- Scripture text files are generated by `backfill_scripture_text.py` using `bible_ref_parser.py` and reference Bible JSON in `server/data/`

---

## Environment

- `.env` file in project root with `ELEVENLABS_API_KEY=your_key_here`
- Never commit `.env` to git
- Never print, echo, log or otherwise expose the key value
- Main branch: `master`
- CI: GitHub Actions ([.github/workflows/flutter.yml](.github/workflows/flutter.yml))

### ElevenLabs operational notes

**API key scope (observed 2026-08-05).** The project key supports TTS generation
but lacks the `user_read` scope, so requests to `/v1/user` and
`/v1/user/subscription` return HTTP 401 with a `missing_permissions` detail.
**Do not diagnose the TTS key as invalid from those 401s** — generation works
fine. Credit balance cannot be read with this key; ask the owner rather than
inferring it.

**Pronunciation rules (documented and verified 2026-08-05).** ElevenLabs
documentation at that date stated that pronunciation-dictionary *phoneme* rules
(IPA/CMU) are supported for `eleven_flash_v2` and `eleven_v3` only, and that
other models silently skip phoneme tags and fall back to default pronunciation.
Phoneme support for `eleven_flash_v2_5` was **not** verified and must not be
assumed. The project's active model (`eleven_turbo_v2_5`) therefore requires
**alias**-based pronunciation handling. This is time-sensitive vendor behaviour
— re-check the official documentation before any architectural work that depends
on it.

**Rendering configuration is settled.** See
[docs/AUDIO_PIPELINE_FINDINGS_2026-08-05.md](docs/AUDIO_PIPELINE_FINDINGS_2026-08-05.md).
A controlled blind test selected the existing `eleven_turbo_v2_5` whole-story
pipeline over chunked/stitched and alternative-model arms. Do not reopen model
migration, paragraph chunking or Request Stitching without new listening
evidence.

### Audio preservation (NON-NEGOTIABLE)

Bible PAL follows a strict **never-delete-audio** rule.

- **Never delete audio** — production or experimental, including rejected takes,
  rerolls, narrator comparisons, model/pipeline tests, blind-test samples,
  pronunciation tests and superseded versions.
- **Never overwrite an audio file** unless the prior version has first been
  preserved under a unique archival filename or location **and** the owner has
  explicitly authorized the replacement.
- **Storage management means moving or archiving**, never erasing. Archive audio
  together with its supporting records: reports, answer keys, request
  information, timestamps, checksums, source-text references and listening
  decisions.
- Audio produced with paid credits remains part of the project's evidence and
  production history even when it is not the version shipped in the app.

---

## Opus 5 Execution Style

- Complete only the requested scope.
- Do not narrate routine tool calls or provide running commentary unless a material problem is discovered.
- Perform one consolidated final integrity check rather than repeatedly rechecking unchanged invariants.
- Report immediately when an unexpected finding materially affects correctness, safety, scope, or repository state.
- Do not widen the task, create subagents, add extra review cycles, or begin adjacent work unless explicitly authorized.
- Do not reinterpret a narrow correction as permission to improve unrelated files.
- Do not make speculative "while I am here" changes.
- Preserve all explicit safety gates, protected-file rules, Git restrictions, review gates, and audio restrictions.
- Task-specific instructions in the current prompt take precedence when they are more restrictive.
- When the requested operation is complete, provide one concise final report and stop.

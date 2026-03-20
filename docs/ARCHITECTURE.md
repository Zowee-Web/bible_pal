# Bible PAL — Architecture

**Last Updated:** 2026-03-09

This document describes the real system architecture derived from the repository. For product behavior, see [SPEC.md](SPEC.md). For invariants, see [INVARIANTS.md](INVARIANTS.md).

---

## Overview

Bible PAL is a Flutter app that delivers personalized audio parables. The user flow:

1. PAL greets the user with a time-aware check-in prompt
2. User responds (text, voice, or quick-tap mood buttons)
3. Mood is detected from the response
4. PAL plays a mood-specific micro-response
5. A parable is selected based on mood, length, and storytelling mode
6. Pre-generated audio plays with scripture references displayed

Stories and audio are pre-generated offline via a Node.js/bash server pipeline, then bundled as assets.

---

## Layers

```
┌─────────────────────────────────────────┐
│  Presentation (lib/features/*)          │
│  Screens organized by feature module    │
├─────────────────────────────────────────┤
│  State (lib/providers/)                 │
│  Riverpod notifiers + service providers │
├─────────────────────────────────────────┤
│  Services (lib/services/)               │
│  Business logic, audio, TTS, mood, etc. │
├─────────────────────────────────────────┤
│  Core (lib/core/)                       │
│  Registries, logging, config, safety    │
├─────────────────────────────────────────┤
│  Models (lib/models/)                   │
│  Immutable data classes with JSON serde │
└─────────────────────────────────────────┘
```

**State management:** Riverpod (not Provider). Providers are defined in `lib/providers/service_providers.dart`. Key notifiers:
- `AppStateNotifier` — user prefs, favorites, history, daily bread
- `ParablePlayerNotifier` — playback state, current parable, audio position

---

## Feature Modules (lib/features/)

| Module | Purpose |
|--------|---------|
| `onboarding/` | First-launch Bible translation selection |
| `main_menu/` | Home screen, Daily Bread, PAL's Parables entry |
| `pals_parables/` | Mood check-in, micro-response, story playback |
| `favorites/` | Saved parables |
| `history/` | Recently played parables (20-item FIFO) |
| `settings/` | User preferences (mode, translation, voice, etc.) |
| `diagnostics/` | Debug breadcrumb viewer (opt-in via compile flag) |
| `my_pals/` | PAL voice selection |
| `consent/` | User consent flows |
| `whisper/` | Legacy prototype screen |

---

## Key Services (lib/services/)

| Service | Responsibility |
|---------|---------------|
| `parable_service.dart` | Story selection, non-repeat logic, pool filtering |
| `audio_service.dart` | just_audio playback (play/pause/seek/stop) |
| `mood_service.dart` | Text-based mood detection (keyword analysis) |
| `pal_prompt_service.dart` | Time-aware check-in prompt selection with non-repeat |
| `pal_audio_service.dart` | PAL voice audio playback (prompts, micro-responses) |
| `greeting_audio_service.dart` | Greeting audio coordination |
| `daily_bread_service.dart` | Daily verse selection and rotation |
| `eleven_labs_tts.dart` | ElevenLabs v3 API client for audio generation |
| `storage_service.dart` | SQLite + SharedPreferences persistence |
| `reflection_service.dart` | Post-story reflection content and playback |
| `stt_service.dart` | Speech-to-text for voice mood input |
| `name_audio_service.dart` | Personalized name audio (TTS name prefix splicing) |
| `kid_safety_service.dart` | Kid-mode content filtering |
| `share_service.dart` | Story sharing |

---

## Core Registries & Safety (lib/core/)

| File | Purpose |
|------|---------|
| `bible_translation_registry.dart` | **Translation allowlist — the #1 invariant** |
| `pal_voice_registry.dart` | PAL voice definitions (Grace, Shepherd, Hope, Stillwater) |
| `scripture_anchor_registry.json` (in assets/stories/) | Scripture anchor registry for Traditional mode (ADR-022) |
| `story_length_bucket.dart` | Short/Full/Long bucket system (strict word-count ranges, see SPEC.md) |
| `app_logger.dart` | Structured JSON logging with breadcrumb ring buffer |
| `analytics_events.dart` | Privacy-safe telemetry event builders |
| `feature_flags.dart` | Runtime feature flags |
| `diagnostics_config.dart` | Compile-time diagnostics toggle |

---

## Story Generation Pipeline (server/)

Stories are generated offline, not at runtime. The pipeline:

1. **Batch generation scripts** (`generate_v2_batch.sh`, `generate_batch_parables.sh`) call Ollama/Gemma to produce story text
2. **Kid safety harness** (`kid_bedtime_harness.sh` + `kid_bedtime_validator.sh`) validates kid-mode stories against forbidden vocabulary
3. **Audio generation** (`generate_audio_from_text.sh`, `generate_reflection_audio.sh`) calls ElevenLabs to produce MP3s
4. **Quality gates** (`quality_gates.sh`, `validate_manifest.sh`) verify word counts, metadata, and manifest integrity
5. **Nightly automation** (`nightly_generate.sh`) automates batch story and audio generation on a daily schedule
6. **Output** lands in `assets/stories/` as text + metadata, with audio as MP3 files

Key server files:
- `server/prompts/` — Generation prompt templates
- `server/contracts/` — Story mode contracts (Traditional/Creative)
- `server/kid_bedtime_forbidden.txt` — Forbidden vocabulary for kid mode
- `server/voices.json` — ElevenLabs voice configuration
- `server/model_router/` — Universal Model Router (task-driven AI model selection)

### Model Router (server/model_router/)

A config-driven Python module that resolves task types to AI models and executes generation through provider abstraction. Generation scripts call the router CLI for model selection, or use the FastAPI endpoint for resolution + execution in a single call. Traditional stories are locked to gpt-4.1 per ADR-014 and ADR-016.

- **Registry**: `model_registry.json` defines models, task types, and fallback chains
- **CLI**: `python3 -m server.model_router.cli resolve <task>` returns JSON with selected model
- **API**: FastAPI server on port 8181 with auth, structured envelopes, and POST /generate
- **Providers**: `providers.py` — thin transport adapters for Ollama and OpenAI (stdlib urllib only)
- **Telemetry**: Privacy-safe structured logging (no prompt/content logging)
- **Integration**: `generate_v2_batch.sh` tries the router first, falls back to hardcoded logic if unavailable

API endpoints:
- `GET /health` — System health + Ollama connectivity
- `GET /models` — Registered models with availability
- `GET /tasks` — Defined task types
- `GET /resolve/{task}` — Resolve task to model (resolution only)
- `POST /generate` — Resolve task + call provider + return generated text

---

## Two Story Modes (LOCKED Contract)

**Traditional** (default): Faithful retellings of real Bible stories. Requires `bibleSourceRef` and `bibleStoryKey`. Multiple stories per mood; identity is the scripture anchor (`scriptureAnchorId`), not the mood. See ADR-022.

**Creative**: Original stories with biblical themes. `bibleSourceRef` must be absent. MoDC (Model of Digital Companionship) rules apply — non-directive, non-prescriptive.

These modes must never blur. See SPEC.md "Story Mode Contracts v2" for full rules.

---

## Story Length Buckets

Story lengths use a strict Short / Full / Long bucket system enforced by `lib/core/story_length_bucket.dart`:
- **Short**: 250–600 words
- **Full**: 601–1200 words
- **Long**: 1201–2000 words

Word ranges are locked in SPEC.md. The UI shows descriptive labels only (no minute estimates).

---

## Testing Strategy

- **Compliance tests** (`test/core/`) — Bible translation allowlist enforcement, repo-wide scan for banned translations
- **Model tests** (`test/models/`) — JSON serialization, validation
- **Service tests** (`test/services/`) — Business logic, mood detection, parable selection
- **Feature tests** (`test/features/`) — Screen-level widget tests
- **Safety tests** (`test/safety/`, `test/kid_bedtime_safe/`) — Kid mode content validation
- **Provider tests** (`test/providers/`) — State management logic

Diagnostics-gated tests require `--dart-define=DIAGNOSTICS_ENABLED=true` and auto-skip otherwise.

---

## Important Boundaries

1. **Translation compliance is enforced at multiple layers** — registry, runtime guards, tests, CI. Do not bypass any layer.
2. **Story modes are mutually exclusive** — Traditional and Creative have different validation rules and must never cross-serve.
3. **PAL voices are separate from narrator voices** — PAL voices (check-in, micro-response) are distinct from story narration voices.
4. **Stories are pre-generated, not runtime** — The app plays bundled audio; it does not call LLMs or TTS at runtime (except for name audio).
5. **Privacy boundary** — No user text, PII, or mood input is ever logged or persisted beyond the current session.

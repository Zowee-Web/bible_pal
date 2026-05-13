# Creative Mode Retirement — 2026-05-13

> **Status:** Stage 1 prep complete. **Archive NOT YET executed.** Awaiting T9 SSD connection (Adam, evening of 2026-05-13).

## Purpose

Bible PAL is consolidating around a Traditional-only product identity:

> "PAL understands your life and responds with real Scripture-grounded Traditional Bible stories."

Creative mode (AI-generated parables, IDs 501–520 and 2000–2079) is being retired from the working codebase. Creative assets are too valuable to delete outright — they represent paid ElevenLabs audio generation and months of curated themes — so they will be preserved via two redundant channels:

1. **Cold archive** on Adam's T9 SSD at the destination below.
2. **Git tag** at the last commit where Creative is live in the working tree.

After Stage 2 completes, the working tree will be Traditional-only and Creative cannot creep back into routing, UI, mood matching, or future Situation Tags work.

## Planned archive destination

```
/Volumes/T9-Archive/bible_pal_archives/creative_retirement_2026_05_13/
```

## Planned git tag

```
pre-creative-retirement-2026-05-13
```

The tag will be applied to the last commit on `fix/creative-retirement-stage1-prep` (or its successor branch) immediately BEFORE any `git rm -r` of Creative paths.

## Inventory summary (from exploration pass, 2026-05-13)

### Primary asset tree
- `assets/stories/creative/` — **100 story directories**, **804 files**, **~508 MB**
  - Legacy range: 501–520 (20 dirs)
  - Modern range: 2000–2079 (80 dirs)
  - Per-story: 4 audio files (.mp3), 3 story texts, 1 reflection text, 1 meta JSON, occasional .title marker

### Creative voice samples
- `assets/pal/audio_archive_grace_2026_04_23/` — 24 `CREATIVE_<MOOD>_NN.mp3` files
- `assets/pal/audio_archive_ruth_v1_2026_04_25/` — 24 files (same pattern)

### Creative-specific JSON assets
- `assets/pal/creative_opening_lines.json` (3.1 KB, 46 lines)

### Manifest entries (525 total Creative variants across 4 files)
- `assets/stories/manifest.json` — 173 entries
- `assets/stories/manifest_opus.json` — 203 entries
- `assets/stories/unused_pal_stories.json` — 44 entries
- `assets/stories/manifest_full_backup.json` — 105 entries (decision deferred: strip vs preserve)

### Root-level JSON registries
- `used_creative_themes.json` — Creative theme registry
- `used_creative_names.json` — Character name registry

### Server-side prompt + data
- `server/prompts/creative_prompt.template.txt` (7.8 KB)
- `server/data/creative_place_names_avoid.txt` (54 B)

### Creative-only scripts
- `scripts/story_factory/generate_creative_story.py`
- `scripts/story_factory/batch_generate_creative.py`
- `scripts/story_factory/test_creative_story_factory.py`
- `server/story_dna.sh`
- `server/test_story_dna.sh`
- `server/bakeoff_claude_vs_gpt41.sh`

### Configs with Creative entries
- `configs/opus_batch_04.json` — 16 entries (lines 149–254)
- `scripts/play_bundle_pick.json` — `"creative"` key (line 19)
- `server/model_router/model_registry.json` — `creative_story` task definition (lines 11,15,25,55,100,106)
- `.claude/settings.local.json` — 2 hook entries (lines 67–68)

### pubspec.yaml declarations
- 80 Creative directory entries (lines 401–480)
- 1 Creative opening lines entry (line 490)

## Complete top-level paths slated for archive

```
assets/stories/creative/
assets/pal/creative_opening_lines.json
assets/pal/audio_archive_grace_2026_04_23/   (Creative-named files only — verify)
assets/pal/audio_archive_ruth_v1_2026_04_25/ (Creative-named files only — verify)
used_creative_themes.json
used_creative_names.json
server/prompts/creative_prompt.template.txt
server/data/creative_place_names_avoid.txt
scripts/story_factory/generate_creative_story.py
scripts/story_factory/batch_generate_creative.py
scripts/story_factory/test_creative_story_factory.py
server/story_dna.sh
server/test_story_dna.sh
server/bakeoff_claude_vs_gpt41.sh
```

Plus extracted Creative entries from manifests/configs (written as separate `*.creative_entries.json` excerpts into the archive root).

## Restoration instructions

### Option A — restore from git tag (preferred for code restoration)

```bash
# View what existed pre-retirement
git checkout pre-creative-retirement-2026-05-13

# Restore the full Creative tree to a working branch
git checkout -b restore/creative-from-tag pre-creative-retirement-2026-05-13
```

This restores every file as it existed at retirement time, including code branches, manifests, pubspec entries, and assets.

### Option B — restore from T9 archive (use if git history is unavailable)

```bash
# Mount T9 first
DEST="/Volumes/T9-Archive/bible_pal_archives/creative_retirement_2026_05_13"
cd /Users/adamlipps/bible_pal

rsync -av "$DEST/assets/stories/creative/" assets/stories/creative/
rsync -av "$DEST/assets/pal/creative_opening_lines.json" assets/pal/
rsync -av "$DEST/server/prompts/" server/prompts/
# ...etc per ARCHIVE_MANIFEST.json contents
```

Then reapply manifest excerpts back into the active manifest files (see `manifest_excerpts/` subtree in archive).

### Option C — partial restore (specific stories only)

The archive preserves per-story directories. To restore just one:

```bash
cp -r "$DEST/assets/stories/creative/2057" assets/stories/creative/2057
# Then manually re-add manifest entry from manifest_excerpts/manifest.creative_entries.json
```

## What is NOT being archived

- **R2 cloud storage** — Per Adam's explicit instruction, R2 is untouched in this retirement. R2 still serves `creative/NNNN/audio_*.mp3` paths if anything queries them. Cleanup of R2 is a separate decision deferred indefinitely.
- **`assets/stories/manifest_full_backup.json`** — Decision deferred to Stage 2: strip Creative entries in place, OR rename and move whole file to T9 as historical backup.

## Backward compatibility (Stage 2 will implement)

- Legacy `storytellingMode: 'creative'` values in SharedPreferences will be coerced to `'traditional'` on load.
- Favorites/history entries pointing at orphaned Creative story IDs will be skipped silently and logged.
- No DB migration required (no schema distinguishes mode).

## Reactivation

Reactivating Creative mode at a future date requires:

1. SPEC update with explicit user approval.
2. Restoration from T9 archive OR git tag.
3. New tests covering the reactivated lane.
4. Re-introduction of Creative validation, manifest entries, pubspec declarations, and UI toggle.

## Document audit trail

- **Inventory pass:** completed 2026-05-13 via 3 parallel Explore agents (assets+manifests, code+UI, scripts+docs+server).
- **Stage 1 prep branch:** `fix/creative-retirement-stage1-prep`.
- **Stage 2 runbook:** [CREATIVE_RETIREMENT_EXECUTION_CHECKLIST.md](CREATIVE_RETIREMENT_EXECUTION_CHECKLIST.md).
- **Pre-state git snapshot:** [CREATIVE_RETIREMENT_GIT_SAFETY_REPORT.md](CREATIVE_RETIREMENT_GIT_SAFETY_REPORT.md).

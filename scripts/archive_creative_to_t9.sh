#!/usr/bin/env bash
#
# archive_creative_to_t9.sh
# ---------------------------------------------------------------------------
# Archive every Creative-mode asset, script, prompt, and config excerpt from
# the Bible PAL working tree to the T9 SSD at the canonical retirement
# destination. This script does NOT modify or delete anything in the working
# tree — it only COPIES.
#
# Companion scripts:
#   - verify_creative_archive.sh : checksum + count verification (run next)
#   - remove_creative_after_verification.sh : the destructive step (run last)
#
# Stage 2 only. Created in Stage 1 prep, NOT executed in Stage 1.
#
# Usage:
#   bash scripts/archive_creative_to_t9.sh             # real run
#   DRY_RUN=1 bash scripts/archive_creative_to_t9.sh   # show what would happen
#
# Exit codes:
#   0  - archive complete, ARCHIVE_COMPLETE.txt written
#   1  - precondition failed (T9 not mounted, destination exists, etc.)
#   2  - rsync or shasum error during copy
#
# Safety:
#   - refuses to run if /Volumes/T9-Archive is not mounted
#   - refuses to run if destination directory already exists
#   - writes a sha256 manifest of source files BEFORE copying
#   - uses rsync --checksum (slower, but verifies content not mtime/size)
#
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Canonical retirement archive destination on the T9 SSD.
T9_ROOT="/Volumes/T9-Archive"
ARCHIVE_DATE="2026_05_13"
DEST_ROOT="${T9_ROOT}/bible_pal_archives/creative_retirement_${ARCHIVE_DATE}"

# Pre-archive sha256 manifest of source files (consumed by verify script).
PRE_MANIFEST="/tmp/pre_archive_creative_tree.sha256"

# Project root (this script lives in scripts/, so root is one level up).
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Dry-run toggle.
DRY_RUN="${DRY_RUN:-0}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

log()  { printf '[archive] %s\n' "$*"; }
warn() { printf '[archive][WARN] %s\n' "$*" >&2; }
die()  { printf '[archive][FATAL] %s\n' "$*" >&2; exit 1; }

run() {
  # Echo + execute, or just echo if DRY_RUN.
  if [ "$DRY_RUN" = "1" ]; then
    printf '[archive][DRY-RUN] %s\n' "$*"
  else
    eval "$@"
  fi
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

log "Project root: $PROJECT_ROOT"
log "T9 destination: $DEST_ROOT"
log "Dry-run mode: $DRY_RUN"

# Must be inside the bible_pal repo.
cd "$PROJECT_ROOT"
[ -f "pubspec.yaml" ] || die "pubspec.yaml not found — not in bible_pal repo?"
grep -q "name: bible_pal" pubspec.yaml || die "pubspec.yaml does not look like bible_pal"

# T9 must be mounted.
if [ ! -d "$T9_ROOT" ]; then
  die "T9 SSD not mounted at $T9_ROOT — connect the drive and retry."
fi

# Destination must NOT already exist (prevent accidental overwrite).
if [ -d "$DEST_ROOT" ]; then
  die "Destination already exists: $DEST_ROOT
Refusing to overwrite. Either resume an in-progress archive manually or pick a new date suffix."
fi

# Required source paths must exist.
required_paths=(
  "assets/stories/creative"
  "assets/pal/creative_opening_lines.json"
  "server/prompts/creative_prompt.template.txt"
  "server/data/creative_place_names_avoid.txt"
  "scripts/story_factory/generate_creative_story.py"
  "scripts/story_factory/batch_generate_creative.py"
  "scripts/story_factory/test_creative_story_factory.py"
  "server/story_dna.sh"
  "server/test_story_dna.sh"
  "server/bakeoff_claude_vs_gpt41.sh"
  "used_creative_themes.json"
  "used_creative_names.json"
)

missing=()
for p in "${required_paths[@]}"; do
  [ -e "$p" ] || missing+=("$p")
done

if [ "${#missing[@]}" -gt 0 ]; then
  warn "Some Creative paths are missing from working tree:"
  for p in "${missing[@]}"; do warn "  - $p"; done
  warn "Continuing anyway — these may have been removed in a prior partial retirement."
fi

# ---------------------------------------------------------------------------
# Phase 1 — build pre-archive sha256 manifest of source files
# ---------------------------------------------------------------------------

log "Phase 1: building pre-archive sha256 manifest at $PRE_MANIFEST"

if [ "$DRY_RUN" = "1" ]; then
  printf '[archive][DRY-RUN] would write sha256 manifest of every Creative source file to %s\n' "$PRE_MANIFEST"
else
  : > "$PRE_MANIFEST"
  # Each source-path block contributes to the manifest.
  # Paths are recorded relative to project root for portability.

  # The big tree
  if [ -d "assets/stories/creative" ]; then
    find assets/stories/creative -type f ! -name ".DS_Store" | sort | xargs shasum -a 256 >> "$PRE_MANIFEST"
  fi

  # Singletons + small archives
  for p in \
    "assets/pal/creative_opening_lines.json" \
    "server/prompts/creative_prompt.template.txt" \
    "server/data/creative_place_names_avoid.txt" \
    "scripts/story_factory/generate_creative_story.py" \
    "scripts/story_factory/batch_generate_creative.py" \
    "scripts/story_factory/test_creative_story_factory.py" \
    "server/story_dna.sh" \
    "server/test_story_dna.sh" \
    "server/bakeoff_claude_vs_gpt41.sh" \
    "used_creative_themes.json" \
    "used_creative_names.json"; do
    [ -f "$p" ] && shasum -a 256 "$p" >> "$PRE_MANIFEST"
  done

  # Voice-sample archives — include only Creative-named files (defensive)
  for archive in \
    "assets/pal/audio_archive_grace_2026_04_23" \
    "assets/pal/audio_archive_ruth_v1_2026_04_25"; do
    if [ -d "$archive" ]; then
      find "$archive" -type f -name "CREATIVE_*.mp3" | sort | xargs -I{} shasum -a 256 "{}" >> "$PRE_MANIFEST"
    fi
  done

  file_count=$(wc -l < "$PRE_MANIFEST" | tr -d ' ')
  log "  Manifest written: $file_count files"
fi

# ---------------------------------------------------------------------------
# Phase 2 — create destination scaffold
# ---------------------------------------------------------------------------

log "Phase 2: creating destination scaffold under $DEST_ROOT"

scaffold_dirs=(
  "$DEST_ROOT"
  "$DEST_ROOT/assets/stories"
  "$DEST_ROOT/assets/pal"
  "$DEST_ROOT/server/prompts"
  "$DEST_ROOT/server/data"
  "$DEST_ROOT/scripts/story_factory"
  "$DEST_ROOT/manifest_excerpts"
  "$DEST_ROOT/docs_snapshot"
)

for d in "${scaffold_dirs[@]}"; do
  run "mkdir -p '$d'"
done

# ---------------------------------------------------------------------------
# Phase 3 — rsync the big tree and singletons
# ---------------------------------------------------------------------------

log "Phase 3: rsync Creative content"

# The 508 MB / 804-file tree.
if [ -d "assets/stories/creative" ]; then
  run "rsync -av --checksum --progress assets/stories/creative/ '$DEST_ROOT/assets/stories/creative/'"
fi

# Creative PAL opening lines.
[ -f "assets/pal/creative_opening_lines.json" ] && \
  run "rsync -av --checksum 'assets/pal/creative_opening_lines.json' '$DEST_ROOT/assets/pal/'"

# Creative voice samples (Creative-named files only).
for archive in \
  "assets/pal/audio_archive_grace_2026_04_23" \
  "assets/pal/audio_archive_ruth_v1_2026_04_25"; do
  if [ -d "$archive" ]; then
    archive_name="$(basename "$archive")"
    run "mkdir -p '$DEST_ROOT/assets/pal/$archive_name'"
    # Use --include/--exclude to grab only Creative files.
    run "rsync -av --checksum --include='CREATIVE_*.mp3' --exclude='*' '$archive/' '$DEST_ROOT/assets/pal/$archive_name/'"
  fi
done

# Server prompts + data.
[ -f "server/prompts/creative_prompt.template.txt" ] && \
  run "rsync -av --checksum 'server/prompts/creative_prompt.template.txt' '$DEST_ROOT/server/prompts/'"
[ -f "server/data/creative_place_names_avoid.txt" ] && \
  run "rsync -av --checksum 'server/data/creative_place_names_avoid.txt' '$DEST_ROOT/server/data/'"

# Creative-only scripts.
for p in \
  "scripts/story_factory/generate_creative_story.py" \
  "scripts/story_factory/batch_generate_creative.py" \
  "scripts/story_factory/test_creative_story_factory.py"; do
  [ -f "$p" ] && run "rsync -av --checksum '$p' '$DEST_ROOT/scripts/story_factory/'"
done

for p in \
  "server/story_dna.sh" \
  "server/test_story_dna.sh" \
  "server/bakeoff_claude_vs_gpt41.sh"; do
  [ -f "$p" ] && run "rsync -av --checksum '$p' '$DEST_ROOT/server/'"
done

# Root-level Creative registries.
for p in "used_creative_themes.json" "used_creative_names.json"; do
  [ -f "$p" ] && run "rsync -av --checksum '$p' '$DEST_ROOT/'"
done

# ---------------------------------------------------------------------------
# Phase 4 — extract Creative entries from manifests/configs
# ---------------------------------------------------------------------------

log "Phase 4: extracting Creative entries from manifests/configs"

extract_creative_entries() {
  # Usage: extract_creative_entries <source_json> <dest_json>
  local src="$1"
  local dst="$2"
  if [ "$DRY_RUN" = "1" ]; then
    printf "[archive][DRY-RUN] would jq-extract Creative entries from %s -> %s\n" "$src" "$dst"
  else
    if [ -f "$src" ]; then
      # Filter to entries where storytellingMode == "creative".
      jq '[.[] | select(.storytellingMode == "creative")]' "$src" > "$dst" 2>/dev/null \
        || jq '.[] | select(.mode == "creative")' "$src" > "$dst" 2>/dev/null \
        || cp "$src" "$dst"
      log "  $(basename "$src") -> $(basename "$dst")"
    fi
  fi
}

extract_creative_entries "assets/stories/manifest.json"             "$DEST_ROOT/manifest_excerpts/manifest.creative_entries.json"
extract_creative_entries "assets/stories/manifest_opus.json"        "$DEST_ROOT/manifest_excerpts/manifest_opus.creative_entries.json"
extract_creative_entries "assets/stories/unused_pal_stories.json"   "$DEST_ROOT/manifest_excerpts/unused_pal_stories.creative_entries.json"
extract_creative_entries "assets/stories/manifest_full_backup.json" "$DEST_ROOT/manifest_excerpts/manifest_full_backup.creative_entries.json"

# Config Creative entries (different schema).
if [ -f "configs/opus_batch_04.json" ]; then
  if [ "$DRY_RUN" = "1" ]; then
    printf "[archive][DRY-RUN] would extract Creative entries from configs/opus_batch_04.json\n"
  else
    jq '[.[] | select(.mode == "creative")]' configs/opus_batch_04.json \
      > "$DEST_ROOT/manifest_excerpts/opus_batch_04.creative_entries.json" 2>/dev/null \
      || cp configs/opus_batch_04.json "$DEST_ROOT/manifest_excerpts/opus_batch_04.snapshot.json"
  fi
fi

# ---------------------------------------------------------------------------
# Phase 5 — snapshot SPEC + INVARIANTS + other docs (text only, small)
# ---------------------------------------------------------------------------

log "Phase 5: snapshotting SPEC / INVARIANTS / DECISIONS / STORY_FACTORY / ARCHITECTURE"

for doc in \
  "docs/SPEC.md" \
  "docs/INVARIANTS.md" \
  "docs/STORY_FACTORY.md" \
  "docs/DECISIONS.md" \
  "docs/ARCHITECTURE.md" \
  "docs/AUDIO_MIGRATION_DEBT.md" \
  "docs/FEATURES_COMPLETE.md"; do
  [ -f "$doc" ] && run "rsync -av --checksum '$doc' '$DEST_ROOT/docs_snapshot/'"
done

# ---------------------------------------------------------------------------
# Phase 6 — write metadata + completion marker
# ---------------------------------------------------------------------------

log "Phase 6: writing archive metadata"

if [ "$DRY_RUN" = "1" ]; then
  printf '[archive][DRY-RUN] would write ARCHIVE_MANIFEST.json + git_state.txt + ARCHIVE_COMPLETE.txt at %s\n' "$DEST_ROOT"
else
  # Metadata JSON: counts + bytes + sha manifest path.
  tree_count=$(find "$DEST_ROOT/assets/stories/creative" -type f 2>/dev/null | wc -l | tr -d ' ')
  tree_bytes=$(du -sk "$DEST_ROOT/assets/stories/creative" 2>/dev/null | cut -f1)
  printf '{\n  "archive_date": "%s",\n  "creative_tree_file_count": %s,\n  "creative_tree_kilobytes": %s,\n  "pre_manifest_path": "%s"\n}\n' \
    "$ARCHIVE_DATE" "$tree_count" "${tree_bytes:-0}" "$PRE_MANIFEST" \
    > "$DEST_ROOT/ARCHIVE_MANIFEST.json"

  # Git state at archive time.
  {
    echo "git rev-parse HEAD: $(git rev-parse HEAD)"
    echo "git branch:         $(git rev-parse --abbrev-ref HEAD)"
    echo "archive date:       $ARCHIVE_DATE"
    echo "archive host:       $(hostname)"
  } > "$DEST_ROOT/git_state.txt"

  # README inside the archive.
  cat > "$DEST_ROOT/README.md" <<EOF
# Bible PAL Creative Retirement Archive — ${ARCHIVE_DATE}

This directory is the cold archive of all Creative-mode assets and excerpts
retired from the Bible PAL working tree on ${ARCHIVE_DATE}.

## To restore
See docs/archive/CREATIVE_RETIREMENT_2026_05_13.md in the bible_pal repo,
or check out git tag pre-creative-retirement-${ARCHIVE_DATE}.

## What's here
- assets/stories/creative/   — full 100-dir Creative story tree
- assets/pal/                — Creative opening lines + voice samples
- server/                    — Creative prompts, data, story DNA scripts
- scripts/story_factory/     — Creative-only generation scripts
- manifest_excerpts/         — Creative entries extracted from manifests
- docs_snapshot/             — SPEC/INVARIANTS/DECISIONS at retirement time
- ARCHIVE_MANIFEST.json      — counts + sizes
- git_state.txt              — git HEAD/branch at archive time

## Pre-archive sha256 manifest
${PRE_MANIFEST} on the source machine. The verify script diffs the
destination tree against this manifest before the deletion script runs.
EOF

  # Completion marker (verify + remove scripts gate on this file).
  printf 'archive_complete=true\narchive_date=%s\n' "$ARCHIVE_DATE" \
    > "$DEST_ROOT/ARCHIVE_COMPLETE.txt"
fi

log "Done. ARCHIVE_COMPLETE.txt written. Next: run scripts/verify_creative_archive.sh"

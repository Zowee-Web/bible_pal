#!/usr/bin/env bash
#
# remove_creative_after_verification.sh
# ---------------------------------------------------------------------------
# DESTRUCTIVE — removes Creative-mode files from the Bible PAL working tree
# using `git rm -r`. This script is the third and final step of the Stage 2
# retirement pipeline and refuses to run unless every earlier safety gate has
# passed.
#
# Order:
#   1. scripts/archive_creative_to_t9.sh         (creates T9 archive)
#   2. scripts/verify_creative_archive.sh        (writes PASS marker)
#   3. git tag pre-creative-retirement-...       (recovery anchor)
#   4. THIS SCRIPT                               (the actual removal)
#
# Stage 2 only. Created in Stage 1 prep, NOT executed in Stage 1.
#
# Usage:
#   bash scripts/remove_creative_after_verification.sh                 # dry-run by default
#   CONFIRM_DELETE=YES_I_HAVE_T9_BACKUP bash scripts/remove_creative_after_verification.sh
#
# Exit codes:
#   0  - removal complete (or dry-run printed plan)
#   1  - precondition failed (PASS missing, wrong branch, dirty tree, tag missing)
#   2  - one or more git rm operations failed
#
# Safety:
#   - default behavior is dry-run; needs CONFIRM_DELETE=YES_I_HAVE_T9_BACKUP
#   - refuses unless /tmp/verify_creative_archive.PASS exists
#   - refuses unless current branch starts with fix/creative-retirement-
#   - refuses unless working tree is clean
#   - refuses unless git tag pre-creative-retirement-2026-05-13 exists
#   - lists every path it WILL remove BEFORE doing anything
#   - does NOT touch R2
#   - does NOT touch assets/stories/manifest_full_backup.json
#
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

PASS_MARKER="/tmp/verify_creative_archive.PASS"
EXPECTED_TAG="pre-creative-retirement-2026-05-13"
BRANCH_PATTERN="^fix/creative-retirement-"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIRM_DELETE="${CONFIRM_DELETE:-}"
DRY_RUN_DEFAULT="${DRY_RUN:-}"

log()  { printf '[remove] %s\n' "$*"; }
warn() { printf '[remove][WARN] %s\n' "$*" >&2; }
die()  { printf '[remove][FATAL] %s\n' "$*" >&2; exit 1; }

cd "$PROJECT_ROOT"

# ---------------------------------------------------------------------------
# Determine effective dry-run
# ---------------------------------------------------------------------------

# DEFAULT: dry-run. Only the explicit CONFIRM_DELETE token enables real removal.
if [ "$CONFIRM_DELETE" = "YES_I_HAVE_T9_BACKUP" ]; then
  EFFECTIVE_DRY_RUN=0
  log "CONFIRM_DELETE=YES_I_HAVE_T9_BACKUP — destructive mode enabled."
else
  EFFECTIVE_DRY_RUN=1
  log "Dry-run mode (default). Set CONFIRM_DELETE=YES_I_HAVE_T9_BACKUP to actually remove."
fi

# Explicit DRY_RUN=1 also forces dry-run regardless.
if [ "$DRY_RUN_DEFAULT" = "1" ]; then
  EFFECTIVE_DRY_RUN=1
  log "DRY_RUN=1 override — forcing dry-run."
fi

run() {
  if [ "$EFFECTIVE_DRY_RUN" = "1" ]; then
    printf '[remove][DRY-RUN] %s\n' "$*"
  else
    eval "$@"
  fi
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

# 1. PASS marker from verify script.
[ -f "$PASS_MARKER" ] || die "Missing $PASS_MARKER — run scripts/verify_creative_archive.sh first.
This is the safety gate: the archive must be verified byte-for-byte before deletion."

# 2. Branch check.
current_branch=$(git rev-parse --abbrev-ref HEAD)
log "Current branch: $current_branch"
if ! [[ "$current_branch" =~ $BRANCH_PATTERN ]]; then
  die "Refusing to run on branch '$current_branch'.
Expected a branch matching $BRANCH_PATTERN (e.g., fix/creative-retirement-stage2)."
fi

# 3. Working tree clean.
if [ -n "$(git status --porcelain)" ]; then
  warn "Working tree is not clean:"
  git status --short >&2
  die "Commit or stash your changes before running this script.
Per Adam's preference: NEVER stash PAL work — commit it instead."
fi

# 4. Recovery tag must exist (created at Step 4 of the runbook).
if ! git tag -l "$EXPECTED_TAG" | grep -qx "$EXPECTED_TAG"; then
  die "Recovery tag '$EXPECTED_TAG' does not exist.
Create it FIRST so retirement is recoverable:
  git tag -a $EXPECTED_TAG -m \"Last commit before Creative retirement\""
fi
log "Recovery tag present: $EXPECTED_TAG"

# 5. R2 untouched — explicit reminder.
log "Reminder: this script does NOT touch R2 cloud storage."

# ---------------------------------------------------------------------------
# Build the removal plan
# ---------------------------------------------------------------------------

# Each entry is a path that will be removed via `git rm -r`.
# Comments inline justify why each is safe to remove (archived + git-tagged).

PATHS_TO_REMOVE=(
  # The big tree — 100 dirs, 804 files, 508 MB. Archived to T9 + sha-verified.
  "assets/stories/creative"

  # Creative PAL opening lines JSON.
  "assets/pal/creative_opening_lines.json"

  # Creative-only Dart source + companion test.
  "lib/core/creative_opening_lines.dart"
  "test/core/creative_opening_lines_test.dart"

  # Creative-only story factory scripts.
  "scripts/story_factory/generate_creative_story.py"
  "scripts/story_factory/batch_generate_creative.py"
  "scripts/story_factory/test_creative_story_factory.py"

  # Creative-only server scripts.
  "server/story_dna.sh"
  "server/test_story_dna.sh"
  "server/bakeoff_claude_vs_gpt41.sh"

  # Creative-only server data.
  "server/prompts/creative_prompt.template.txt"
  "server/data/creative_place_names_avoid.txt"

  # Root-level Creative registries.
  "used_creative_themes.json"
  "used_creative_names.json"
)

# Voice-sample archives — only the CREATIVE_*.mp3 files inside, not the
# entire directories (those may contain other audio).
VOICE_SAMPLE_GLOBS=(
  "assets/pal/audio_archive_grace_2026_04_23/CREATIVE_*.mp3"
  "assets/pal/audio_archive_ruth_v1_2026_04_25/CREATIVE_*.mp3"
)

# Paths NOT removed by this script (handled in later Stage 2 steps):
#   - pubspec.yaml lines 401-480 + 490        (Edit tool, separate commit)
#   - assets/stories/manifest*.json entries   (jq filter, separate commit)
#   - configs/opus_batch_04.json entries      (jq filter, separate commit)
#   - scripts/play_bundle_pick.json           (Edit tool, separate commit)
#   - server/model_router/model_registry.json (Edit tool, separate commit)
#   - lib/safety/story_mode_validator.dart    (Edit tool, code simplification)
#   - lib/services/parable_service.dart       (Edit tool)
#   - lib/providers/app_state_notifier.dart   (Edit tool)
#   - lib/features/main_menu/main_menu_screen.dart  (Edit tool)
#   - lib/features/pals_parables/pals_parables_screen.dart (Edit tool)
#   - lib/models/user_preferences.dart        (Edit tool — coerce-on-load)
#   - lib/models/parable.dart                 (Edit tool)
#   - lib/core/analytics_events.dart          (Edit tool)
#   - test/* updates                          (separate test commit)
#   - docs/SPEC.md, docs/INVARIANTS.md, etc.  (separate docs commit)
#
# Also explicitly NOT touched:
#   - assets/stories/manifest_full_backup.json (deferred decision)
#   - server/legacy/ directory                 (deferred decision)
#   - R2 cloud storage                         (never touched)

# ---------------------------------------------------------------------------
# Show the plan (always — even in real mode, before doing anything)
# ---------------------------------------------------------------------------

log ""
log "=== REMOVAL PLAN ==="
log ""
log "Paths to remove via git rm -r:"
for p in "${PATHS_TO_REMOVE[@]}"; do
  if [ -e "$p" ]; then
    printf '  - %s  (exists)\n' "$p"
  else
    printf '  - %s  (already absent — will skip)\n' "$p"
  fi
done

log ""
log "Voice-sample globs to remove via git rm:"
for g in "${VOICE_SAMPLE_GLOBS[@]}"; do
  # Use compgen to check if the glob expands to anything.
  if compgen -G "$g" > /dev/null 2>&1; then
    matches=$(compgen -G "$g" | wc -l | tr -d ' ')
    printf '  - %s  (%s files match)\n' "$g" "$matches"
  else
    printf '  - %s  (no matches — will skip)\n' "$g"
  fi
done

log ""
log "Paths explicitly NOT removed by this script:"
log "  - assets/stories/manifest_full_backup.json (deferred)"
log "  - server/legacy/                            (deferred)"
log "  - R2 cloud storage                          (never)"
log "  - pubspec.yaml + manifests + code           (separate Stage 2 commits)"
log ""

# ---------------------------------------------------------------------------
# Execute (or describe if dry-run)
# ---------------------------------------------------------------------------

if [ "$EFFECTIVE_DRY_RUN" = "1" ]; then
  log "Dry-run complete. No files removed."
  log "To actually remove: CONFIRM_DELETE=YES_I_HAVE_T9_BACKUP $0"
  exit 0
fi

log "Executing removal..."

for p in "${PATHS_TO_REMOVE[@]}"; do
  if [ -e "$p" ]; then
    git rm -r --quiet "$p"
    log "  removed: $p"
  fi
done

for g in "${VOICE_SAMPLE_GLOBS[@]}"; do
  if compgen -G "$g" > /dev/null 2>&1; then
    # shellcheck disable=SC2086
    git rm --quiet $g
    log "  removed glob: $g"
  fi
done

log ""
log "Removal staged in git. Review with: git status"
log "Next commit must include:"
log "  - These removals"
log "  - pubspec.yaml + manifest + config edits"
log "  - Code simplification"
log "  - SPEC + INVARIANTS updates"
log "Commit as a single bundled change unless a piece looks risky in review."

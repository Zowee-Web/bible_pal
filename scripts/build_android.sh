#!/usr/bin/env bash
#
# build_android.sh — Defensive Android release-build wrapper.
#
# Bible PAL ships with all 445 stories bundled as Flutter assets, which makes
# the Android AAB ~1.2 GB — well over the Play Store 150 MB limit. This script
# trims the Android build inputs to a 32-story seed set, runs the build, and
# restores the repo to its original state on exit (success OR failure).
#
# Temporary mutations (these and ONLY these):
#   - pubspec.yaml — non-seed story directory entries removed
#   - assets/stories/{seed_dirs}/audio_*_story_full.mp3 → moved to backup
#   - assets/stories/{seed_dirs}/audio_*_story_long.mp3 → moved to backup
#
# All mutations are restored via a trap on EXIT, even if any command fails.
# Post-restore, `git diff --stat` and a pubspec.yaml checksum are verified.
#
# Reference: docs/SPEC.md Feature 27, Cloud Foundation v1
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_ROOT="$REPO_ROOT/.android_build_backup_${TIMESTAMP}"
PUBSPEC="$REPO_ROOT/pubspec.yaml"
PUBSPEC_BACKUP="$BACKUP_ROOT/pubspec.yaml"
PUBSPEC_CHECKSUM_FILE="$BACKUP_ROOT/pubspec.yaml.sha256"
MOVED_AUDIO_BACKUP="$BACKUP_ROOT/moved_audio"

# Seed story directories (32 stories) — must match the seed map in
# docs/SPEC.md Feature 27 / the Cloud Foundation v1 plan.
SEED_TRADITIONAL=(1000 1001 1002 1003 1004 1005 1006 1007 1008 1009 1010 1011 1012 1013 1014 1015)
SEED_CREATIVE=(2000 2001 2002 2003 2004 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015)

# Track files that the cleanup trap must restore. Populated as we mutate.
declare -a MOVED_FILES=()
PUBSPEC_MUTATED=0
RESTORE_FAILED=0

log()  { printf '\033[1;34m[build_android]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[build_android]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[build_android]\033[0m %s\n' "$*" >&2; exit 1; }

cleanup() {
  local exit_code=$?
  log "Restoring repo state…"

  # 1. Restore pubspec.yaml from backup.
  if [ "$PUBSPEC_MUTATED" -eq 1 ]; then
    if [ -f "$PUBSPEC_BACKUP" ]; then
      if ! cp "$PUBSPEC_BACKUP" "$PUBSPEC"; then
        warn "FAILED to restore pubspec.yaml from $PUBSPEC_BACKUP"
        RESTORE_FAILED=1
      fi
    else
      warn "pubspec.yaml backup missing at $PUBSPEC_BACKUP"
      RESTORE_FAILED=1
    fi
  fi

  # 2. Restore each moved audio file.
  if [ ${#MOVED_FILES[@]} -gt 0 ]; then
    for original in "${MOVED_FILES[@]}"; do
      local backup_path="$MOVED_AUDIO_BACKUP/${original#${REPO_ROOT}/}"
      if [ -f "$backup_path" ]; then
        mkdir -p "$(dirname "$original")"
        if ! mv "$backup_path" "$original"; then
          warn "FAILED to restore $original from $backup_path"
          RESTORE_FAILED=1
        fi
      else
        warn "Backup missing for $original (expected at $backup_path)"
        RESTORE_FAILED=1
      fi
    done
  fi

  # 3. Verify pubspec.yaml checksum matches the original.
  if [ "$PUBSPEC_MUTATED" -eq 1 ] && [ -f "$PUBSPEC_CHECKSUM_FILE" ]; then
    local expected actual
    expected="$(cut -d' ' -f1 < "$PUBSPEC_CHECKSUM_FILE")"
    actual="$(shasum -a 256 "$PUBSPEC" | cut -d' ' -f1)"
    if [ "$expected" != "$actual" ]; then
      warn "pubspec.yaml checksum mismatch after restore!"
      warn "  expected: $expected"
      warn "  actual:   $actual"
      RESTORE_FAILED=1
    else
      log "pubspec.yaml checksum verified."
    fi
  fi

  # 4. Verify git working tree is clean (only the files we touched).
  if command -v git >/dev/null 2>&1 && [ -d "$REPO_ROOT/.git" ]; then
    local diff_summary
    diff_summary="$(git -C "$REPO_ROOT" diff --stat -- pubspec.yaml assets/stories 2>/dev/null || true)"
    if [ -n "$diff_summary" ]; then
      warn "git diff --stat shows unexpected changes after restore:"
      printf '%s\n' "$diff_summary" >&2
      RESTORE_FAILED=1
    else
      log "git working tree clean for tracked files."
    fi
  fi

  if [ "$RESTORE_FAILED" -eq 1 ]; then
    warn "RESTORE INCOMPLETE — manual inspection required."
    warn "Backup root preserved at: $BACKUP_ROOT"
    # Force non-zero exit to surface the failure to CI/devs.
    exit 99
  fi

  # All clean — remove backup directory.
  if [ -d "$BACKUP_ROOT" ]; then
    rm -rf "$BACKUP_ROOT"
  fi

  exit "$exit_code"
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# 1. Sanity checks
# ---------------------------------------------------------------------------
[ -f "$PUBSPEC" ] || die "pubspec.yaml not found at $PUBSPEC"
command -v flutter >/dev/null 2>&1 || die "flutter command not found in PATH"

original_aab_dir="$REPO_ROOT/build/app/outputs/bundle/release"
[ -f "$original_aab_dir/app-release.aab" ] && \
  log "Pre-existing AAB at $original_aab_dir/app-release.aab will be overwritten."

# ---------------------------------------------------------------------------
# 2. Backup pubspec.yaml + checksum
# ---------------------------------------------------------------------------
mkdir -p "$BACKUP_ROOT"
cp "$PUBSPEC" "$PUBSPEC_BACKUP"
shasum -a 256 "$PUBSPEC" > "$PUBSPEC_CHECKSUM_FILE"
log "Backed up pubspec.yaml → $PUBSPEC_BACKUP"

# ---------------------------------------------------------------------------
# 3. Trim pubspec.yaml to seed story directories
# ---------------------------------------------------------------------------
# Build a regex matching only the SEED dirs we want to keep, then drop every
# other `assets/stories/(traditional|creative)/NNNN/` line.
seed_keep_regex='^[[:space:]]*-[[:space:]]+assets/stories/(traditional|creative)/(1000|1001|1002|1003|1004|1005|1006|1007|1008|1009|1010|1011|1012|1013|1014|1015|2000|2001|2002|2003|2004|2005|2006|2007|2008|2009|2010|2011|2012|2013|2014|2015)/[[:space:]]*$'
all_story_regex='^[[:space:]]*-[[:space:]]+assets/stories/(traditional|creative)/[0-9]+/[[:space:]]*$'

awk -v keep="$seed_keep_regex" -v all="$all_story_regex" '
  {
    if ($0 ~ all && $0 !~ keep) {
      next  # drop non-seed story directory
    }
    print
  }
' "$PUBSPEC_BACKUP" > "$PUBSPEC.tmp"
mv "$PUBSPEC.tmp" "$PUBSPEC"
PUBSPEC_MUTATED=1

dropped_count=$(($(grep -cE "$all_story_regex" "$PUBSPEC_BACKUP") - $(grep -cE "$all_story_regex" "$PUBSPEC")))
kept_count=$(grep -cE "$all_story_regex" "$PUBSPEC")
log "pubspec.yaml: dropped $dropped_count story dirs, kept $kept_count seed dirs."

# ---------------------------------------------------------------------------
# 4. Move full/long MP3s out of seed directories
# ---------------------------------------------------------------------------
mkdir -p "$MOVED_AUDIO_BACKUP"
move_audio_out() {
  local story_dir="$1"
  if [ ! -d "$story_dir" ]; then
    return
  fi
  while IFS= read -r -d '' f; do
    local rel="${f#${REPO_ROOT}/}"
    local dest="$MOVED_AUDIO_BACKUP/$rel"
    mkdir -p "$(dirname "$dest")"
    mv "$f" "$dest"
    MOVED_FILES+=("$f")
  done < <(find "$story_dir" -type f \( \
              -name 'audio_*_story_full.mp3' -o \
              -name 'audio_*_story_long.mp3' \) -print0)
}

for id in "${SEED_TRADITIONAL[@]}"; do
  move_audio_out "$REPO_ROOT/assets/stories/traditional/$id"
done
for id in "${SEED_CREATIVE[@]}"; do
  move_audio_out "$REPO_ROOT/assets/stories/creative/$id"
done
log "Moved ${#MOVED_FILES[@]} full/long audio file(s) out of seed dirs."

# ---------------------------------------------------------------------------
# 5. Run the Android build
# ---------------------------------------------------------------------------
log "Running: flutter clean"
flutter clean >/dev/null

log "Running: flutter pub get"
flutter pub get >/dev/null

log "Running: flutter build appbundle --release"
flutter build appbundle --release

# ---------------------------------------------------------------------------
# 6. Report
# ---------------------------------------------------------------------------
aab_path="$REPO_ROOT/build/app/outputs/bundle/release/app-release.aab"
if [ -f "$aab_path" ]; then
  size_human=$(du -h "$aab_path" | cut -f1)
  size_bytes=$(stat -f%z "$aab_path" 2>/dev/null || stat -c%s "$aab_path" 2>/dev/null)
  log "BUILD SUCCESS"
  log "  AAB:  $aab_path"
  log "  Size: $size_human ($size_bytes bytes)"
  log "Before: 32 seed dirs bundled (full/long stripped) | After: AAB built."
else
  die "Build did not produce $aab_path"
fi

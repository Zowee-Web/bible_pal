#!/usr/bin/env bash
#
# verify_creative_archive.sh
# ---------------------------------------------------------------------------
# Verify that the T9 archive produced by archive_creative_to_t9.sh is a
# byte-for-byte copy of the working-tree Creative content. Compares:
#   - file count
#   - total byte count (assets/stories/creative tree)
#   - sha256 of every archived file
#
# Writes /tmp/verify_creative_archive.PASS on success. The deletion script
# refuses to run unless that marker exists.
#
# Stage 2 only. Created in Stage 1 prep, NOT executed in Stage 1.
#
# Usage:
#   bash scripts/verify_creative_archive.sh             # real run
#   DRY_RUN=1 bash scripts/verify_creative_archive.sh   # describe only
#
# Exit codes:
#   0  - verification passed, PASS marker written
#   1  - precondition failed (archive missing, manifest missing, etc.)
#   2  - mismatch found (count, bytes, or sha)
#
# ---------------------------------------------------------------------------

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration (must match archive_creative_to_t9.sh)
# ---------------------------------------------------------------------------

T9_ROOT="/Volumes/T9-Archive"
ARCHIVE_DATE="2026_05_13"
DEST_ROOT="${T9_ROOT}/bible_pal_archives/creative_retirement_${ARCHIVE_DATE}"
PRE_MANIFEST="/tmp/pre_archive_creative_tree.sha256"
POST_MANIFEST="/tmp/post_archive_creative_tree.sha256"
PASS_MARKER="/tmp/verify_creative_archive.PASS"
FAIL_MARKER="/tmp/verify_creative_archive.FAIL"

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DRY_RUN="${DRY_RUN:-0}"

log()  { printf '[verify] %s\n' "$*"; }
warn() { printf '[verify][WARN] %s\n' "$*" >&2; }
die()  { printf '[verify][FATAL] %s\n' "$*" >&2; rm -f "$PASS_MARKER"; printf 'fail\n' > "$FAIL_MARKER"; exit 1; }

cd "$PROJECT_ROOT"

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

# Clean up any previous PASS / FAIL markers so this run starts fresh.
rm -f "$PASS_MARKER" "$FAIL_MARKER"

[ -d "$T9_ROOT"   ] || die "T9 not mounted at $T9_ROOT."
[ -d "$DEST_ROOT" ] || die "Archive destination missing: $DEST_ROOT
Run scripts/archive_creative_to_t9.sh first."
[ -f "$DEST_ROOT/ARCHIVE_COMPLETE.txt" ] || die "ARCHIVE_COMPLETE.txt missing — archive did not finish cleanly."
[ -f "$PRE_MANIFEST" ] || die "Pre-archive sha256 manifest missing: $PRE_MANIFEST
Re-run archive_creative_to_t9.sh to regenerate it."

log "Project root:      $PROJECT_ROOT"
log "Archive:           $DEST_ROOT"
log "Pre-manifest:      $PRE_MANIFEST"
log "Dry-run:           $DRY_RUN"

if [ "$DRY_RUN" = "1" ]; then
  log "Dry-run mode — would perform count/byte/sha comparison against archive."
  exit 0
fi

# ---------------------------------------------------------------------------
# Check 1 — file count match for the big tree
# ---------------------------------------------------------------------------

log "Check 1: file count for assets/stories/creative tree"

if [ -d "assets/stories/creative" ]; then
  src_count=$(find assets/stories/creative -type f ! -name ".DS_Store" | wc -l | tr -d ' ')
else
  src_count=0
fi

if [ -d "$DEST_ROOT/assets/stories/creative" ]; then
  dst_count=$(find "$DEST_ROOT/assets/stories/creative" -type f ! -name ".DS_Store" | wc -l | tr -d ' ')
else
  dst_count=0
fi

log "  source: $src_count   archive: $dst_count"
[ "$src_count" = "$dst_count" ] || die "File count mismatch (src=$src_count vs dst=$dst_count)"

# ---------------------------------------------------------------------------
# Check 2 — byte count match for the big tree
# ---------------------------------------------------------------------------

log "Check 2: byte count for assets/stories/creative tree"

# Use BSD-friendly du (macOS). -A flag is portable to GNU.
src_bytes=$(find assets/stories/creative -type f ! -name ".DS_Store" -exec wc -c {} \; 2>/dev/null \
  | awk '{s+=$1} END {print s+0}')
dst_bytes=$(find "$DEST_ROOT/assets/stories/creative" -type f ! -name ".DS_Store" -exec wc -c {} \; 2>/dev/null \
  | awk '{s+=$1} END {print s+0}')

log "  source: $src_bytes bytes   archive: $dst_bytes bytes"
[ "$src_bytes" = "$dst_bytes" ] || die "Byte count mismatch (src=$src_bytes vs dst=$dst_bytes)"

# ---------------------------------------------------------------------------
# Check 3 — sha256 manifest match for every archived file
# ---------------------------------------------------------------------------

log "Check 3: sha256 manifest"

: > "$POST_MANIFEST"

# Rebuild the same kinds of entries the archive script wrote.
if [ -d "$DEST_ROOT/assets/stories/creative" ]; then
  find "$DEST_ROOT/assets/stories/creative" -type f ! -name ".DS_Store" \
    | sort | xargs shasum -a 256 \
    | sed "s|$DEST_ROOT/||" >> "$POST_MANIFEST"
fi

# Singleton files at archive root.
for rel in \
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
  if [ -f "$DEST_ROOT/$rel" ]; then
    shasum -a 256 "$DEST_ROOT/$rel" | sed "s|$DEST_ROOT/||" >> "$POST_MANIFEST"
  fi
done

# Voice sample archives.
for archive in "audio_archive_grace_2026_04_23" "audio_archive_ruth_v1_2026_04_25"; do
  if [ -d "$DEST_ROOT/assets/pal/$archive" ]; then
    find "$DEST_ROOT/assets/pal/$archive" -type f -name "CREATIVE_*.mp3" \
      | sort | xargs -I{} shasum -a 256 "{}" \
      | sed "s|$DEST_ROOT/||" >> "$POST_MANIFEST"
  fi
done

# The pre manifest paths are relative to the project root; the post manifest
# paths are relative to DEST_ROOT (we stripped the prefix). Normalize the pre
# manifest the same way for an apples-to-apples diff.
sort "$PRE_MANIFEST"   > "${PRE_MANIFEST}.sorted"
sort "$POST_MANIFEST"  > "${POST_MANIFEST}.sorted"

if diff -u "${PRE_MANIFEST}.sorted" "${POST_MANIFEST}.sorted" > /tmp/verify_creative_diff.txt; then
  log "  sha256 manifest MATCH"
else
  warn "sha256 manifest mismatch — see /tmp/verify_creative_diff.txt for details"
  head -50 /tmp/verify_creative_diff.txt >&2
  die "Archive does not match source. DO NOT delete anything."
fi

# ---------------------------------------------------------------------------
# Success
# ---------------------------------------------------------------------------

cat > "$PASS_MARKER" <<EOF
verified=true
date=${ARCHIVE_DATE}
src_file_count=${src_count}
src_bytes=${src_bytes}
EOF

log ""
log "VERIFICATION PASSED."
log "  PASS marker:    $PASS_MARKER"
log "  Pre manifest:   ${PRE_MANIFEST}.sorted"
log "  Post manifest:  ${POST_MANIFEST}.sorted"
log ""
log "Next: create git tag pre-creative-retirement-${ARCHIVE_DATE},"
log "then run scripts/remove_creative_after_verification.sh"

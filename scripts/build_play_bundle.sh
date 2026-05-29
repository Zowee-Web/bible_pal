#!/usr/bin/env bash
#
# build_play_bundle.sh — Build a Google Play AAB with curated, compressed audio.
#
# Stages a Play-only assets/stories/ from the compressed audio mirror
# (assets_audio_compressed/) and a curated story subset, swaps pubspec.yaml
# for a slim version, runs `flutter build appbundle`, then restores both.
# Dev workflow is fully restored on exit (success or failure).
#
# Usage:
#   ./scripts/build_play_bundle.sh             # full build
#   ./scripts/build_play_bundle.sh --stage     # stage only, do not build
#   ./scripts/build_play_bundle.sh --keep      # leave staged state in place
#                                              # after build (for inspection)
#

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

STAGE_ONLY=false
KEEP_AFTER_BUILD=false
for arg in "$@"; do
  case "$arg" in
    --stage) STAGE_ONLY=true ;;
    --keep)  KEEP_AFTER_BUILD=true ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

STORIES_DIR="$PROJECT_ROOT/assets/stories"
STORIES_BACKUP="$PROJECT_ROOT/assets/stories.devbackup"
PAL_AUDIO_DIR="$PROJECT_ROOT/assets/pal/audio"
PAL_AUDIO_BACKUP="$PROJECT_ROOT/assets/pal/audio.devbackup"
PAL_AUDIO_COMPRESSED="$PROJECT_ROOT/assets_pal_compressed/audio"
PUBSPEC="$PROJECT_ROOT/pubspec.yaml"
PUBSPEC_BACKUP="$PROJECT_ROOT/pubspec.yaml.devbackup"
STAGE_DIR="$PROJECT_ROOT/.play_build_stage/stories"
PICK_FILE="$PROJECT_ROOT/scripts/play_bundle_pick.json"

# ── Restore on exit (idempotent) ─────────────────────────────────────
restore_state() {
  local exit_code=$?
  if $KEEP_AFTER_BUILD && [ "$exit_code" -eq 0 ]; then
    echo ""
    echo "--keep set: leaving staged assets/stories/ and pubspec.yaml in place."
    echo "  Backups: $STORIES_BACKUP, $PAL_AUDIO_BACKUP, $PUBSPEC_BACKUP"
    return 0
  fi
  if [ -d "$STORIES_BACKUP" ]; then
    echo ""
    echo "Restoring assets/stories/ from devbackup..."
    rm -rf "$STORIES_DIR"
    mv "$STORIES_BACKUP" "$STORIES_DIR"
  fi
  if [ -d "$PAL_AUDIO_BACKUP" ]; then
    echo "Restoring assets/pal/audio/ from devbackup..."
    rm -rf "$PAL_AUDIO_DIR"
    mv "$PAL_AUDIO_BACKUP" "$PAL_AUDIO_DIR"
  fi
  if [ -f "$PUBSPEC_BACKUP" ]; then
    echo "Restoring pubspec.yaml from devbackup..."
    mv "$PUBSPEC_BACKUP" "$PUBSPEC"
  fi
  rm -rf "$PROJECT_ROOT/.play_build_stage"
  return $exit_code
}
trap restore_state EXIT INT TERM

# ── Sanity checks ────────────────────────────────────────────────────
if [ ! -f "$PICK_FILE" ]; then
  echo "ERROR: Pick file missing: $PICK_FILE" >&2
  echo "Generate it before running this script." >&2
  exit 1
fi
if [ -d "$STORIES_BACKUP" ] || [ -d "$PAL_AUDIO_BACKUP" ] || [ -f "$PUBSPEC_BACKUP" ]; then
  echo "ERROR: Stale backups found from a previous interrupted run." >&2
  echo "  $STORIES_BACKUP" >&2
  echo "  $PAL_AUDIO_BACKUP" >&2
  echo "  $PUBSPEC_BACKUP" >&2
  echo "Inspect, then either restore manually or remove the backups." >&2
  exit 1
fi
if [ ! -d "$PROJECT_ROOT/assets_audio_compressed/stories" ]; then
  echo "ERROR: assets_audio_compressed/stories not found." >&2
  echo "Run scripts/compress_audio.sh first." >&2
  exit 1
fi
if [ ! -d "$PAL_AUDIO_COMPRESSED" ]; then
  echo "ERROR: assets_pal_compressed/audio not found." >&2
  echo "Run scripts/compress_pal_audio.sh first." >&2
  exit 1
fi

# ── Stage curated bundle ─────────────────────────────────────────────
echo "Staging curated story bundle..."
rm -rf "$PROJECT_ROOT/.play_build_stage"
mkdir -p "$STAGE_DIR/traditional" "$STAGE_DIR/creative"

python3 - <<PYEOF
import json, os, shutil, sys

ROOT = "$PROJECT_ROOT"
PICK_FILE = "$PICK_FILE"
SRC_TEXT = os.path.join(ROOT, "assets/stories")
SRC_AUDIO = os.path.join(ROOT, "assets_audio_compressed/stories")
DST = os.path.join(ROOT, ".play_build_stage/stories")

with open(PICK_FILE) as f:
    pick = json.load(f)

trad_set = set(pick["traditional"])
crea_set = set(pick["creative"])
picked = {("traditional", sid) for sid in trad_set} | {("creative", sid) for sid in crea_set}

# Copy text files (per-story dirs) + compressed audio
# Play bundle ships WEB audio only — KJV text still copied for scripture display.
def is_kjv_audio(fn):
    return fn.endswith(".mp3") and ("_kjv_" in fn or "reflection_kjv" in fn)

for kind, ids in [("traditional", trad_set), ("creative", crea_set)]:
    for sid in ids:
        src_text_dir = os.path.join(SRC_TEXT, kind, sid)
        src_audio_dir = os.path.join(SRC_AUDIO, kind, sid)
        dst_dir = os.path.join(DST, kind, sid)
        os.makedirs(dst_dir, exist_ok=True)
        # Text/meta/scripture (not audio, not "long" anything; KJV text kept)
        if os.path.isdir(src_text_dir):
            for fn in os.listdir(src_text_dir):
                if fn.endswith(".mp3"):
                    continue
                if "_long" in fn:
                    continue
                shutil.copy2(os.path.join(src_text_dir, fn), os.path.join(dst_dir, fn))
        # Compressed audio: WEB only, no "long"
        if os.path.isdir(src_audio_dir):
            for fn in os.listdir(src_audio_dir):
                if not fn.endswith(".mp3"):
                    continue
                if "_long.mp3" in fn:
                    continue
                if is_kjv_audio(fn):
                    continue
                shutil.copy2(os.path.join(src_audio_dir, fn), os.path.join(dst_dir, fn))

# Copy registry/index files
for fn in ["scripture_anchor_registry.json",
          "biblical_figure_registry.json",
          "character_registry.json",
          "paths_index.json"]:
    src = os.path.join(SRC_TEXT, fn)
    if os.path.exists(src):
        shutil.copy2(src, os.path.join(DST, fn))

# Filter manifest.json to picked stories, drop "long" + drop KJV variants
with open(os.path.join(SRC_TEXT, "manifest.json")) as f:
    manifest = json.load(f)
filtered = []
for p in manifest["parables"]:
    afp = p.get("audioFilePath", "")
    parts = afp.split("/")
    if len(parts) < 3:
        continue
    if (parts[0], parts[1]) not in picked:
        continue
    if p.get("storyLength") == "long":
        continue
    if p.get("translationId") == "KJV":
        continue
    filtered.append(p)
manifest["parables"] = filtered
with open(os.path.join(DST, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)

# Filter jesus_life_index.json to picked story IDs
with open(os.path.join(SRC_TEXT, "jesus_life_index.json")) as f:
    jli = json.load(f)
def story_in_pick(story_id):
    # story_1000_weary_short_traditional → traditional/1000
    parts = story_id.split("_")
    if len(parts) < 4:
        return False
    sid = parts[1]
    kind = parts[-1]
    return (kind, sid) in picked
jli["sequence"] = [s for s in jli.get("sequence", []) if story_in_pick(s)]
with open(os.path.join(DST, "jesus_life_index.json"), "w") as f:
    json.dump(jli, f, indent=2)

print(f"  Staged {len(trad_set)} Traditional + {len(crea_set)} Creative stories")
print(f"  Manifest: {len(filtered)} parable variants (was {len(manifest['parables']) if False else len(manifest['parables'])})")
print(f"  Jesus path: {len(jli['sequence'])} entries")
PYEOF

# Compute staged audio total
staged_audio_mb=$(find "$STAGE_DIR" -name "*.mp3" -exec du -ck {} + | tail -1 | awk '{printf "%.1f", $1/1024}')
echo "  Staged audio: ${staged_audio_mb} MB"

# ── Generate slim pubspec.yaml ───────────────────────────────────────
echo "Generating Play pubspec.yaml..."
PROJECT_ROOT="$PROJECT_ROOT" PUBSPEC="$PUBSPEC" PICK_FILE="$PICK_FILE" python3 - <<'PYEOF'
import os, re, json

PUBSPEC = os.environ["PUBSPEC"]
PICK_FILE = os.environ["PICK_FILE"]

with open(PICK_FILE) as f:
    pick = json.load(f)

with open(PUBSPEC) as f:
    src = f.read()

# Match all per-story dir lines (one regex covers both traditional and creative)
line_re = re.compile(
    r"^    - assets/stories/(?:traditional|creative)/\d+/\n",
    re.MULTILINE,
)

# Build the curated replacement block
new_lines = [f"    - assets/stories/traditional/{sid}/\n" for sid in pick["traditional"]]
new_lines += [f"    - assets/stories/creative/{sid}/\n" for sid in pick["creative"]]
replacement = "".join(new_lines)

# Remove every per-story dir line, then insert the curated block once
# at the position where the original block started.
match = line_re.search(src)
if not match:
    raise SystemExit("ERROR: no per-story asset lines found in pubspec.yaml")
insert_pos = match.start()
stripped = line_re.sub("", src)
# After stripping, insert_pos may have shifted because the lines before
# the first match are unchanged. So insert_pos is still valid.
new_src = stripped[:insert_pos] + replacement + stripped[insert_pos:]

with open(PUBSPEC + ".play_generated", "w") as f:
    f.write(new_src)

# Sanity: count refs after rewrite
trad_count = new_src.count("assets/stories/traditional/")
crea_count = new_src.count("assets/stories/creative/")
print(f"  Pubspec rewritten: {trad_count} traditional + {crea_count} creative dir refs")
PYEOF

# ── Swap state in place ──────────────────────────────────────────────
echo "Swapping state for build..."
mv "$STORIES_DIR" "$STORIES_BACKUP"
mv "$STAGE_DIR" "$STORIES_DIR"
mv "$PAL_AUDIO_DIR" "$PAL_AUDIO_BACKUP"
cp -R "$PAL_AUDIO_COMPRESSED" "$PAL_AUDIO_DIR"
mv "$PUBSPEC" "$PUBSPEC_BACKUP"
mv "$PUBSPEC.play_generated" "$PUBSPEC"

pal_mb=$(du -sm "$PAL_AUDIO_DIR" | awk '{print $1}')
echo "  Staged PAL audio (compressed): ${pal_mb} MB"

if $STAGE_ONLY; then
  echo ""
  echo "=== Stage complete (--stage flag set, not building) ==="
  echo "Staged state is in place. Run with --keep to keep it, or"
  echo "interrupt the script (Ctrl+C) to restore."
  read -p "Press Enter to restore..." _
  exit 0
fi

# ── Build AAB ────────────────────────────────────────────────────────
echo ""
echo "=== Building release AAB ==="
flutter build appbundle --release

# ── Report ───────────────────────────────────────────────────────────
AAB_PATH="$PROJECT_ROOT/build/app/outputs/bundle/release/app-release.aab"
if [ -f "$AAB_PATH" ]; then
  AAB_SIZE=$(du -h "$AAB_PATH" | cut -f1)
  AAB_BYTES=$(stat -f%z "$AAB_PATH" 2>/dev/null || stat -c%s "$AAB_PATH")
  AAB_MB=$(echo "scale=1; $AAB_BYTES / 1048576" | bc)
  echo ""
  echo "=== Build success ==="
  echo "AAB:  $AAB_PATH"
  echo "Size: $AAB_SIZE ($AAB_MB MB)"
  if (( $(echo "$AAB_MB < 200" | bc -l) )); then
    echo "Status: ✓ Under Google Play 200 MB cap"
  else
    echo "Status: ✗ Over 200 MB cap (must trim further)"
  fi
else
  echo "ERROR: AAB not found at $AAB_PATH" >&2
  exit 1
fi

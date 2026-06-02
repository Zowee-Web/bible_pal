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
LOCK_DIR="$PROJECT_ROOT/.bundle_build.lock.d"

# ── Restore on exit (idempotent) ─────────────────────────────────────
LOCK_ACQUIRED=false

restore_state() {
  local exit_code=$?
  # If we did not acquire the lock, another bundle build owns the dev tree.
  # Backups and stage dirs belong to that process — touch nothing.
  if [ "$LOCK_ACQUIRED" != "true" ]; then
    return $exit_code
  fi
  if $KEEP_AFTER_BUILD && [ "$exit_code" -eq 0 ]; then
    echo ""
    echo "--keep set: leaving staged assets/stories/ and pubspec.yaml in place."
    echo "  Backups: $STORIES_BACKUP, $PAL_AUDIO_BACKUP, $PUBSPEC_BACKUP"
    rmdir "$LOCK_DIR" 2>/dev/null || true
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
  rmdir "$LOCK_DIR" 2>/dev/null || true
  return $exit_code
}
trap restore_state EXIT INT TERM

# ── Cross-platform staging mutex (portable: macOS + Linux) ───────────
# Atomic mkdir is the portable lock primitive — `flock` is not present in
# default macOS installs. Released by restore_state on EXIT/INT/TERM.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "ERROR: another bundle/staging build holds $LOCK_DIR." >&2
  echo "If you are certain no other build is running, remove the lock with:" >&2
  echo "  rmdir $LOCK_DIR" >&2
  exit 1
fi
LOCK_ACQUIRED=true

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
# iOS-flavored backups indicate an iOS staging script is mid-flight or
# crashed without restoring. Refuse to proceed — the dev tree is not ours
# to mutate until those are resolved.
if [ -d "$PROJECT_ROOT/assets/stories.iosdevbackup" ] \
   || [ -d "$PROJECT_ROOT/assets/pal/audio.iosdevbackup" ] \
   || [ -f "$PROJECT_ROOT/pubspec.yaml.iosdevbackup" ]; then
  echo "ERROR: iOS-flavored .iosdevbackup markers present." >&2
  echo "Either an iOS bundle build is mid-flight or it crashed without restoring." >&2
  echo "Resolve those first before running the Play bundle build." >&2
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
mkdir -p "$STAGE_DIR/traditional"

python3 - <<PYEOF
import json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = "$PROJECT_ROOT"
PICK_FILE = "$PICK_FILE"
SRC_TEXT = os.path.join(ROOT, "assets/stories")
SRC_AUDIO = os.path.join(ROOT, "assets_audio_compressed/stories")
DST = os.path.join(ROOT, ".play_build_stage/stories")
STATE_FILE = os.path.join(ROOT, ".play_build_stage", "picked_stories.json")

def get_r2_base():
    env_path = os.path.join(ROOT, ".env")
    if os.path.isfile(env_path):
        with open(env_path) as f:
            for line in f:
                if line.startswith("AUDIO_BASE_URL="):
                    return line.split("=", 1)[1].strip()
    return None

R2_BASE = get_r2_base()
if not R2_BASE:
    print("ERROR: AUDIO_BASE_URL not found in .env — required for R2 audit.", file=sys.stderr)
    sys.exit(1)

with open(PICK_FILE) as f:
    pick = json.load(f)

audio_set = set(pick["traditional"])  # stories with bundled audio + text

def is_kjv_audio(fn):
    return fn.endswith(".mp3") and ("_kjv_" in fn or "reflection_kjv" in fn)

# Load manifest and apply length/translation filters
with open(os.path.join(SRC_TEXT, "manifest.json")) as f:
    manifest = json.load(f)

# Group surviving entries by (kind, sid)
entries_by_story = {}
for p in manifest["parables"]:
    afp = p.get("audioFilePath", "")
    parts = afp.split("/")
    if len(parts) < 3:
        continue
    if p.get("storyLength") == "long":
        continue
    if p.get("translationId") == "KJV":
        continue
    kind, sid = parts[0], parts[1]
    if kind == "creative":
        continue  # Creative lane retired 2026-05-13
    entries_by_story.setdefault((kind, sid), []).append(p)

# Identify text-only candidates: traditional stories not in audio_set
# Their audio paths must be R2-verified before inclusion
text_only_candidates = {
    key: entries for key, entries in entries_by_story.items()
    if key[0] == "traditional" and key[1] not in audio_set
}

# Collect distinct audio paths to probe
probe_paths = sorted({
    p["audioFilePath"]
    for entries in text_only_candidates.values()
    for p in entries
})

print(f"  R2 audit: probing {len(probe_paths)} non-bundled audio paths against {R2_BASE}...")

def probe(path):
    url = f"{R2_BASE}/{path}"
    r = subprocess.run(
        ["curl", "-sI", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "10", url],
        capture_output=True, text=True,
    )
    return path, r.stdout.strip() == "200"

with ThreadPoolExecutor(max_workers=24) as pool:
    probe_results = dict(pool.map(probe, probe_paths))

r2_hits = sum(1 for v in probe_results.values() if v)
r2_misses = len(probe_paths) - r2_hits
print(f"    on R2: {r2_hits}   missing (dropped): {r2_misses}")

# Warn if R2 looks unreachable
if probe_paths and r2_hits == 0:
    print("  WARNING: 0 R2 hits — network unreachable or bucket empty.")
    print("           Bundle will ship audio-bundled set only.")

# Build final picked sets
text_only_set = set()
final_entries = []
for (kind, sid), entries in entries_by_story.items():
    if sid in audio_set:
        final_entries.extend(entries)
        continue
    surviving = [p for p in entries if probe_results.get(p["audioFilePath"], False)]
    if surviving:
        text_only_set.add(sid)
        final_entries.extend(surviving)

picked_stories = audio_set | text_only_set

# Stage text/meta/scripture for ALL picked stories
for sid in picked_stories:
    src_text_dir = os.path.join(SRC_TEXT, "traditional", sid)
    dst_dir = os.path.join(DST, "traditional", sid)
    os.makedirs(dst_dir, exist_ok=True)
    if os.path.isdir(src_text_dir):
        for fn in os.listdir(src_text_dir):
            if fn.endswith(".mp3"):
                continue
            if "_long" in fn:
                continue
            shutil.copy2(os.path.join(src_text_dir, fn), os.path.join(dst_dir, fn))

# Stage audio for audio_set only (WEB short/full/reflection from compressed mirror)
for sid in audio_set:
    src_audio_dir = os.path.join(SRC_AUDIO, "traditional", sid)
    dst_dir = os.path.join(DST, "traditional", sid)
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

# Write filtered manifest
manifest["parables"] = final_entries
with open(os.path.join(DST, "manifest.json"), "w") as f:
    json.dump(manifest, f, indent=2)

# Filter jesus_life_index by final picked set
with open(os.path.join(SRC_TEXT, "jesus_life_index.json")) as f:
    jli = json.load(f)
def story_in_pick(story_id):
    parts = story_id.split("_")
    if len(parts) < 4:
        return False
    return parts[1] in picked_stories
jli["sequence"] = [s for s in jli.get("sequence", []) if story_in_pick(s)]
with open(os.path.join(DST, "jesus_life_index.json"), "w") as f:
    json.dump(jli, f, indent=2)

# Persist picked sets for pubspec generation pass
with open(STATE_FILE, "w") as f:
    json.dump({
        "audio_bundled": sorted(audio_set),
        "text_only": sorted(text_only_set),
        "all": sorted(picked_stories),
    }, f, indent=2)

print(f"  Audio-bundled stories:           {len(audio_set)}")
print(f"  Text-only (R2-served) stories:   {len(text_only_set)}")
print(f"  Total launch corpus:             {len(picked_stories)}")
print(f"  Manifest variants:               {len(final_entries)}")
print(f"  Jesus path entries:              {len(jli['sequence'])}")
PYEOF

# Compute staged audio + text totals
staged_audio_mb=$(find "$STAGE_DIR" -name "*.mp3" -exec du -ck {} + | tail -1 | awk '{printf "%.1f", $1/1024}')
staged_text_kb=$(find "$STAGE_DIR" \( -name "*.txt" -o -name "*.json" \) -exec du -ck {} + | tail -1 | awk '{print $1}')
echo "  Staged audio: ${staged_audio_mb} MB"
echo "  Staged text + meta: ${staged_text_kb} KB"

# ── Generate slim pubspec.yaml ───────────────────────────────────────
echo "Generating Play pubspec.yaml..."
PROJECT_ROOT="$PROJECT_ROOT" PUBSPEC="$PUBSPEC" python3 - <<'PYEOF'
import os, re, json

PUBSPEC = os.environ["PUBSPEC"]
PROJECT_ROOT = os.environ["PROJECT_ROOT"]
STATE_FILE = os.path.join(PROJECT_ROOT, ".play_build_stage", "picked_stories.json")

with open(STATE_FILE) as f:
    state = json.load(f)

with open(PUBSPEC) as f:
    src = f.read()

# Match all per-story dir lines (one regex covers both traditional and creative)
line_re = re.compile(
    r"^    - assets/stories/(?:traditional|creative)/\d+/\n",
    re.MULTILINE,
)

# List every picked story dir (audio-bundled + text-only). Pubspec is
# directory-scoped, so audio absence in a text-only dir is what makes it text-only.
new_lines = [f"    - assets/stories/traditional/{sid}/\n" for sid in state["all"]]
replacement = "".join(new_lines)

match = line_re.search(src)
if not match:
    raise SystemExit("ERROR: no per-story asset lines found in pubspec.yaml")
insert_pos = match.start()
stripped = line_re.sub("", src)
new_src = stripped[:insert_pos] + replacement + stripped[insert_pos:]

with open(PUBSPEC + ".play_generated", "w") as f:
    f.write(new_src)

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

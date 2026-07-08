#!/usr/bin/env bash
#
# build_ios_bundle.sh — Build an iOS Runner.app with curated, compressed audio.
#
# Stages an iOS-only assets/stories/ from the compressed audio mirror
# (assets_audio_compressed/) and a curated story subset, swaps pubspec.yaml
# for a slim version, runs `flutter build ios --release`, then restores.
# Dev workflow is fully restored on exit (success or failure).
#
# Usage:
#   ./scripts/build_ios_bundle.sh             # full build
#   ./scripts/build_ios_bundle.sh --stage     # stage only, do not build
#   ./scripts/build_ios_bundle.sh --keep      # leave staged state in place
#                                             # after build (for inspection)
#
# Mirrors scripts/build_play_bundle.sh with intentional deltas:
#   - Stage dir:        .ios_build_stage/   (vs .play_build_stage/)
#   - Pubspec temp:     pubspec.yaml.ios_generated
#   - Backup suffix:    .iosdevbackup       (vs .devbackup) — keeps Android
#                       and iOS backup namespaces distinct so concurrent
#                       runs fail loudly instead of corrupting the dev tree.
#   - Shared lock:      .bundle_build.lock.d (same mkdir mutex Android holds).
#   - Build command:    flutter clean → flutter pub get → pod install →
#                       flutter build ios --release.
#   - Output report:    build/ios/iphoneos/Runner.app size (uncompressed).
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
STORIES_BACKUP="$PROJECT_ROOT/assets/stories.iosdevbackup"
PAL_AUDIO_DIR="$PROJECT_ROOT/assets/pal/audio"
PAL_AUDIO_BACKUP="$PROJECT_ROOT/assets/pal/audio.iosdevbackup"
PAL_AUDIO_COMPRESSED="$PROJECT_ROOT/assets_pal_compressed/audio"
PUBSPEC="$PROJECT_ROOT/pubspec.yaml"
PUBSPEC_BACKUP="$PROJECT_ROOT/pubspec.yaml.iosdevbackup"
STAGE_DIR="$PROJECT_ROOT/.ios_build_stage/stories"
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
    echo "Restoring assets/stories/ from iosdevbackup..."
    rm -rf "$STORIES_DIR"
    mv "$STORIES_BACKUP" "$STORIES_DIR"
  fi
  if [ -d "$PAL_AUDIO_BACKUP" ]; then
    echo "Restoring assets/pal/audio/ from iosdevbackup..."
    rm -rf "$PAL_AUDIO_DIR"
    mv "$PAL_AUDIO_BACKUP" "$PAL_AUDIO_DIR"
  fi
  if [ -f "$PUBSPEC_BACKUP" ]; then
    echo "Restoring pubspec.yaml from iosdevbackup..."
    mv "$PUBSPEC_BACKUP" "$PUBSPEC"
  fi
  rm -rf "$PROJECT_ROOT/.ios_build_stage"
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
  exit 1
fi
# iOS-flavored stale backups indicate a prior iOS staging crashed.
if [ -d "$STORIES_BACKUP" ] || [ -d "$PAL_AUDIO_BACKUP" ] || [ -f "$PUBSPEC_BACKUP" ]; then
  echo "ERROR: Stale iOS backups found from a previous interrupted run." >&2
  echo "  $STORIES_BACKUP" >&2
  echo "  $PAL_AUDIO_BACKUP" >&2
  echo "  $PUBSPEC_BACKUP" >&2
  echo "Inspect, then either restore manually or remove the backups." >&2
  exit 1
fi
# Android-flavored stale backups indicate a Play build is mid-flight or crashed.
if [ -d "$PROJECT_ROOT/assets/stories.devbackup" ] \
   || [ -d "$PROJECT_ROOT/assets/pal/audio.devbackup" ] \
   || [ -f "$PROJECT_ROOT/pubspec.yaml.devbackup" ]; then
  echo "ERROR: Android-flavored .devbackup markers present." >&2
  echo "Either a Play build is mid-flight or it crashed without restoring." >&2
  echo "Resolve those first before running the iOS bundle build." >&2
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
# ATS prerequisite: HTTPS R2 base URL only.
ENV_BASE_URL="$(grep -E '^AUDIO_BASE_URL=' "$PROJECT_ROOT/.env" 2>/dev/null | head -1 | cut -d= -f2- | tr -d ' "')"
if [ -z "${ENV_BASE_URL:-}" ]; then
  echo "ERROR: AUDIO_BASE_URL not found in .env." >&2
  exit 1
fi
if [[ "$ENV_BASE_URL" != https://* ]]; then
  echo "ERROR: AUDIO_BASE_URL must be https:// (iOS ATS blocks plain http)." >&2
  echo "  Got: $ENV_BASE_URL" >&2
  exit 1
fi
# Tooling
command -v flutter >/dev/null || { echo "ERROR: flutter not on PATH" >&2; exit 1; }
command -v pod >/dev/null     || { echo "ERROR: pod (CocoaPods) not on PATH" >&2; exit 1; }
command -v python3 >/dev/null || { echo "ERROR: python3 not on PATH" >&2; exit 1; }
command -v curl >/dev/null    || { echo "ERROR: curl not on PATH" >&2; exit 1; }
command -v xcrun >/dev/null   || { echo "ERROR: xcrun not on PATH" >&2; exit 1; }

# ── Stage curated bundle ─────────────────────────────────────────────
# This Python block is intentionally identical to the corresponding block in
# scripts/build_play_bundle.sh. The only differences are the stage root path
# (.ios_build_stage vs .play_build_stage) and the state-file location. When
# the time comes to factor this into scripts/lib/stage_corpus.py, do it in a
# separate slice after iOS has shipped at least once.

echo "Staging curated story bundle..."
rm -rf "$PROJECT_ROOT/.ios_build_stage"
mkdir -p "$STAGE_DIR/traditional" "$STAGE_DIR/kids"

python3 - <<PYEOF
import json, os, shutil, subprocess, sys
from concurrent.futures import ThreadPoolExecutor

ROOT = "$PROJECT_ROOT"
PICK_FILE = "$PICK_FILE"
SRC_TEXT = os.path.join(ROOT, "assets/stories")
SRC_AUDIO = os.path.join(ROOT, "assets_audio_compressed/stories")
DST = os.path.join(ROOT, ".ios_build_stage/stories")
STATE_FILE = os.path.join(ROOT, ".ios_build_stage", "picked_stories.json")

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

bundled_pick = set(pick["traditional"])  # curated traditional stories with bundled audio

def is_kjv_audio(fn):
    return fn.endswith(".mp3") and ("_kjv_" in fn or "reflection_kjv" in fn)

# Load manifest (full 1252-entry corpus). Step 3: the FULL manifest is bundled
# verbatim so first-launch mood selection has the complete pool. Audio is still
# pruned to the curated set below.
with open(os.path.join(SRC_TEXT, "manifest.json")) as f:
    manifest = json.load(f)

# Compute all unique story IDs in the full manifest. Used by text staging and
# pubspec rewrite so every manifest entry has its text/scripture/meta files in
# the bundled tree (Step 3 — fixes catalog-drift mood-selection failure).
# Map each story id -> its lane dir ("traditional" or "kids") from the manifest.
sid_kind = {}
for p in manifest["parables"]:
    afp = p.get("audioFilePath", "")
    parts = afp.split("/")
    if len(parts) >= 3 and parts[0] in ("traditional", "kids"):
        sid_kind[parts[1]] = parts[0]
all_manifest_sids = set(sid_kind)

# Audio pick: curated traditional set PLUS every kid story (kid lane ships in full).
kid_sids = {sid for sid, k in sid_kind.items() if k == "kids"}
audio_set = bundled_pick | kid_sids

# Group surviving entries by (kind, sid) — used for the AUDIO pick (R2 audit).
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
    if key[0] in ("traditional", "kids") and key[1] not in audio_set
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

# Stage text/meta/scripture for EVERY story in the manifest (Step 3 — full
# text coverage so mood selection on the full manifest never surfaces "No
# story text available"). Long text variants are bundled too because long
# entries appear in the staged manifest.
for sid in all_manifest_sids:
    kind = sid_kind.get(sid)
    if not kind:
        continue
    src_text_dir = os.path.join(SRC_TEXT, kind, sid)
    dst_dir = os.path.join(DST, kind, sid)
    if os.path.isdir(src_text_dir):
        os.makedirs(dst_dir, exist_ok=True)
        for fn in os.listdir(src_text_dir):
            if fn.endswith(".mp3"):
                continue
            shutil.copy2(os.path.join(src_text_dir, fn), os.path.join(dst_dir, fn))

# Stage audio for audio_set only (WEB short/full/reflection from compressed
# mirror). Step 3: create dst_dir here too — text loop only visits sids
# present in the manifest, so an audio_set sid that's absent from the
# manifest (pick-file / manifest mismatch) needs its own dir creation.
for sid in audio_set:
    kind = sid_kind.get(sid, "traditional")
    src_audio_dir = os.path.join(SRC_AUDIO, kind, sid)
    dst_dir = os.path.join(DST, kind, sid)
    if os.path.isdir(src_audio_dir):
        os.makedirs(dst_dir, exist_ok=True)
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

# Write the FULL manifest verbatim (Step 3). final_entries is kept for the
# diagnostics print below but no longer mutates the bundled manifest.
shutil.copy2(os.path.join(SRC_TEXT, "manifest.json"),
             os.path.join(DST, "manifest.json"))

# Filter jesus_life_index by manifest presence (Step 3 — consistent with
# expanded manifest staging so the path UI references stories actually in
# the bundled catalog).
with open(os.path.join(SRC_TEXT, "jesus_life_index.json")) as f:
    jli = json.load(f)
def story_in_manifest(story_id):
    parts = story_id.split("_")
    if len(parts) < 4:
        return False
    return parts[1] in all_manifest_sids
jli["sequence"] = [s for s in jli.get("sequence", []) if story_in_manifest(s)]
with open(os.path.join(DST, "jesus_life_index.json"), "w") as f:
    json.dump(jli, f, indent=2)

# Persist picked + manifest sets for pubspec generation pass (Step 3 adds
# manifest_sids so pubspec lists every story dir whose ID is in the staged
# manifest, not just the audio-verified subset).
with open(STATE_FILE, "w") as f:
    json.dump({
        "audio_bundled": sorted(audio_set),
        "text_only": sorted(text_only_set),
        "all": sorted(picked_stories),
        "manifest_sids": sorted(all_manifest_sids),
        "sid_kind": sid_kind,
    }, f, indent=2)

print(f"  Audio-bundled stories:           {len(audio_set)}")
print(f"  Text-only (R2-served) stories:   {len(text_only_set)}")
print(f"  Audio launch corpus:             {len(picked_stories)}")
print(f"  Audio-verified manifest entries: {len(final_entries)}")
print(f"  Full bundled manifest entries:   {len(manifest['parables'])}")
print(f"  All stories in manifest:         {len(all_manifest_sids)}")
print(f"  Jesus path entries:              {len(jli['sequence'])}")
PYEOF

# Compute staged audio + text totals and structural counts (pre-swap, while
# the stage dir is still at $STAGE_DIR).
staged_audio_mb=$(find "$STAGE_DIR" -name "*.mp3" -exec du -ck {} + | tail -1 | awk '{printf "%.1f", $1/1024}')
staged_text_kb=$(find "$STAGE_DIR" \( -name "*.txt" -o -name "*.json" \) -exec du -ck {} + | tail -1 | awk '{print $1}')
staged_story_dirs=$(find "$STAGE_DIR/traditional" "$STAGE_DIR/kids" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l | awk '{print $1}')
staged_audio_files=$(find "$STAGE_DIR" -name "*.mp3" | wc -l | awk '{print $1}')
staged_manifest_entries=$(python3 -c "import json,sys;print(len(json.load(open('$STAGE_DIR/manifest.json'))['parables']))")
echo "  Staged audio: ${staged_audio_mb} MB"
echo "  Staged text + meta: ${staged_text_kb} KB"
echo "  Staged story dirs: ${staged_story_dirs}"
echo "  Staged audio files: ${staged_audio_files}"
echo "  Staged manifest entries: ${staged_manifest_entries}"

# Step 3 — text coverage check: every story in the staged manifest must
# have its referenced textFilePath present in the staged tree.
missing_text=$(python3 -c "
import json, os
m = json.load(open('$STAGE_DIR/manifest.json'))
missing = [p['textFilePath'] for p in m['parables']
           if p.get('textFilePath') and not os.path.exists(os.path.join('$STAGE_DIR', p['textFilePath']))]
print(len(missing))
")
echo "  Text coverage check: $missing_text manifest entries missing textFilePath in staged tree"
if [ "$missing_text" -gt 0 ]; then
  echo "  WARNING: text coverage incomplete — investigate before shipping"
fi

# ── Generate slim pubspec.yaml ───────────────────────────────────────
echo "Generating iOS pubspec.yaml..."
PROJECT_ROOT="$PROJECT_ROOT" PUBSPEC="$PUBSPEC" python3 - <<'PYEOF'
import os, re, json

PUBSPEC = os.environ["PUBSPEC"]
PROJECT_ROOT = os.environ["PROJECT_ROOT"]
STATE_FILE = os.path.join(PROJECT_ROOT, ".ios_build_stage", "picked_stories.json")

with open(STATE_FILE) as f:
    state = json.load(f)

with open(PUBSPEC) as f:
    src = f.read()

# Match all per-story dir lines (one regex covers traditional, creative, kids)
line_re = re.compile(
    r"^    - assets/stories/(?:traditional|creative|kids)/\d+/\n",
    re.MULTILINE,
)

# List every story dir whose ID is in the staged manifest (Step 3), under its
# own lane (traditional/<id>/ or kids/<id>/). Audio absence makes a dir
# text-only at runtime; the three-tier resolver handles it via R2 / null-return.
sid_kind = state.get("sid_kind", {})
new_lines = [f"    - assets/stories/{sid_kind.get(sid, 'traditional')}/{sid}/\n"
             for sid in state["manifest_sids"]]
replacement = "".join(new_lines)

match = line_re.search(src)
if not match:
    raise SystemExit("ERROR: no per-story asset lines found in pubspec.yaml")
insert_pos = match.start()
stripped = line_re.sub("", src)
new_src = stripped[:insert_pos] + replacement + stripped[insert_pos:]

with open(PUBSPEC + ".ios_generated", "w") as f:
    f.write(new_src)

trad_count = new_src.count("assets/stories/traditional/")
kids_count = new_src.count("assets/stories/kids/")
print(f"  Pubspec rewritten: {trad_count} traditional + {kids_count} kids dir refs")
PYEOF

# Step 3 — pubspec coverage check: pubspec must declare every story dir
# whose ID appears in the staged manifest.
pubspec_dir_count=$(grep -cE "^    - assets/stories/(traditional|kids)/" "$PUBSPEC.ios_generated" 2>/dev/null || echo 0)
unique_sids_in_manifest=$(python3 -c "
import json
m = json.load(open('$STAGE_DIR/manifest.json'))
sids = set()
for p in m['parables']:
    afp = p.get('audioFilePath', '')
    parts = afp.split('/')
    if len(parts) >= 3 and parts[0] in ('traditional', 'kids'):
        sids.add(parts[1])
print(len(sids))
")
echo "  Pubspec coverage check: $pubspec_dir_count dirs declared vs $unique_sids_in_manifest unique manifest sids"
if [ "$pubspec_dir_count" -ne "$unique_sids_in_manifest" ]; then
  echo "  WARNING: pubspec coverage mismatch — investigate before shipping"
fi

# ── Swap state in place ──────────────────────────────────────────────
echo "Swapping state for build..."
mv "$STORIES_DIR" "$STORIES_BACKUP"
mv "$STAGE_DIR" "$STORIES_DIR"
mv "$PAL_AUDIO_DIR" "$PAL_AUDIO_BACKUP"
cp -R "$PAL_AUDIO_COMPRESSED" "$PAL_AUDIO_DIR"
mv "$PUBSPEC" "$PUBSPEC_BACKUP"
mv "$PUBSPEC.ios_generated" "$PUBSPEC"

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

# ── Build iOS Runner.app ─────────────────────────────────────────────
# flutter clean inside the staged window — Xcode's incremental build copies
# flutter_assets/ from a cached intermediate; without clean, a previous
# full-corpus build leaks into Runner.app.
echo ""
echo "=== flutter clean (inside staged window) ==="
flutter clean

echo "=== flutter pub get ==="
flutter pub get

echo "=== pod install ==="
( cd "$PROJECT_ROOT/ios" && pod install )

echo ""
echo "=== Building release Runner.app ==="
# Regenerate the secret-reduced client config so the build bundles app.env
# (allowlisted client keys only) — never the full .env with pipeline secrets.
"$PROJECT_ROOT/scripts/gen_app_env.sh"
# Build the .app, not the .ipa. IPA generation requires explicit distribution
# method + signing identity selection and is out of scope for this slice,
# which targets local-device install via xcrun devicectl.
flutter build ios --release

# ── Report ───────────────────────────────────────────────────────────
RUNNER_APP="$PROJECT_ROOT/build/ios/iphoneos/Runner.app"
if [ -d "$RUNNER_APP" ]; then
  APP_MB=$(du -sm "$RUNNER_APP" | awk '{print $1}')
  echo ""
  echo "=== Build success ==="
  echo "Runner.app: $RUNNER_APP"
  echo "Size: ${APP_MB} MB"
  echo "Staged story dirs:       ${staged_story_dirs}"
  echo "Staged audio files:      ${staged_audio_files}"
  echo "Staged manifest entries: ${staged_manifest_entries}"
  if [ "$APP_MB" -lt 200 ]; then
    echo "Status: under 200 MB smoke-test target"
  else
    echo "Status: over 200 MB smoke-test target — investigate before shipping"
  fi
  echo ""
  echo "Install with:"
  echo "  xcrun devicectl device install app --device <udid> $RUNNER_APP"
else
  echo "ERROR: Runner.app not found at $RUNNER_APP" >&2
  exit 1
fi

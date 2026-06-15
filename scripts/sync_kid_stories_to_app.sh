#!/usr/bin/env bash
#
# sync_kid_stories_to_app.sh — make every created kid story visible + playable.
#
# The rule: when a kid story has rendered (and -18/high-pass compressed) audio,
# it becomes VISIBLE (app manifest) and PLAYABLE (bundled). This script makes
# that automatic and idempotent — run it after rendering + normalizing a batch:
#
#   1. Surface: promote every kid story with audio into assets/stories/manifest.json
#   2. Pubspec: ensure assets/stories/kids/<id>/ is listed for every such story
#   3. Validate: kids gate + manifest.json / kids_manifest.json / pubspec sanity
#   4. Fail loudly if the COMPRESSED (-18) audio is missing for any surfaced story
#
# Does NOT run the Play/iOS build (heavyweight + riskier — keep that manual).
# Does NOT commit — review the diff, then commit yourself.
#
# Usage: ./scripts/sync_kid_stories_to_app.sh
#
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== 1/4  Surfacing kid stories into manifest.json =="
python3 scripts/promote_kid_stories.py --write

echo ""
echo "== 2/4  Syncing pubspec.yaml kid asset dirs =="
python3 - <<'PY'
import json, re
KM = "assets/stories/kids_manifest.json"
PUB = "pubspec.yaml"
TERMINAL = {"REJECTED", "SUPERSEDED"}

km = json.load(open(KM))
# Kid story dirs that have audio (production id parsed from kids/<id>/...).
want = set()
for s in km["stories"]:
    if s.get("audioFilePath") and s.get("status") not in TERMINAL:
        m = re.match(r"kids/(\d+)/", s["audioFilePath"])
        if m:
            want.add(m.group(1))
want_sorted = sorted(want, key=int)

lines = open(PUB).read().splitlines(keepends=True)
kid_re = re.compile(r"^    - assets/stories/kids/\d+/\s*$")
trad_re = re.compile(r"^    - assets/stories/traditional/\d+/\s*$")

# Drop existing kid dir lines; remember where to re-insert (first kid line, or
# right after the last traditional dir line if none exist yet).
kept, insert, last_trad = [], None, None
had = set()
for ln in lines:
    km_ = kid_re.match(ln)
    if km_:
        had.add(re.search(r"kids/(\d+)/", ln).group(1))
        if insert is None:
            insert = len(kept)
        continue
    if trad_re.match(ln):
        last_trad = len(kept)
    kept.append(ln)
if insert is None:
    insert = (last_trad + 1) if last_trad is not None else len(kept)

new = [f"    - assets/stories/kids/{sid}/\n" for sid in want_sorted]
out = kept[:insert] + new + kept[insert:]
open(PUB, "w").writelines(out)

added = sorted(want - had, key=int)
removed = sorted(had - want, key=int)
print(f"  kid dirs in pubspec: {len(want_sorted)}")
if added:   print(f"    + added:   {', '.join(added)}")
if removed: print(f"    - removed: {', '.join(removed)} (no longer have audio)")
if not added and not removed: print("    (already in sync)")
PY

echo ""
echo "== 3/4  Validating =="
python3 scripts/validate_kids.py >/dev/null && echo "  kids gate: 0 FAIL"
python3 -c "import json; json.load(open('assets/stories/manifest.json')); print('  manifest.json: valid JSON')"
python3 -c "import json; json.load(open('assets/stories/kids_manifest.json')); print('  kids_manifest.json: valid JSON')"
# pubspec sanity (pyyaml not guaranteed): structure intact + traditional block not nuked
python3 - <<'PY'
import re, sys
src = open("pubspec.yaml").read()
trad = len(re.findall(r"^    - assets/stories/traditional/\d+/$", src, re.M))
if "flutter:" not in src or "  assets:" not in src:
    sys.exit("  pubspec.yaml: STRUCTURE BROKEN (missing flutter:/assets:)")
if trad < 400:
    sys.exit(f"  pubspec.yaml: only {trad} traditional dirs — looks corrupted, aborting")
print(f"  pubspec.yaml: ok ({trad} traditional dir refs intact)")
PY

echo ""
echo "== 4/4  Checking compressed (-18) audio for every surfaced kid story =="
python3 - <<'PY'
import json, os, sys
m = json.load(open("assets/stories/manifest.json"))
pub = open("pubspec.yaml").read()
errs, dirs = [], set()
for p in m["parables"]:
    afp = p.get("audioFilePath", "")
    if not afp.startswith("kids/"):
        continue
    comp = os.path.join("assets_audio_compressed/stories", afp)
    if not os.path.exists(comp):
        errs.append(f"MISSING compressed audio: {comp}  (story {p['storyId']})")
    sid = afp.split("/")[1]
    if sid not in dirs:
        dirs.add(sid)
        if f"assets/stories/kids/{sid}/" not in pub:
            errs.append(f"pubspec missing dir: assets/stories/kids/{sid}/")
if errs:
    print("FAIL — surfaced kid stories are not fully playable:", file=sys.stderr)
    for e in errs:
        print("  - " + e, file=sys.stderr)
    print("\nRun compress_audio.sh (or loudnorm_audio.sh --highpass) for the missing "
          "compressed audio, then re-run this script.", file=sys.stderr)
    sys.exit(1)
print(f"  OK: {len(dirs)} kid story dirs — all compressed audio present + in pubspec")
PY

echo ""
echo "== Done. Kid stories synced (manifest + pubspec). Review the diff and commit. =="
echo "   To ship: run scripts/build_play_bundle.sh / build_ios_bundle.sh (manual)."

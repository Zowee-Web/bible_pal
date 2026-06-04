#!/bin/bash
# =============================================================================
# Bible PAL — Bulk upload manifest audio to Cloudflare R2
# =============================================================================
#
# Modes:
#   DRY_RUN=1       Audit every manifest path against R2 in parallel.
#                   Reports would-upload / would-skip (already-on-R2) /
#                   missing-locally / failed counts + sample paths.
#                   No writes, no wrangler auth required.
#   SMALL_BATCH=1   Upload only the first 5 files (live)
#   (default)       Upload every manifest audio path (live)
#
# Usage:
#   DRY_RUN=1     ./scripts/upload_r2_audio.sh   # step 1: audit
#   SMALL_BATCH=1 ./scripts/upload_r2_audio.sh   # step 2: live test (5 files)
#                 ./scripts/upload_r2_audio.sh   # step 3: full upload
#
# Requires: wrangler CLI, authenticated (wrangler login) — for live modes only.
#           Dry-run uses curl HEAD against the public R2 dev URL, no auth.
# =============================================================================

set -euo pipefail

# Run from repo root so .env / assets/stories paths resolve correctly even
# when the script is invoked from somewhere else (matches upload_r2_catalog.sh).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BUCKET="bible-pal-audio"
ASSETS_DIR="assets/stories"
MANIFEST="$ASSETS_DIR/manifest.json"

# Shared mutex with build_play_bundle.sh / build_ios_bundle.sh. Those scripts
# `mv assets/stories → assets/stories.devbackup` mid-build; a concurrent
# upload audit + upload loop reads those moved files as MISSING-local and
# silently drops them. Holding the same lock serializes uploads with
# Play/iOS bundle builds and prevents that race.
LOCK_DIR="$REPO_ROOT/.bundle_build.lock.d"
LOCK_ACQUIRED=false

# Counters
UPLOADED=0
SKIPPED=0
MISSING=0
FAILED=0

# Single cleanup function for everything — lock + audit tempdir. AUDIT_DIR
# is created later in the script; reference it defensively in case we exit
# before it's set.
AUDIT_DIR=""
cleanup() {
    [ -n "$AUDIT_DIR" ] && [ -d "$AUDIT_DIR" ] && rm -rf "$AUDIT_DIR"
    [ "$LOCK_ACQUIRED" = "true" ] && rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# ── Preflight checks ────────────────────────────────────────────────────────

# 0. Acquire the shared bundle-build lock. Atomic mkdir is the portable
# primitive — flock isn't on stock macOS. Released by trap on exit.
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "ERROR: another bundle build or upload holds $LOCK_DIR." >&2
    echo "If you are certain nothing else is running, remove it with:" >&2
    echo "  rmdir $LOCK_DIR" >&2
    exit 1
fi
LOCK_ACQUIRED=true

# 1. wrangler installed?
if ! command -v wrangler &>/dev/null; then
    echo "ERROR: wrangler CLI not found."
    echo "  Install:      npm install -g wrangler"
    echo "  Authenticate: wrangler login"
    exit 1
fi

# 2. wrangler authenticated? (list buckets as a test)
# Dry-run uses curl HEAD against the public R2 dev URL — no wrangler auth needed.
if [ "${DRY_RUN:-0}" != "1" ]; then
    # SIGPIPE guard: `grep -q` closes pipe early, which kills wrangler with
    # SIGPIPE and fails the pipeline under `set -o pipefail`.
    set +o pipefail
    bucket_list_output=$(wrangler r2 bucket list 2>/dev/null)
    set -o pipefail
    if ! echo "$bucket_list_output" | grep -q "$BUCKET"; then
        echo "ERROR: Cannot access R2 bucket '$BUCKET'."
        echo "  Possible causes:"
        echo "    - Not authenticated: run 'wrangler login'"
        echo "    - Bucket name wrong: expected '$BUCKET'"
        echo "    - Bucket doesn't exist in your Cloudflare account"
        echo ""
        echo "  Buckets found:"
        echo "${bucket_list_output:-    (none — auth likely failed)}"
        exit 1
    fi
fi

# 3. Manifest exists?
if [ ! -f "$MANIFEST" ]; then
    echo "ERROR: Manifest not found at $MANIFEST"
    exit 1
fi

# ── Extract audio paths from manifest ────────────────────────────────────────
# ONLY audioFilePath and reflectionAudioPath — both are always .mp3
# This ignores textFilePath, scriptureTextFilePath, and all other fields.

AUDIO_PATHS=$(python3 -c "
import json, sys
with open('$MANIFEST') as f:
    m = json.load(f)
paths = set()
for p in m.get('parables', []):
    for key in ('audioFilePath', 'reflectionAudioPath'):
        v = p.get(key, '')
        if v and v.endswith('.mp3'):
            paths.add(v)
        elif v:
            print(f'WARNING: non-mp3 path skipped: {v}', file=sys.stderr)
for p in sorted(paths):
    print(p)
")

TOTAL=$(echo "$AUDIO_PATHS" | wc -l | tr -d ' ')

# ── Determine mode ───────────────────────────────────────────────────────────

if [ "${DRY_RUN:-0}" = "1" ]; then
    MODE="DRY RUN (audit all $TOTAL paths, no uploads, no auth required)"
    LIMIT=$TOTAL
elif [ "${SMALL_BATCH:-0}" = "1" ]; then
    MODE="SMALL BATCH (first 5 files, live upload)"
    LIMIT=5
else
    MODE="FULL UPLOAD (all $TOTAL files)"
    LIMIT=$TOTAL
fi

# ── Header ───────────────────────────────────────────────────────────────────

echo "================================================================"
echo "  Bible PAL R2 Audio Upload"
echo "================================================================"
echo "  Mode:      $MODE"
echo "  Bucket:    $BUCKET"
echo "  Manifest:  $MANIFEST"
echo "  Total manifest audio files: $TOTAL"
echo "  Files this run: $LIMIT"
echo "================================================================"
echo ""

# ── Sample commands ──────────────────────────────────────────────────────────

# Find one traditional and one creative path for sample display.
# SIGPIPE guard: `awk ... exit` closes the read end before printf
# finishes writing all 1128 lines (~50 KB, often larger than the OS
# pipe buffer). That kills printf with SIGPIPE, which pipefail propagates,
# which `set -e` turns fatal. Disable pipefail just for these two lines —
# we don't care about the printf exit status, only awk's match.
set +o pipefail
SAMPLE_TRAD=$(printf '%s\n' "$AUDIO_PATHS" | awk '/^traditional\// { print; exit }')
SAMPLE_CREA=$(printf '%s\n' "$AUDIO_PATHS" | awk '/^creative\// { print; exit }')
set -o pipefail

echo "Sample wrangler commands:"
echo ""
if [ -n "$SAMPLE_TRAD" ]; then
    echo "  Traditional:"
    echo "    wrangler r2 object put \"$BUCKET/$SAMPLE_TRAD\" \\"
    echo "      --file=\"$ASSETS_DIR/$SAMPLE_TRAD\" \\"
    echo "      --content-type=\"audio/mpeg\" --remote"
    echo ""
fi
if [ -n "$SAMPLE_CREA" ]; then
    echo "  Creative:"
    echo "    wrangler r2 object put \"$BUCKET/$SAMPLE_CREA\" \\"
    echo "      --file=\"$ASSETS_DIR/$SAMPLE_CREA\" \\"
    echo "      --content-type=\"audio/mpeg\" --remote"
    echo ""
fi
echo "----------------------------------------------------------------"
echo ""

# ── R2 audit (shared by dry-run and live preflight) ─────────────────────────
# Reads AUDIO_BASE_URL from .env (single source of truth shared with the
# Flutter dotenv loader). Probes every path in parallel against the public
# R2 dev URL. No wrangler auth required for the probe itself.
R2_BASE=$(grep '^AUDIO_BASE_URL=' .env 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"')
if [ -z "$R2_BASE" ]; then
    echo "ERROR: AUDIO_BASE_URL not found in .env — required for R2 audit."
    exit 1
fi

AUDIT_DIR=$(mktemp -d -t r2_audit.XXXXXX)
# cleanup trap set earlier (lock + audit dir together) handles removal

echo "  Auditing $TOTAL paths against $R2_BASE ..."
echo ""

AUDIO_PATHS="$AUDIO_PATHS" R2_BASE="$R2_BASE" ASSETS_DIR="$ASSETS_DIR" AUDIT_DIR="$AUDIT_DIR" python3 - <<'PYEOF'
import json, os, subprocess, sys, time, random
from concurrent.futures import ThreadPoolExecutor

R2_BASE = os.environ["R2_BASE"]
ASSETS_DIR = os.environ["ASSETS_DIR"]
AUDIT_DIR = os.environ["AUDIT_DIR"]
paths = [p for p in os.environ["AUDIO_PATHS"].strip().split("\n") if p]

# Cloudflare's public *.r2.dev URLs are subject to per-source-IP rate
# limits. 8 workers + exponential backoff on 429 keeps us safely
# under the threshold while still finishing ~1000 probes in <2 min.
MAX_WORKERS = 8
MAX_RETRIES = 4

def probe_once(url):
    r = subprocess.run(
        ["curl", "-sI", "-o", "/dev/null", "-w", "%{http_code}", "--max-time", "10", url],
        capture_output=True, text=True,
    )
    return r.stdout.strip()

def classify(rel_path):
    local_file = os.path.join(ASSETS_DIR, rel_path)
    local_ok = os.path.isfile(local_file)
    url = f"{R2_BASE}/{rel_path}"
    code = ""
    for attempt in range(MAX_RETRIES):
        code = probe_once(url)
        if code != "429":
            break
        # Exponential backoff with jitter — 0.5s, 1s, 2s, 4s (plus 0-250ms)
        time.sleep((0.5 * (2 ** attempt)) + random.uniform(0, 0.25))
    if code == "200":
        status = "on_r2"
    elif code == "404":
        status = "absent"
    else:
        status = "error"
    return [rel_path, local_ok, status, code]

with ThreadPoolExecutor(max_workers=MAX_WORKERS) as pool:
    results = list(pool.map(classify, paths))

would_skip   = [r for r in results if r[2] == "on_r2"]
would_upload = [r for r in results if r[2] == "absent" and r[1]]
missing      = [r for r in results if r[2] == "absent" and not r[1]]
failed       = [r for r in results if r[2] == "error"]

# Persist audit for the upload loop + summary to read.
with open(os.path.join(AUDIT_DIR, "audit.json"), "w") as f:
    json.dump({
        "would_upload": [r[0] for r in would_upload],
        "would_skip":   [r[0] for r in would_skip],
        "missing":      [r[0] for r in missing],
        "failed":       [[r[0], r[3]] for r in failed],
        "total":        len(results),
    }, f)

label = "Dry-run R2 audit summary" if os.environ.get("DRY_RUN", "0") == "1" else "Pre-flight R2 audit summary"
print(f"  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"    {label}")
print(f"  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
print(f"    To upload    (local present, R2 missing):   {len(would_upload):>5}")
print(f"    Skip         (already on R2):               {len(would_skip):>5}")
print(f"    Missing      (local absent, cannot upload): {len(missing):>5}")
print(f"    Failed       (probe error, non-200/non-404):{len(failed):>5}")
print(f"    Total manifest audio paths:                 {len(results):>5}")
print(f"  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

def show(label, rows, max_n=5):
    if not rows:
        return
    print()
    print(f"  Sample {label} (first {min(max_n, len(rows))} of {len(rows)}):")
    for r in rows[:max_n]:
        suffix = ""
        if r[3] not in ("200", "404"):
            suffix = f"  [http={r[3]}]"
        print(f"    - {r[0]}{suffix}")

show("TO-UPLOAD paths", would_upload)
show("SKIP paths (already on R2)", would_skip)
show("MISSING-LOCAL paths", missing)
show("FAILED probes", failed)
PYEOF

# Reusable accessors over the audit JSON. python3 -c is cheap here; the file
# is tiny so re-reading per question is fine and keeps the bash side simple.
audit_count() { python3 -c "import json; print(len(json.load(open('$AUDIT_DIR/audit.json'))['$1']))"; }
audit_list()  { python3 -c "import json
for p in json.load(open('$AUDIT_DIR/audit.json'))['$1']:
    print(p)"; }

# Capture audit-derived counters. SKIPPED + MISSING + PROBE_FAILED are
# pre-determined by the audit; UPLOADED + FAILED are filled by the loop below.
SKIPPED=$(audit_count would_skip)
MISSING=$(audit_count missing)
PROBE_FAILED=$(audit_count failed)

# ── Dry-run: stop here, exit non-zero only on probe errors ─────────────────
if [ "${DRY_RUN:-0}" = "1" ]; then
    if [ "$PROBE_FAILED" -gt 0 ]; then exit 1; fi
    exit 0
fi

# ── Live upload: iterate only the to-upload queue from the audit ────────────
TO_UPLOAD_PATHS=$(audit_list would_upload)
UPLOAD_QUEUE_TOTAL=$(audit_count would_upload)

# Honor SMALL_BATCH on the upload queue (not on the full manifest).
if [ "${SMALL_BATCH:-0}" = "1" ]; then
    LIMIT=5
    if [ "$UPLOAD_QUEUE_TOTAL" -lt 5 ]; then LIMIT=$UPLOAD_QUEUE_TOTAL; fi
else
    LIMIT=$UPLOAD_QUEUE_TOTAL
fi

if [ "$UPLOAD_QUEUE_TOTAL" -eq 0 ]; then
    echo ""
    echo "Nothing to upload — every manifest audio path is already on R2."
    if [ "$PROBE_FAILED" -gt 0 ]; then exit 1; fi
    exit 0
fi

echo ""
echo "----------------------------------------------------------------"
echo "Uploading $LIMIT of $UPLOAD_QUEUE_TOTAL needed files..."
echo "----------------------------------------------------------------"

# Sample buffers — first 5 successful + first 5 failed paths
UPLOADED_SAMPLES=()
FAILED_SAMPLES=()
COUNT=0
for rel_path in $TO_UPLOAD_PATHS; do
    COUNT=$((COUNT + 1))
    if [ $COUNT -gt $LIMIT ]; then break; fi
    local_file="$ASSETS_DIR/$rel_path"

    # Defensive: file may have been deleted between audit and upload.
    if [ ! -f "$local_file" ]; then
        echo "  [$COUNT/$LIMIT] MISSING after audit: $rel_path"
        MISSING=$((MISSING + 1))
        continue
    fi

    echo "  [$COUNT/$LIMIT] Uploading: $rel_path"
    if wrangler r2 object put "$BUCKET/$rel_path" --file="$local_file" --content-type="audio/mpeg" --remote 2>&1; then
        UPLOADED=$((UPLOADED + 1))
        if [ "${#UPLOADED_SAMPLES[@]}" -lt 5 ]; then
            UPLOADED_SAMPLES+=("$rel_path")
        fi
    else
        FAILED=$((FAILED + 1))
        echo "  [$COUNT/$LIMIT] FAILED: $rel_path"
        if [ "${#FAILED_SAMPLES[@]}" -lt 5 ]; then
            FAILED_SAMPLES+=("$rel_path")
        fi
    fi
done

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
echo "================================================================"
echo "  Summary"
echo "================================================================"
echo "  Uploaded:      $UPLOADED"
echo "  Skipped:       $SKIPPED   (already on R2 before this run)"
echo "  Missing local: $MISSING"
echo "  Failed:        $FAILED   (wrangler upload errors)"
if [ "$PROBE_FAILED" -gt 0 ]; then
    echo "  Probe errors:  $PROBE_FAILED   (R2 audit could not classify; skipped this run)"
fi
echo "================================================================"

# macOS ships bash 3.2 — `${arr[@]}` on an empty array under `set -u`
# fails with "unbound variable". Guard with length checks and only
# expand when non-empty.
if [ "${#UPLOADED_SAMPLES[@]}" -gt 0 ]; then
    echo ""
    echo "  Sample UPLOADED paths (first ${#UPLOADED_SAMPLES[@]}):"
    for p in "${UPLOADED_SAMPLES[@]}"; do
        echo "    - $p"
    done
fi
if [ "${#FAILED_SAMPLES[@]}" -gt 0 ]; then
    echo ""
    echo "  Sample FAILED paths (first ${#FAILED_SAMPLES[@]}):"
    for p in "${FAILED_SAMPLES[@]}"; do
        echo "    - $p"
    done
fi

# Echo the audit's skipped/missing samples too so the final summary is
# self-contained (no need to scroll back to the pre-flight section).
python3 - <<PYEOF
import json
a = json.load(open("$AUDIT_DIR/audit.json"))
def show(label, items, max_n=5):
    if not items: return
    print()
    print(f"  Sample {label} (first {min(max_n, len(items))}):")
    for p in items[:max_n]:
        if isinstance(p, list):
            print(f"    - {p[0]}  [http={p[1]}]")
        else:
            print(f"    - {p}")
show("SKIPPED paths (already on R2)", a["would_skip"])
show("MISSING-LOCAL paths", a["missing"])
show("PROBE-FAILED paths", a["failed"])
PYEOF

if [ $FAILED -gt 0 ] || [ "$PROBE_FAILED" -gt 0 ]; then
    exit 1
fi

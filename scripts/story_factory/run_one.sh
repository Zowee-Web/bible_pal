#!/usr/bin/env bash
# run_one.sh — Thin wrapper for generate_traditional_story.py
# Usage: ./scripts/story_factory/run_one.sh --story_id 803 --anchor "Psalm 46" ...
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

START=$(date +%s)

set +e
python3 "$SCRIPT_DIR/generate_traditional_story.py" "$@"
EXIT_CODE=$?
set -e

END=$(date +%s)
ELAPSED=$((END - START))
echo ""
echo "Elapsed: ${ELAPSED}s"
exit $EXIT_CODE

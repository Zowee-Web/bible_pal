#!/usr/bin/env bash
# nightly_generate.sh - Nightly batch automation for Bible PAL
# SPEC.md Feature #7: Automated script runs at 2:00 AM daily
#
# Generates ~20 new parables per night across mixed moods and lengths.
# Calls generate_batch_parables.sh multiple times, cycling through moods.
#
# Usage:
#   ./server/nightly_generate.sh          # Normal run
#   DRY_RUN=1 ./server/nightly_generate.sh  # Preview without generating

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
LOG_FILE="$LOG_DIR/nightly_$(date +%Y%m%d_%H%M%S).log"
STATE_FILE="$SCRIPT_DIR/.nightly_state"
DRY_RUN="${DRY_RUN:-0}"

mkdir -p "$LOG_DIR"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log "=== Bible PAL Nightly Generation ==="
log "Script: $0"
log "Dry run: $DRY_RUN"

# Load state from previous run (batch number + mood offset)
if [[ -f "$STATE_FILE" ]]; then
    BATCH_NUM=$(jq -r '.batch_num // 100' "$STATE_FILE" 2>/dev/null || echo 100)
    MOOD_OFFSET=$(jq -r '.mood_offset // 0' "$STATE_FILE" 2>/dev/null || echo 0)
else
    BATCH_NUM=100
    MOOD_OFFSET=0
fi

log "Starting batch: $BATCH_NUM, mood offset: $MOOD_OFFSET"

# Mood rotation (matches SPEC.md mood categories)
MOODS=("joyful" "weary" "anxious" "hurting" "neutral" "encouraging" "calm_peaceful" "brave_courage")
TOTAL_MOODS=${#MOODS[@]}

STORIES_GENERATED=0
TARGET=20
FAILURES=0
MOOD_IDX=$MOOD_OFFSET

# Each batch call generates 3 stories (5min, 10min, 15min)
# 7 calls * 3 = 21 stories (≥ 20 target)
MAX_BATCHES=7

for ((i = 0; i < MAX_BATCHES; i++)); do
    CURRENT_MOOD_IDX=$((MOOD_IDX % TOTAL_MOODS))
    CURRENT_MOOD="${MOODS[$CURRENT_MOOD_IDX]}"

    log "Batch $BATCH_NUM: mood=$CURRENT_MOOD (index=$CURRENT_MOOD_IDX)"

    if [[ "$DRY_RUN" == "1" ]]; then
        log "  [DRY RUN] Would generate 3 stories"
        STORIES_GENERATED=$((STORIES_GENERATED + 3))
    else
        if "$SCRIPT_DIR/generate_batch_parables.sh" "$BATCH_NUM" "$CURRENT_MOOD_IDX" >> "$LOG_FILE" 2>&1; then
            STORIES_GENERATED=$((STORIES_GENERATED + 3))
            log "  OK: 3 stories generated (total: $STORIES_GENERATED)"
        else
            FAILURES=$((FAILURES + 1))
            log "  FAIL: Batch $BATCH_NUM failed for mood $CURRENT_MOOD"
        fi
    fi

    BATCH_NUM=$((BATCH_NUM + 1))
    MOOD_IDX=$((MOOD_IDX + 1))

    # Brief pause between batches to avoid overwhelming Ollama/ElevenLabs
    if [[ "$DRY_RUN" != "1" ]] && ((i < MAX_BATCHES - 1)); then
        sleep 5
    fi
done

# Save state for next run
jq -n \
    --argjson batch_num "$BATCH_NUM" \
    --argjson mood_offset "$((MOOD_IDX % TOTAL_MOODS))" \
    '{batch_num: $batch_num, mood_offset: $mood_offset}' > "$STATE_FILE"

log ""
log "=== Summary ==="
log "Stories generated: $STORIES_GENERATED"
log "Failures: $FAILURES"
log "Next batch: $BATCH_NUM, next mood offset: $((MOOD_IDX % TOTAL_MOODS))"
log "State saved to: $STATE_FILE"
log "=== Done ==="

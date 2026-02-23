#!/bin/bash
# generate_pal_audio_batch.sh
# Pre-renders ALL PAL conversation audio (greetings + compassionate replies + preview)
# for all 4 PAL voices using ElevenLabs API.
#
# CRITICAL: This is a SERVER-SIDE script. The generated MP3s ship as bundled assets.
# The mobile app NEVER calls ElevenLabs at runtime.
#
# Usage: AUDIO_ENABLED=1 ./server/generate_pal_audio_batch.sh
#
# Onboarding audio (onboard_01) is rendered ONLY for the default voice (VOICE_SARAH_STORYTELLER).
# All other lines are rendered for all 4 voices.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
VOICES_FILE="$SCRIPT_DIR/voices.json"
PAL_LINES_FILE="$PROJECT_ROOT/assets/pal/pal_lines.json"
OUTPUT_BASE="$PROJECT_ROOT/assets/pal/audio"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Source ElevenLabs safety guard
source "$SCRIPT_DIR/elevenlabs_guard.sh"
trap elevenlabs_release_lock EXIT INT TERM

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}Error: jq required${NC}" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}Error: curl required${NC}" >&2; exit 1; }

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}Error: .env not found at $ENV_FILE${NC}" >&2
    exit 1
fi

while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    export "$key=$value"
done < "$ENV_FILE"

if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}Error: ELEVENLABS_API_KEY not found in .env${NC}" >&2
    exit 1
fi

# Validate input files
if [[ ! -f "$VOICES_FILE" ]]; then
    echo -e "${RED}Error: voices.json not found at $VOICES_FILE${NC}" >&2
    exit 1
fi

if [[ ! -f "$PAL_LINES_FILE" ]]; then
    echo -e "${RED}Error: pal_lines.json not found at $PAL_LINES_FILE${NC}" >&2
    exit 1
fi

# PAL voice keys (must match pal_voice_registry.dart)
PAL_VOICES=(
    "VOICE_SARAH_STORYTELLER"
    "VOICE_HANNAH_HOPE"
    "VOICE_JAMES_HUSKY"
    "VOICE_DAVID_SHEPHERD"
)
DEFAULT_VOICE="VOICE_SARAH_STORYTELLER"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Bible PAL - Batch PAL Voice Audio Generation${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Resolve ElevenLabs IDs from voices.json
resolve_voice_id() {
    local voice_key="$1"
    local el_id
    el_id=$(jq -r --arg key "$voice_key" '.voices[] | select(.voiceKey == $key) | .elevenLabsId' "$VOICES_FILE")
    if [[ -z "$el_id" || "$el_id" == "null" ]]; then
        echo -e "${RED}Error: Voice key '$voice_key' not found in voices.json${NC}" >&2
        exit 1
    fi
    echo "$el_id"
}

# Collect all lines from pal_lines.json
# Returns: line_id\ttext pairs
collect_lines() {
    local category="$1"
    case "$category" in
        onboarding)
            jq -r '.onboarding[] | "\(.id)\t\(.text)"' "$PAL_LINES_FILE"
            ;;
        preview)
            jq -r '.preview[] | "\(.id)\t\(.text)"' "$PAL_LINES_FILE"
            ;;
        greetings)
            jq -r '.greetings[] | "\(.id)\t\(.text)"' "$PAL_LINES_FILE"
            ;;
        positive)
            jq -r '.compassionateReplies.positive[] | "\(.id)\t\(.text)"' "$PAL_LINES_FILE"
            ;;
        neutral)
            jq -r '.compassionateReplies.neutral[] | "\(.id)\t\(.text)"' "$PAL_LINES_FILE"
            ;;
        negative)
            jq -r '.compassionateReplies.negative[] | "\(.id)\t\(.text)"' "$PAL_LINES_FILE"
            ;;
    esac
}

# Generate one audio file
# Args: voice_key eleven_labs_id line_id text
generate_one() {
    local voice_key="$1"
    local el_id="$2"
    local line_id="$3"
    local text="$4"
    local output_dir="$OUTPUT_BASE/$voice_key"
    local output_file="$output_dir/${line_id}.mp3"

    # Skip if already exists (unless FORCE_REGEN=1)
    if [[ -f "$output_file" && -s "$output_file" && "${FORCE_REGEN:-0}" != "1" ]]; then
        echo -e "  ${GREEN}skip${NC} $voice_key/$line_id.mp3 (exists)"
        return 0
    fi

    mkdir -p "$output_dir"

    local char_count
    char_count=$(printf "%s" "$text" | wc -c | tr -d ' ')

    # Use elevenlabs_guard for safety (PAL lines are short, use 5min tier)
    if elevenlabs_check_and_log "pal_${voice_key}_${line_id}" "$char_count" "5"; then
        local http_code
        http_code=$(elevenlabs_call "$text" "$output_file" "$el_id" "$ELEVENLABS_API_KEY")

        if [[ "$http_code" == "200" && -s "$output_file" ]]; then
            local file_size
            file_size=$(ls -lh "$output_file" | awk '{print $5}')
            echo -e "  ${GREEN}done${NC} $voice_key/$line_id.mp3 ($file_size)"
            return 0
        else
            echo -e "  ${RED}FAIL${NC} $voice_key/$line_id.mp3 (HTTP $http_code)"
            rm -f "$output_file"
            return 1
        fi
    else
        echo -e "  ${YELLOW}BLOCKED${NC} $voice_key/$line_id.mp3 (safety guard)"
        return 1
    fi
}

# Count lines for progress
GREETING_COUNT=$(jq '.greetings | length' "$PAL_LINES_FILE")
PREVIEW_COUNT=$(jq '.preview | length' "$PAL_LINES_FILE")
POS_COUNT=$(jq '.compassionateReplies.positive | length' "$PAL_LINES_FILE")
NEU_COUNT=$(jq '.compassionateReplies.neutral | length' "$PAL_LINES_FILE")
NEG_COUNT=$(jq '.compassionateReplies.negative | length' "$PAL_LINES_FILE")
ONBOARD_COUNT=$(jq '.onboarding | length' "$PAL_LINES_FILE")
LINES_PER_VOICE=$((PREVIEW_COUNT + GREETING_COUNT + POS_COUNT + NEU_COUNT + NEG_COUNT))
TOTAL_FILES=$(( (LINES_PER_VOICE * ${#PAL_VOICES[@]}) + ONBOARD_COUNT ))

echo -e "Lines per voice: ${CYAN}$LINES_PER_VOICE${NC} (preview: $PREVIEW_COUNT, greetings: $GREETING_COUNT, replies: $((POS_COUNT + NEU_COUNT + NEG_COUNT)))"
echo -e "Onboarding lines: ${CYAN}$ONBOARD_COUNT${NC} (default voice only)"
echo -e "Voices: ${CYAN}${#PAL_VOICES[@]}${NC}"
echo -e "Total files: ${CYAN}$TOTAL_FILES${NC}"
echo ""

SUCCESS=0
FAILURES=0
SKIPPED=0

for voice_key in "${PAL_VOICES[@]}"; do
    el_id=$(resolve_voice_id "$voice_key")
    echo -e "${BLUE}Voice: $voice_key${NC} ($el_id)"

    # Onboarding: only for default voice
    if [[ "$voice_key" == "$DEFAULT_VOICE" ]]; then
        echo -e "  ${CYAN}[onboarding]${NC}"
        while IFS=$'\t' read -r line_id text; do
            if generate_one "$voice_key" "$el_id" "$line_id" "$text"; then
                SUCCESS=$((SUCCESS + 1))
            else
                FAILURES=$((FAILURES + 1))
            fi
        done < <(collect_lines "onboarding")
    fi

    # Preview
    echo -e "  ${CYAN}[preview]${NC}"
    while IFS=$'\t' read -r line_id text; do
        if generate_one "$voice_key" "$el_id" "$line_id" "$text"; then
            SUCCESS=$((SUCCESS + 1))
        else
            FAILURES=$((FAILURES + 1))
        fi
    done < <(collect_lines "preview")

    # Greetings
    echo -e "  ${CYAN}[greetings]${NC}"
    while IFS=$'\t' read -r line_id text; do
        if generate_one "$voice_key" "$el_id" "$line_id" "$text"; then
            SUCCESS=$((SUCCESS + 1))
        else
            FAILURES=$((FAILURES + 1))
        fi
    done < <(collect_lines "greetings")

    # Compassionate replies
    for bucket in positive neutral negative; do
        echo -e "  ${CYAN}[compassionate: $bucket]${NC}"
        while IFS=$'\t' read -r line_id text; do
            if generate_one "$voice_key" "$el_id" "$line_id" "$text"; then
                SUCCESS=$((SUCCESS + 1))
            else
                FAILURES=$((FAILURES + 1))
            fi
        done < <(collect_lines "$bucket")
    done

    echo ""
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Results: ${GREEN}$SUCCESS generated${NC}, ${RED}$FAILURES failed${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Fail hard if any files are missing
if [[ $FAILURES -gt 0 ]]; then
    echo -e "${RED}ERROR: $FAILURES files failed to generate. Fix errors and re-run.${NC}" >&2
    exit 1
fi

# Final validation: check all expected files exist
echo ""
echo -e "${BLUE}Validating all expected files...${NC}"
MISSING=0
for voice_key in "${PAL_VOICES[@]}"; do
    # Preview
    while IFS=$'\t' read -r line_id _; do
        if [[ ! -s "$OUTPUT_BASE/$voice_key/${line_id}.mp3" ]]; then
            echo -e "  ${RED}MISSING${NC} $voice_key/${line_id}.mp3"
            MISSING=$((MISSING + 1))
        fi
    done < <(collect_lines "preview")

    # Greetings
    while IFS=$'\t' read -r line_id _; do
        if [[ ! -s "$OUTPUT_BASE/$voice_key/${line_id}.mp3" ]]; then
            echo -e "  ${RED}MISSING${NC} $voice_key/${line_id}.mp3"
            MISSING=$((MISSING + 1))
        fi
    done < <(collect_lines "greetings")

    # Replies
    for bucket in positive neutral negative; do
        while IFS=$'\t' read -r line_id _; do
            if [[ ! -s "$OUTPUT_BASE/$voice_key/${line_id}.mp3" ]]; then
                echo -e "  ${RED}MISSING${NC} $voice_key/${line_id}.mp3"
                MISSING=$((MISSING + 1))
            fi
        done < <(collect_lines "$bucket")
    done
done

# Onboarding (default voice only)
while IFS=$'\t' read -r line_id _; do
    if [[ ! -s "$OUTPUT_BASE/$DEFAULT_VOICE/${line_id}.mp3" ]]; then
        echo -e "  ${RED}MISSING${NC} $DEFAULT_VOICE/${line_id}.mp3"
        MISSING=$((MISSING + 1))
    fi
done < <(collect_lines "onboarding")

if [[ $MISSING -gt 0 ]]; then
    echo -e "${RED}ERROR: $MISSING expected files are missing or empty.${NC}" >&2
    exit 1
fi

echo -e "${GREEN}All $TOTAL_FILES audio files present and non-empty.${NC}"
echo ""
echo -e "${GREEN}Done! Assets are ready at: assets/pal/audio/${NC}"

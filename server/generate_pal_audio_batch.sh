#!/bin/bash
# generate_pal_audio_batch.sh
# Pre-renders ALL PAL conversation audio (prompts + micro-responses + preview + onboarding)
# for all 4 PAL voices using ElevenLabs API with Eleven v3 engine.
#
# CRITICAL: This is a SERVER-SIDE script. The generated MP3s ship as bundled assets.
# The mobile app NEVER calls ElevenLabs at runtime.
#
# Usage: AUDIO_ENABLED=1 ./server/generate_pal_audio_batch.sh
#        AUDIO_ENABLED=1 FORCE_REGEN=1 ./server/generate_pal_audio_batch.sh
#
# Onboarding audio (onboard_01) is rendered ONLY for the default voice (VOICE_GRACE).
# All other lines are rendered for all 4 voices.
#
# pal_lines.json v2 structure:
#   prompts:        16 buckets (4 time windows × 4 categories) × 6 lines = 96
#   microResponses: 5 mood buckets × 6 lines = 30
#   preview:        1 line
#   onboarding:     1 line (default voice only)
#
# Expected total: (96 + 30 + 1) × 4 voices + 1 onboarding = 509 files

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

# Validate pal_lines.json is v2
PAL_VERSION=$(jq '.version // 0' "$PAL_LINES_FILE")
if [[ "$PAL_VERSION" != "2" ]]; then
    echo -e "${RED}Error: pal_lines.json version is $PAL_VERSION, expected 2${NC}" >&2
    exit 1
fi

# PAL voice keys (must match pal_voice_registry.dart)
PAL_VOICES=(
    "VOICE_GRACE"
    "VOICE_SHEPHERD"
    "VOICE_HOPE"
    "VOICE_STILLWATER"
)
DEFAULT_VOICE="VOICE_GRACE"

# ElevenLabs model for PAL audio (v3 engine)
PAL_MODEL_ID="eleven_v3"

# Prompt bucket keys (4 time windows × 4 categories = 16 buckets)
PROMPT_BUCKETS=(
    "morning_day" "morning_heart" "morning_burden" "morning_gratitude"
    "afternoon_day" "afternoon_heart" "afternoon_burden" "afternoon_gratitude"
    "evening_day" "evening_heart" "evening_burden" "evening_gratitude"
    "lateNight_day" "lateNight_heart" "lateNight_burden" "lateNight_gratitude"
)

# Micro-response mood keys
MICRO_MOODS=("joyful" "weary" "anxious" "hurting" "neutral")

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Bible PAL - Batch PAL Voice Audio Generation (v2)${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Model: ${BLUE}$PAL_MODEL_ID${NC}"
echo ""

# Resolve ElevenLabs IDs from voices.json palVoices section
resolve_voice_id() {
    local voice_key="$1"
    local el_id
    el_id=$(jq -r --arg key "$voice_key" '.palVoices[] | select(.voiceKey == $key) | .elevenLabsId' "$VOICES_FILE")
    if [[ -z "$el_id" || "$el_id" == "null" ]]; then
        echo -e "${RED}Error: Voice key '$voice_key' not found in voices.json palVoices${NC}" >&2
        exit 1
    fi
    echo "$el_id"
}

# Format text for speech: trim whitespace, collapse repeated spaces,
# preserve commas, periods, ellipses, em dashes (these aid cadence).
format_text_for_speech() {
    local text="$1"
    # Trim leading/trailing whitespace
    text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    # Collapse repeated spaces
    text=$(echo "$text" | tr -s ' ')
    echo "$text"
}

# Collect lines from pal_lines.json v2
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
        prompt_*)
            local bucket="${category#prompt_}"
            jq -r --arg b "$bucket" '.prompts[$b][] | "\(.id)\t\(.text)"' "$PAL_LINES_FILE"
            ;;
        micro_*)
            local mood="${category#micro_}"
            jq -r --arg m "$mood" '.microResponses[$m][] | "\(.id)\t\(.text)"' "$PAL_LINES_FILE"
            ;;
        *)
            echo -e "${RED}Error: Unknown category '$category'${NC}" >&2
            exit 1
            ;;
    esac
}

# Generate one audio file using PAL-specific voice settings + Eleven v3
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

    # Format text for speech
    text=$(format_text_for_speech "$text")

    local char_count
    char_count=$(printf "%s" "$text" | wc -c | tr -d ' ')

    # Use elevenlabs_guard for safety (PAL lines are short, use 5min tier)
    if elevenlabs_check_and_log "pal_${voice_key}_${line_id}" "$char_count" "5"; then
        # Build PAL-specific JSON payload with v3 model + PAL voice settings
        local json_payload
        json_payload=$(jq -n --arg text "$text" --arg model "$PAL_MODEL_ID" '{
            text: $text,
            model_id: $model,
            voice_settings: {
                stability: 0.35,
                similarity_boost: 0.75,
                style: 0.40,
                use_speaker_boost: true
            }
        }')

        echo -e "${BLUE}→ Calling ElevenLabs API (model: $PAL_MODEL_ID)...${NC}" >&2

        local http_code
        local curl_exit
        http_code=$(curl -sS \
            --connect-timeout 10 \
            --max-time 120 \
            -w "%{http_code}" \
            -o "$output_file" \
            -X POST \
            "https://api.elevenlabs.io/v1/text-to-speech/${el_id}" \
            -H "xi-api-key: $ELEVENLABS_API_KEY" \
            -H "Content-Type: application/json" \
            -d "$json_payload" 2>&1) || curl_exit=$?

        # Release lock
        rmdir "$GUARD_LOCK_DIR" 2>/dev/null || true

        # Check curl exit code first
        if [[ -n "${curl_exit:-}" && "$curl_exit" -ne 0 ]]; then
            echo -e "  ${RED}FAIL${NC} $voice_key/$line_id.mp3 (curl exit: $curl_exit)"
            rm -f "$output_file"
            return 1
        fi

        if [[ "$http_code" == "200" && -s "$output_file" ]]; then
            local file_size
            file_size=$(ls -lh "$output_file" | awk '{print $5}')
            echo -e "  ${GREEN}done${NC} $voice_key/$line_id.mp3 ($file_size)"
            CHARS_USED=$((CHARS_USED + char_count))
            return 0
        else
            echo -e "  ${RED}FAIL${NC} $voice_key/$line_id.mp3 (HTTP $http_code)"
            # Print error detail if available
            if [[ -f "$output_file" ]]; then
                local error_msg
                error_msg=$(jq -r '.detail.message // .detail // .message // empty' < "$output_file" 2>/dev/null || true)
                if [[ -n "$error_msg" ]]; then
                    echo -e "  ${RED}  Detail: $error_msg${NC}"
                fi
            fi
            rm -f "$output_file"
            return 1
        fi
    else
        echo -e "  ${YELLOW}BLOCKED${NC} $voice_key/$line_id.mp3 (safety guard)"
        return 1
    fi
}

# Count lines for progress
PROMPT_COUNT=$(jq '[.prompts | to_entries[] | .value | length] | add' "$PAL_LINES_FILE")
MICRO_COUNT=$(jq '[.microResponses | to_entries[] | .value | length] | add' "$PAL_LINES_FILE")
PREVIEW_COUNT=$(jq '.preview | length' "$PAL_LINES_FILE")
ONBOARD_COUNT=$(jq '.onboarding | length' "$PAL_LINES_FILE")
LINES_PER_VOICE=$((PREVIEW_COUNT + PROMPT_COUNT + MICRO_COUNT))
TOTAL_FILES=$(( (LINES_PER_VOICE * ${#PAL_VOICES[@]}) + ONBOARD_COUNT ))

echo -e "Lines per voice: ${CYAN}$LINES_PER_VOICE${NC} (preview: $PREVIEW_COUNT, prompts: $PROMPT_COUNT, micro-responses: $MICRO_COUNT)"
echo -e "Onboarding lines: ${CYAN}$ONBOARD_COUNT${NC} (default voice only)"
echo -e "Voices: ${CYAN}${#PAL_VOICES[@]}${NC} (${PAL_VOICES[*]})"
echo -e "Total files: ${CYAN}$TOTAL_FILES${NC}"
echo ""

SUCCESS=0
FAILURES=0
CHARS_USED=0

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

    # Prompts (16 buckets)
    for bucket in "${PROMPT_BUCKETS[@]}"; do
        echo -e "  ${CYAN}[prompt: $bucket]${NC}"
        while IFS=$'\t' read -r line_id text; do
            if generate_one "$voice_key" "$el_id" "$line_id" "$text"; then
                SUCCESS=$((SUCCESS + 1))
            else
                FAILURES=$((FAILURES + 1))
            fi
        done < <(collect_lines "prompt_$bucket")
    done

    # Micro-responses (5 mood buckets)
    for mood in "${MICRO_MOODS[@]}"; do
        echo -e "  ${CYAN}[micro-response: $mood]${NC}"
        while IFS=$'\t' read -r line_id text; do
            if generate_one "$voice_key" "$el_id" "$line_id" "$text"; then
                SUCCESS=$((SUCCESS + 1))
            else
                FAILURES=$((FAILURES + 1))
            fi
        done < <(collect_lines "micro_$mood")
    done

    echo ""
done

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Results: ${GREEN}$SUCCESS generated${NC}, ${RED}$FAILURES failed${NC}"
echo -e "Credits consumed: ${CYAN}~$CHARS_USED characters${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# Fail hard if any files failed
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

    # Prompts
    for bucket in "${PROMPT_BUCKETS[@]}"; do
        while IFS=$'\t' read -r line_id _; do
            if [[ ! -s "$OUTPUT_BASE/$voice_key/${line_id}.mp3" ]]; then
                echo -e "  ${RED}MISSING${NC} $voice_key/${line_id}.mp3"
                MISSING=$((MISSING + 1))
            fi
        done < <(collect_lines "prompt_$bucket")
    done

    # Micro-responses
    for mood in "${MICRO_MOODS[@]}"; do
        while IFS=$'\t' read -r line_id _; do
            if [[ ! -s "$OUTPUT_BASE/$voice_key/${line_id}.mp3" ]]; then
                echo -e "  ${RED}MISSING${NC} $voice_key/${line_id}.mp3"
                MISSING=$((MISSING + 1))
            fi
        done < <(collect_lines "micro_$mood")
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
echo -e "  Model: $PAL_MODEL_ID"
echo -e "  Credits: ~$CHARS_USED characters"

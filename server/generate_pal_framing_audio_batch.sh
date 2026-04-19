#!/bin/bash
# generate_pal_framing_audio_batch.sh
# Pre-renders all PAL framing overlay + opening line audio for all 4 PAL voices.
#
# CRITICAL: This is a SERVER-SIDE script. The generated MP3s ship as bundled assets.
# The mobile app NEVER calls ElevenLabs at runtime.
#
# Usage: AUDIO_ENABLED=1 ./server/generate_pal_framing_audio_batch.sh
#        AUDIO_ENABLED=1 FORCE_REGEN=1 ./server/generate_pal_framing_audio_batch.sh
#
# Line pools and expected totals (per voice):
#   Opening lines:              60  (from pal_opening_lines.dart)
#   Reflection lines:           32  (from pal_reflection_lines.json)
#   Tone-biased reflection:    120  (from pal_tone_biased_reflection_lines.json)
#   Framing lines:              92  (from biblical_figure_registry.json)
#   Transition lines:           12  (from pal_transition_lines.json)
#   ─────────────────────────────────
#   Per voice:                 316
#   Total (4 voices):        1,264 MP3 files
#
# Asset output: assets/pal/audio/{voiceKey}/{lineId}.mp3
# Same directory structure as existing PAL prompt/micro-response audio.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
VOICES_FILE="$SCRIPT_DIR/voices.json"
OUTPUT_BASE="$PROJECT_ROOT/assets/pal/audio"

# JSON source files
REFLECTION_FILE="$PROJECT_ROOT/assets/pal/pal_reflection_lines.json"
TONE_BIASED_FILE="$PROJECT_ROOT/assets/pal/pal_tone_biased_reflection_lines.json"
TRANSITION_FILE="$PROJECT_ROOT/assets/pal/pal_transition_lines.json"
FRAMING_FILE="$PROJECT_ROOT/assets/stories/biblical_figure_registry.json"
CREATIVE_FILE="$PROJECT_ROOT/assets/pal/creative_opening_lines.json"
# Opening lines are Dart const — we extract from the manifest below.
OPENING_MANIFEST="$SCRIPT_DIR/pal_opening_lines_manifest.json"

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
for f in "$VOICES_FILE" "$REFLECTION_FILE" "$TONE_BIASED_FILE" "$TRANSITION_FILE" "$FRAMING_FILE" "$CREATIVE_FILE"; do
    if [[ ! -f "$f" ]]; then
        echo -e "${RED}Error: Required file not found: $f${NC}" >&2
        exit 1
    fi
done

if [[ ! -f "$OPENING_MANIFEST" ]]; then
    echo -e "${YELLOW}Warning: $OPENING_MANIFEST not found.${NC}"
    echo -e "${YELLOW}Run: dart run server/extract_opening_lines.dart to generate it.${NC}"
    echo -e "${YELLOW}Opening lines will be skipped.${NC}"
    SKIP_OPENING=1
else
    SKIP_OPENING=0
fi

# PAL voice keys
PAL_VOICES=(
    "VOICE_GRACE"
    "VOICE_SHEPHERD"
    "VOICE_HOPE"
    "VOICE_STILLWATER"
)

# ElevenLabs model for PAL audio (v3 engine, same as existing PAL audio)
# PAL audio standard: eleven_v3 (premium voice experience).
# Story audio uses eleven_turbo_v2_5 separately. Do not mix.
PAL_MODEL_ID="eleven_v3"

echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}  Bible PAL - Framing Overlay Audio Generation${NC}"
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

format_text_for_speech() {
    local text="$1"
    text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    text=$(echo "$text" | tr -s ' ')
    echo "$text"
}

# Collect id\ttext pairs from each source
collect_reflection_lines() {
    jq -r '.moods | to_entries[] | .value[] | "\(.id)\t\(.text)"' "$REFLECTION_FILE"
}

collect_tone_biased_lines() {
    jq -r '.moods | to_entries[] | .value | to_entries[] | .value[] | "\(.id)\t\(.text)"' "$TONE_BIASED_FILE"
}

collect_transition_lines() {
    jq -r '.lines[] | "\(.id)\t\(.text)"' "$TRANSITION_FILE"
}

collect_framing_lines() {
    jq -r '.entries[] | .framingLines[] | "\(.id)\t\(.text)"' "$FRAMING_FILE"
}

collect_creative_lines() {
    jq -r '.moods | to_entries[] | .value[] | "\(.id)\t\(.text)"' "$CREATIVE_FILE"
}

collect_opening_lines() {
    if [[ "$SKIP_OPENING" == "1" ]]; then
        return
    fi
    jq -r '.lines[] | "\(.id)\t\(.text)"' "$OPENING_MANIFEST"
}

# Generate one audio file (same pattern as generate_pal_audio_batch.sh)
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
    text=$(format_text_for_speech "$text")

    local char_count
    char_count=$(printf "%s" "$text" | wc -c | tr -d ' ')

    if elevenlabs_check_and_log "pal_framing_${voice_key}_${line_id}" "$char_count" "5"; then
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

        rmdir "$GUARD_LOCK_DIR" 2>/dev/null || true

        if [[ -n "${curl_exit:-}" && "$curl_exit" -ne 0 ]]; then
            echo -e "  ${RED}FAIL${NC} $voice_key/$line_id.mp3 (curl error $curl_exit)"
            rm -f "$output_file"
            return 1
        fi

        if [[ "$http_code" == "200" && -s "$output_file" ]]; then
            echo -e "  ${GREEN}done${NC} $voice_key/$line_id.mp3 (${char_count} chars)"
        else
            echo -e "  ${RED}FAIL${NC} $voice_key/$line_id.mp3 (HTTP $http_code)"
            rm -f "$output_file"
            return 1
        fi
    else
        echo -e "  ${YELLOW}GUARD${NC} $voice_key/$line_id.mp3 (rate limited)"
        return 1
    fi
}

# Main loop
TOTAL=0
GENERATED=0
SKIPPED=0
FAILED=0

for voice_key in "${PAL_VOICES[@]}"; do
    el_id=$(resolve_voice_id "$voice_key")
    echo -e "\n${CYAN}Voice: $voice_key${NC} (${el_id:0:8}...)"

    for category in opening reflection tone_biased transition framing creative; do
        echo -e "  ${BLUE}[$category]${NC}"

        lines=""
        case "$category" in
            opening)     lines=$(collect_opening_lines) ;;
            reflection)  lines=$(collect_reflection_lines) ;;
            tone_biased) lines=$(collect_tone_biased_lines) ;;
            transition)  lines=$(collect_transition_lines) ;;
            framing)     lines=$(collect_framing_lines) ;;
            creative)    lines=$(collect_creative_lines) ;;
        esac

        if [[ -z "$lines" ]]; then
            echo -e "    ${YELLOW}(no lines)${NC}"
            continue
        fi

        while IFS=$'\t' read -r line_id text; do
            ((TOTAL++))
            if generate_one "$voice_key" "$el_id" "$line_id" "$text"; then
                if [[ -f "$OUTPUT_BASE/$voice_key/${line_id}.mp3" ]]; then
                    ((SKIPPED++))
                else
                    ((GENERATED++))
                fi
            else
                ((FAILED++))
            fi
        done <<< "$lines"
    done
done

echo -e "\n${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "  Total: ${TOTAL}  Generated: ${GENERATED}  Skipped: ${SKIPPED}  Failed: ${FAILED}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

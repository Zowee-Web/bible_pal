#!/usr/bin/env bash
# =============================================================================
# generate_opus_audio.sh — ElevenLabs TTS for Opus 4.6 stories
# =============================================================================
# Generates audio for short + full lengths only (no longs).
# Reads voice assignments from meta JSON files.
# Idempotent: skips files that already exist.
#
# USAGE:
#   ./scripts/generate_opus_audio.sh [OPTIONS]
#
# OPTIONS:
#   --dry-run       Show what would be generated without calling the API
#   --story ID      Generate audio for a single story ID only
#   --retry-file F  Retry only the files listed in F (one path per line)
#
# REQUIRES:
#   - .env with ELEVENLABS_API_KEY
#   - jq installed
#   - server/voices.json (for voice ID lookup)
# =============================================================================

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
VOICES_FILE="$PROJECT_ROOT/server/voices.json"
STORIES_DIR="$PROJECT_ROOT/assets/stories"
FAILURES_FILE="$PROJECT_ROOT/assets/stories/.audio_failures.log"

# TTS settings (locked — matches production)
ELEVENLABS_MODEL="eleven_turbo_v2_5"
ELEVENLABS_STABILITY="0.6"
ELEVENLABS_SIMILARITY="0.8"
ELEVENLABS_STYLE="0.0"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Counters
GENERATED=0
SKIPPED=0
RETRIED=0
FAILED=0

# Options
DRY_RUN=false
SINGLE_STORY=""
RETRY_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    DRY_RUN=true; shift ;;
        --story)      SINGLE_STORY="$2"; shift 2 ;;
        --retry-file) RETRY_FILE="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Load environment
if [[ -f "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    source "$ENV_FILE"
fi

if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}FATAL: ELEVENLABS_API_KEY not set in .env${NC}"
    exit 1
fi

if [[ ! -f "$VOICES_FILE" ]]; then
    echo -e "${RED}FATAL: voices.json not found at $VOICES_FILE${NC}"
    exit 1
fi

# Clear failures log
> "$FAILURES_FILE"

# =============================================================================
# Voice ID lookup
# =============================================================================
get_voice_id() {
    local voice_key="$1"
    local id
    id=$(jq -r --arg key "$voice_key" \
        '.voices[] | select(.voiceKey == $key) | .elevenLabsId' \
        "$VOICES_FILE")
    # If voices.json uses an env-placeholder (_LOAD_FROM_ENV_VOICE_X), resolve
    # the actual ElevenLabs ID from the .env-sourced shell variable.
    if [[ "$id" == _LOAD_FROM_ENV_* ]]; then
        local env_key="${id#_LOAD_FROM_ENV_}"
        id=$(eval "echo \"\${$env_key:-}\"")
    fi
    echo "$id"
}

# =============================================================================
# TTS generation
# =============================================================================
generate_audio() {
    local text_file="$1"
    local output_file="$2"
    local voice_key="$3"

    # Skip if already exists
    if [[ -f "$output_file" ]] && [[ $(stat -f%z "$output_file" 2>/dev/null || stat -c%s "$output_file" 2>/dev/null) -gt 1000 ]]; then
        SKIPPED=$((SKIPPED + 1))
        return 0
    fi

    local voice_id
    voice_id=$(get_voice_id "$voice_key")
    if [[ -z "$voice_id" || "$voice_id" == "null" ]]; then
        echo -e "${RED}  ERROR: No ElevenLabs ID for voice $voice_key${NC}"
        echo "$output_file" >> "$FAILURES_FILE"
        FAILED=$((FAILED + 1))
        return 1
    fi

    local text
    text=$(cat "$text_file")
    local char_count=${#text}

    if $DRY_RUN; then
        echo -e "${BLUE}  [DRY RUN] ${char_count} chars → $(basename "$output_file") (${voice_key})${NC}"
        GENERATED=$((GENERATED + 1))
        return 0
    fi

    echo -e "${BLUE}  TTS: ${char_count} chars → $(basename "$output_file") (${voice_key})${NC}"

    local max_retries=2
    local attempt=0

    while [[ $attempt -le $max_retries ]]; do
        attempt=$((attempt + 1))

        local http_code
        http_code=$(curl -s -w "%{http_code}" \
            -X POST "https://api.elevenlabs.io/v1/text-to-speech/${voice_id}" \
            -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
            -H "Content-Type: application/json" \
            -d "$(jq -n \
                --arg text "$text" \
                --arg model "$ELEVENLABS_MODEL" \
                --argjson stability "$ELEVENLABS_STABILITY" \
                --argjson similarity "$ELEVENLABS_SIMILARITY" \
                --argjson style "$ELEVENLABS_STYLE" \
                '{
                    text: $text,
                    model_id: $model,
                    voice_settings: {
                        stability: $stability,
                        similarity_boost: $similarity,
                        style: $style,
                        use_speaker_boost: true
                    }
                }')" \
            -o "$output_file" 2>/dev/null)

        if [[ "$http_code" == "200" ]] && [[ -s "$output_file" ]]; then
            local size
            size=$(ls -lh "$output_file" | awk '{print $5}')
            echo -e "${GREEN}    ✓ ${size}${NC}"
            GENERATED=$((GENERATED + 1))
            if [[ $attempt -gt 1 ]]; then
                RETRIED=$((RETRIED + 1))
            fi
            sleep 1  # Rate limit protection
            return 0
        fi

        # Handle rate limiting
        if [[ "$http_code" == "429" ]]; then
            local wait=$((attempt * 5))
            echo -e "${YELLOW}    Rate limited (429). Waiting ${wait}s...${NC}"
            sleep "$wait"
            continue
        fi

        # Other errors
        echo -e "${RED}    Attempt $attempt failed: HTTP $http_code${NC}"
        rm -f "$output_file"
        sleep 2
    done

    echo -e "${RED}    FAILED after $max_retries retries${NC}"
    echo "$output_file|$text_file|$voice_key" >> "$FAILURES_FILE"
    FAILED=$((FAILED + 1))
    return 1
}

# =============================================================================
# Process a single story
# =============================================================================
process_story() {
    local mode_dir="$1"  # traditional or creative
    local story_id="$2"

    local story_dir="$STORIES_DIR/$mode_dir/$story_id"
    local meta_file="$story_dir/meta_${story_id}.json"

    if [[ ! -f "$meta_file" ]]; then
        echo -e "${RED}  No meta file for $story_id${NC}"
        return 1
    fi

    local mode voice_key kid_friendly
    mode=$(jq -r '.mode' "$meta_file")
    voice_key=$(jq -r '.voiceKey' "$meta_file")
    kid_friendly=$(jq -r '.kidFriendly' "$meta_file")

    echo -e "\n${GREEN}Story $story_id${NC} ($mode, kid=$kid_friendly, voice=$voice_key)"

    # Determine lanes
    local lanes=("web")
    if [[ "$kid_friendly" == "false" && "$mode" == "traditional" ]]; then
        lanes+=("kjv")
    fi

    # Generate story audio (short + full only)
    for lane in "${lanes[@]}"; do
        for length in short full; do
            local text_file="$story_dir/story_${story_id}_${mode}_${lane}_${length}.txt"
            local audio_file
            if [[ "$lane" == "web" ]]; then
                audio_file="$story_dir/audio_${story_id}_story_${length}.mp3"
            else
                audio_file="$story_dir/audio_${story_id}_story_${lane}_${length}.mp3"
            fi

            if [[ -f "$text_file" ]]; then
                generate_audio "$text_file" "$audio_file" "$voice_key"
            fi
        done
    done

    # Generate reflection audio
    for lane in "${lanes[@]}"; do
        local refl_file="$story_dir/reflection_${story_id}_${mode}_${lane}.txt"
        local refl_audio
        if [[ "$lane" == "web" ]]; then
            refl_audio="$story_dir/audio_${story_id}_reflection.mp3"
        else
            refl_audio="$story_dir/audio_${story_id}_reflection_${lane}.mp3"
        fi

        if [[ -f "$refl_file" ]]; then
            generate_audio "$refl_file" "$refl_audio" "$voice_key"
        fi
    done
}

# =============================================================================
# Main
# =============================================================================

echo "============================================"
echo "  Opus Audio Generation"
echo "============================================"
echo "Model: $ELEVENLABS_MODEL"
echo "Settings: stability=$ELEVENLABS_STABILITY similarity=$ELEVENLABS_SIMILARITY style=$ELEVENLABS_STYLE"
if $DRY_RUN; then
    echo -e "${YELLOW}MODE: DRY RUN (no API calls)${NC}"
fi
if [[ -n "$SINGLE_STORY" ]]; then
    echo "Targeting single story: $SINGLE_STORY"
fi
echo ""

# Handle retry mode
if [[ -n "$RETRY_FILE" ]]; then
    echo -e "${YELLOW}RETRY MODE: reading failures from $RETRY_FILE${NC}"
    while IFS='|' read -r output_file text_file voice_key; do
        [[ -z "$output_file" ]] && continue
        echo -e "${YELLOW}  Retrying: $(basename "$output_file")${NC}"
        generate_audio "$text_file" "$output_file" "$voice_key"
    done < "$RETRY_FILE"
else
    # Process all Opus traditional stories (1000+)
    for story_id in $(ls "$STORIES_DIR/traditional/" | sort -n | awk '$1 >= 1000'); do
        if [[ -n "$SINGLE_STORY" && "$story_id" != "$SINGLE_STORY" ]]; then
            continue
        fi
        process_story "traditional" "$story_id"
    done

    # Process all Opus creative stories (2000+)
    for story_id in $(ls "$STORIES_DIR/creative/" | sort -n | awk '$1 >= 2000'); do
        if [[ -n "$SINGLE_STORY" && "$story_id" != "$SINGLE_STORY" ]]; then
            continue
        fi
        process_story "creative" "$story_id"
    done
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo "============================================"
echo "  SUMMARY"
echo "============================================"
echo -e "  Generated: ${GREEN}$GENERATED${NC}"
echo -e "  Skipped:   ${BLUE}$SKIPPED${NC}"
echo -e "  Retried:   ${YELLOW}$RETRIED${NC}"
echo -e "  Failed:    ${RED}$FAILED${NC}"
echo ""

if [[ $FAILED -gt 0 ]]; then
    echo -e "${RED}Failures logged to: $FAILURES_FILE${NC}"
    echo "Retry with: $0 --retry-file $FAILURES_FILE"
fi

exit $FAILED

#!/bin/bash
# generate_voice_test_batch.sh
# Generates 5 parables with different voices for testing
# Each parable is 5 minutes, different mood, different voice

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"
MANIFEST_FILE="$OUTPUT_DIR/manifest.json"

# Source ElevenLabs safety guard and story calibration
source "$SCRIPT_DIR/elevenlabs_guard.sh"
source "$SCRIPT_DIR/story_calibration.sh"
trap elevenlabs_release_lock EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check dependencies
command -v jq >/dev/null 2>&1 || { echo -e "${RED}❌ Error: jq required${NC}" >&2; exit 1; }
command -v curl >/dev/null 2>&1 || { echo -e "${RED}❌ Error: curl required${NC}" >&2; exit 1; }

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ Error: .env not found${NC}"
    exit 1
fi

source "$ENV_FILE"

# Validate env vars
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - Voice Test Batch (5 parables, 5 voices)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Load or init manifest
if [[ -f "$MANIFEST_FILE" ]]; then
    if ! MANIFEST_JSON=$(cat "$MANIFEST_FILE" | jq '.' 2>/dev/null); then
        echo -e "${RED}❌ Error: manifest.json is corrupted${NC}"
        exit 1
    fi
else
    MANIFEST_JSON='{\"parables\":[]}'
fi

# Voice configurations (Voice ID, Name, Mood)
# Using voices from .env and ElevenLabs library
declare -a VOICES=(
    "JBFqnCBsd6RMkjVDRZzb:George:joyful"           # British, mature narrator - joyful
    "SAz9YHcvj6GT2YYXdXww:River:weary"             # Calm, neutral - weary
    "Xb7hH8MSUJpSbSDYk0k2:Alice:anxious"           # British, professional - anxious
    "pFZP5JQG7iQjIQuC4Bku:Lily:hurting"            # British, confident - hurting
    "XrExE9yKIg1WjnnlVkGX:Matilda:neutral"         # American, upbeat - neutral
)

for voice_config in "${VOICES[@]}"; do
    IFS=':' read -r voice_id voice_name mood <<< "$voice_config"

    # Calculate story number
    total_parables=$(echo "$MANIFEST_JSON" | jq '.parables | length')
    story_num=$((total_parables + 1))
    story_id=$(printf "parable_%03d_%s_5min_voice_%s" "$story_num" "$mood" "$voice_name")

    # Check if exists
    exists=$(echo "$MANIFEST_JSON" | jq -r --arg id "$story_id" '(.parables // []) | map(select(.storyId == $id)) | length')
    if [[ "$exists" != "0" ]]; then
        echo -e "${YELLOW}⊙ Skipping $story_id (exists)${NC}"
        continue
    fi

    echo -e "${BLUE}→ Generating: $story_id with voice $voice_name${NC}"

    # Generate story text using existing function
    source "$SCRIPT_DIR/generate_batch_parables.sh"
    story_text=$(generate_story_text "$mood" 5)
    title=$(generate_title "$mood" "$story_num")

    audio_file="$OUTPUT_DIR/${story_id}.mp3"
    text_file="$OUTPUT_DIR/${story_id}.txt"

    # Save text
    echo "$story_text" > "$text_file"

    # ELEVENLABS SAFETY GUARD
    char_count=$(printf "%s" "$story_text" | wc -c | tr -d ' ')

    if elevenlabs_check_and_log "$story_id" "$char_count" "5"; then
        http_code=$(elevenlabs_call "$story_text" "$audio_file" "$voice_id" "$ELEVENLABS_API_KEY")

        if [[ "$http_code" == "200" ]]; then
            file_size=$(ls -lh "$audio_file" | awk '{print $5}')
            echo -e "${GREEN}✓ Generated: $story_id ($file_size) - Voice: $voice_name${NC}"
            audio_path="${story_id}.mp3"
        else
            echo -e "${RED}✗ API Error (HTTP $http_code)${NC}"
            if [[ -f "$audio_file" ]]; then
                error_msg=$(jq -r '.detail.message // .message // empty' < "$audio_file" 2>/dev/null || cat "$audio_file")
                echo -e "${RED}Error: $error_msg${NC}"
                rm "$audio_file"
            fi
            audio_path="null"
        fi
    else
        echo -e "${YELLOW}⚠ Audio generation skipped for $story_id${NC}"
        audio_path="null"
    fi

    # Add to manifest (with or without audio)
    new_entry=$(jq -n \
        --arg id "$story_id" \
        --arg title "$title (Voice: $voice_name)" \
        --arg mood "$mood" \
        --argjson length 5 \
        --arg audio "$audio_path" \
        --arg text "${story_id}.txt" \
        '{
            storyId: $id,
            title: $title,
            mood: $mood,
            length: $length,
            faithTradition: "Protestant",
            storytellingMode: "creative",
            audioFilePath: (if $audio == "null" then null else $audio end),
            textFilePath: $text
        }')

    MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq ".parables += [$new_entry]")

    sleep 1  # Rate limiting
done

# Save manifest
echo "$MANIFEST_JSON" | jq '.' > "$MANIFEST_FILE"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Voice test batch complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Total parables: $(echo "$MANIFEST_JSON" | jq '.parables | length')"
echo ""

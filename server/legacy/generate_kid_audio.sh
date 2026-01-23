#!/usr/bin/env bash
# Generate audio for 16 kid-friendly traditional Bible stories using ElevenLabs
# Uses warm, nurturing voices appropriate for children's content
# Voice selection uses voices.json as single source of truth (kid-compatible pool)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"

# Source shared components
source "$SCRIPT_DIR/elevenlabs_guard.sh"
source "$SCRIPT_DIR/voice_selector.sh"
trap elevenlabs_release_lock EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}❌ Error: .env not found${NC}"
    exit 1
fi

while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    export "$key=$value"
done < "$ENV_FILE"

# Validate API key
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - Kid-Friendly Story Audio Generation${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Kid Voice Pool: ${GREEN}$(jq '[.voices[] | select(.audience | index("kid"))] | length' "$VOICES_FILE") voices${NC}"
echo ""

# Voice selection now uses voice_selector.sh with kid-compatible filter
# NOTE: Grace, Abilene, and Grant are FORBIDDEN voices - see ADR-002

# Story IDs to generate (parable_050 through parable_065)
STORY_IDS=(
    "parable_050_joyful_5min_kid_trad"
    "parable_051_joyful_10min_kid_trad"
    "parable_052_joyful_15min_kid_trad"
    "parable_053_joyful_20min_kid_trad"
    "parable_054_weary_5min_kid_trad"
    "parable_055_weary_10min_kid_trad"
    "parable_056_weary_15min_kid_trad"
    "parable_057_weary_20min_kid_trad"
    "parable_058_anxious_5min_kid_trad"
    "parable_059_anxious_10min_kid_trad"
    "parable_060_anxious_15min_kid_trad"
    "parable_061_anxious_20min_kid_trad"
    "parable_062_hurting_5min_kid_trad"
    "parable_063_hurting_10min_kid_trad"
    "parable_064_hurting_15min_kid_trad"
    "parable_065_hurting_20min_kid_trad"
)

# Generate audio for each story
for i in "${!STORY_IDS[@]}"; do
    story_id="${STORY_IDS[$i]}"
    text_file="$OUTPUT_DIR/${story_id}.txt"
    audio_file="$OUTPUT_DIR/${story_id}.mp3"

    # Skip if audio already exists
    if [[ -f "$audio_file" ]]; then
        echo -e "${YELLOW}⊙ Skipping $story_id (audio exists)${NC}"
        continue
    fi

    # Check if text file exists
    if [[ ! -f "$text_file" ]]; then
        echo -e "${RED}✗ Text file not found: $text_file${NC}"
        continue
    fi

    # Read story text
    story_text=$(cat "$text_file")
    char_count=$(printf "%s" "$story_text" | wc -c | tr -d ' ')

    # Select voice from kid-compatible pool (deterministic based on storyId)
    voice_key=$(select_voice_for_story "$story_id" "true")
    voice_id=$(get_voice_id "$voice_key")
    voice_name=$(get_voice_display_name "$voice_key")

    echo -e "${BLUE}→ Generating audio: $story_id${NC}"
    echo -e "${BLUE}  Narrator: $voice_name ($voice_key)${NC}"
    echo -e "${BLUE}  Characters: $char_count${NC}"

    # Extract length from story_id for safety check
    if [[ $story_id =~ _([0-9]+)min ]]; then
        length="${BASH_REMATCH[1]}"
    else
        length=10  # default fallback
    fi

    # Safety check and log
    if elevenlabs_check_and_log "$story_id" "$char_count" "$length"; then
        http_code=$(elevenlabs_call "$story_text" "$audio_file" "$voice_id" "$ELEVENLABS_API_KEY")

        if [[ "$http_code" == "200" ]]; then
            file_size=$(ls -lh "$audio_file" | awk '{print $5}')
            echo -e "${GREEN}✓ Generated: $story_id ($file_size)${NC}"
        else
            echo -e "${RED}✗ Audio generation failed (HTTP $http_code)${NC}"
            if [[ -f "$audio_file" ]]; then
                error_msg=$(cat "$audio_file")
                echo -e "${RED}Error: $error_msg${NC}"
                rm "$audio_file"
            fi
        fi
    else
        echo -e "${YELLOW}⚠ Audio generation skipped for $story_id${NC}"
    fi

    # Brief pause between API calls
    sleep 1
done

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Kid-friendly audio generation complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

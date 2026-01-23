#!/bin/bash
# =============================================================================
# generate_reflection_audio.sh
# Generates pre-spoken reflection audio for Bible PAL stories
# Uses ElevenLabs TTS with the SAME voice as the story
# =============================================================================
#
# ADR-010 REQUIREMENTS (docs/DECISIONS.md):
# - Every story (Traditional AND Creative) MUST have a reflection
# - Reflection audio MUST use the SAME narratorVoiceKey as the story
# - Reflection is NEVER auto-played - user taps "Hear Reflection" button
#
# USAGE:
#   ./generate_reflection_audio.sh <story_id> [--voice <VOICE_KEY>] [--mood <MOOD>] [--kid]
#
# IMPORTANT: When generating reflection for an existing story, ALWAYS pass
# the --voice flag with the SAME voice used for the story audio. This ensures
# voice continuity per ADR-010.
#
# EXAMPLES:
#   ./generate_reflection_audio.sh parable_401 --voice VOICE_JAMES_HUSKY --mood encouraging
#   ./generate_reflection_audio.sh parable_401 --kid --mood joyful
#
# PREREQUISITES:
#   - .env file with ELEVENLABS_API_KEY
#   - jq installed (for JSON parsing)
#   - server/voices.json (voice pool definition)
#
# =============================================================================

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Load environment variables
if [[ -f "$PROJECT_ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    source "$PROJECT_ROOT/.env"
fi

# Check for required tools
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq is required but not installed${NC}"
    exit 1
fi

# Check for API key
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

# Voice pool file
VOICES_FILE="$SCRIPT_DIR/voices.json"
if [[ ! -f "$VOICES_FILE" ]]; then
    echo -e "${RED}Error: voices.json not found at $VOICES_FILE${NC}"
    exit 1
fi

# =============================================================================
# Reflection Templates (deterministic, no LLM)
# =============================================================================
# These templates match lib/services/reflection_templates.dart
# Each ends with a soft landing line

declare -A ADULT_REFLECTIONS_BY_MOOD
ADULT_REFLECTIONS_BY_MOOD[joyful]="Stories of joy often reflect moments when gratitude and connection come together. These narratives show how small blessings can accumulate into a sense of abundance. And even a small step forward can be enough for today."
ADULT_REFLECTIONS_BY_MOOD[weary]="Weariness in stories often looks like carrying burdens over long stretches. These narratives show that rest and renewal are part of the natural rhythm of life. And even a small step forward can be enough for today."
ADULT_REFLECTIONS_BY_MOOD[anxious]="Stories about worry often reflect the tension between what we can control and what we cannot. These narratives show that peace sometimes comes from releasing our grip on outcomes. And even a small step forward can be enough for today."
ADULT_REFLECTIONS_BY_MOOD[hurting]="Pain in stories often looks like walking through seasons of loss or disappointment. These narratives show that sorrow and hope can exist together. And even a small step forward can be enough for today."
ADULT_REFLECTIONS_BY_MOOD[neutral]="Stories of ordinary days often reflect the steady rhythm of daily faithfulness. These narratives show that meaning can be found in quiet, unremarkable moments. And even a small step forward can be enough for today."
ADULT_REFLECTIONS_BY_MOOD[encouraging]="Stories of encouragement often reflect moments when hope breaks through difficulty. These narratives show that even small acts of kindness can sustain us through challenging times. And even a small step forward can be enough for today."

declare -A KID_REFLECTIONS_BY_MOOD
KID_REFLECTIONS_BY_MOOD[joyful]="This story shows that good things can happen when we share and care for others. Even one small kindness matters."
KID_REFLECTIONS_BY_MOOD[weary]="This story shows that it is okay to rest when we are tired. Even one small rest can help."
KID_REFLECTIONS_BY_MOOD[anxious]="This story shows that even when things feel scary, we are not alone. Even one small brave thing counts."
KID_REFLECTIONS_BY_MOOD[hurting]="This story shows that being kind matters, even when things feel unfair. Even one small kindness helps."
KID_REFLECTIONS_BY_MOOD[neutral]="This story shows that every day has moments worth noticing. Even one small thing can be special."
KID_REFLECTIONS_BY_MOOD[encouraging]="This story shows that we can help each other feel better. Even one small hello can make a difference."

# =============================================================================
# Functions
# =============================================================================

get_voice_id() {
    local voice_key="$1"
    jq -r --arg key "$voice_key" '.voices[] | select(.voiceKey == $key) | .elevenLabsId' "$VOICES_FILE"
}

get_fallback_voice_key() {
    jq -r '.selectionAlgorithm.fallback' "$VOICES_FILE"
}

select_voice_for_story() {
    local story_id="$1"
    local is_kid="${2:-false}"

    # Get all voices (filter for kid-friendly if needed)
    local voice_count
    if [[ "$is_kid" == "true" ]]; then
        voice_count=$(jq '[.voices[] | select(.audience | contains(["kid"]))] | length' "$VOICES_FILE")
    else
        voice_count=$(jq '.voices | length' "$VOICES_FILE")
    fi

    # Deterministic selection: hash story_id and mod by voice count
    local hash
    hash=$(echo -n "$story_id" | md5sum | cut -c1-8)
    local hash_dec=$((16#$hash))
    local index=$((hash_dec % voice_count))

    # Get voice key at index
    if [[ "$is_kid" == "true" ]]; then
        jq -r --argjson idx "$index" '[.voices[] | select(.audience | contains(["kid"]))][$idx].voiceKey' "$VOICES_FILE"
    else
        jq -r --argjson idx "$index" '.voices[$idx].voiceKey' "$VOICES_FILE"
    fi
}

generate_audio() {
    local text="$1"
    local voice_id="$2"
    local output_file="$3"

    local char_count=${#text}
    echo -e "${BLUE}Generating audio: ${char_count} chars with voice ${voice_id}${NC}"

    # Source the ElevenLabs guard for rate limiting
    if [[ -f "$SCRIPT_DIR/elevenlabs_guard.sh" ]]; then
        # shellcheck disable=SC1091
        source "$SCRIPT_DIR/elevenlabs_guard.sh"

        if ! elevenlabs_check_and_log "reflection" "$char_count" 1; then
            echo -e "${RED}ElevenLabs guard rejected request${NC}"
            return 1
        fi
    fi

    local response
    response=$(curl -s -w "\n%{http_code}" \
        -X POST "https://api.elevenlabs.io/v1/text-to-speech/${voice_id}" \
        -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "{
            \"text\": $(echo "$text" | jq -Rs .),
            \"model_id\": \"eleven_turbo_v2_5\",
            \"voice_settings\": {
                \"stability\": 0.6,
                \"similarity_boost\": 0.8,
                \"style\": 0.0,
                \"use_speaker_boost\": true
            }
        }" \
        -o "$output_file")

    local http_code
    http_code=$(echo "$response" | tail -n1)

    if [[ "$http_code" == "200" ]]; then
        echo -e "${GREEN}Audio generated successfully: $output_file${NC}"
        return 0
    else
        echo -e "${RED}ElevenLabs API error: HTTP $http_code${NC}"
        rm -f "$output_file"
        return 1
    fi
}

usage() {
    echo "Usage: $0 <story_id> [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --voice <VOICE_KEY>   Voice to use (e.g., VOICE_JAMES_HUSKY)"
    echo "  --mood <MOOD>         Mood for reflection (joyful, weary, anxious, hurting, neutral, encouraging)"
    echo "  --kid                 Use kid-friendly reflection template"
    echo "  --output <PATH>       Output file path (default: assets/stories/<story_id>.reflection.mp3)"
    echo "  --dry-run             Show what would be generated without calling API"
    echo ""
    echo "Examples:"
    echo "  $0 parable_401 --voice VOICE_JAMES_HUSKY --mood encouraging"
    echo "  $0 parable_401 --kid --mood joyful"
}

# =============================================================================
# Main
# =============================================================================

if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

STORY_ID="$1"
shift

# Parse arguments
VOICE_KEY=""
MOOD="neutral"
IS_KID="false"
OUTPUT_PATH=""
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --voice)
            VOICE_KEY="$2"
            shift 2
            ;;
        --mood)
            MOOD="$2"
            shift 2
            ;;
        --kid)
            IS_KID="true"
            shift
            ;;
        --output)
            OUTPUT_PATH="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Select voice if not specified
if [[ -z "$VOICE_KEY" ]]; then
    VOICE_KEY=$(select_voice_for_story "$STORY_ID" "$IS_KID")
    echo -e "${BLUE}Auto-selected voice: $VOICE_KEY${NC}"
fi

# Get ElevenLabs voice ID
VOICE_ID=$(get_voice_id "$VOICE_KEY")
if [[ -z "$VOICE_ID" || "$VOICE_ID" == "null" ]]; then
    echo -e "${RED}Error: Voice not found: $VOICE_KEY${NC}"
    exit 1
fi

# Get reflection text
if [[ "$IS_KID" == "true" ]]; then
    REFLECTION_TEXT="${KID_REFLECTIONS_BY_MOOD[$MOOD]:-${KID_REFLECTIONS_BY_MOOD[neutral]}}"
else
    REFLECTION_TEXT="${ADULT_REFLECTIONS_BY_MOOD[$MOOD]:-${ADULT_REFLECTIONS_BY_MOOD[neutral]}}"
fi

# Default output path
if [[ -z "$OUTPUT_PATH" ]]; then
    OUTPUT_PATH="$PROJECT_ROOT/assets/stories/${STORY_ID}.reflection.mp3"
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Generating Reflection Audio${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Story ID:    ${GREEN}$STORY_ID${NC}"
echo -e "Voice:       ${GREEN}$VOICE_KEY${NC}"
echo -e "Voice ID:    ${GREEN}$VOICE_ID${NC}"
echo -e "Mood:        ${GREEN}$MOOD${NC}"
echo -e "Kid Mode:    ${GREEN}$IS_KID${NC}"
echo -e "Output:      ${GREEN}$OUTPUT_PATH${NC}"
echo -e "Text:        ${YELLOW}${REFLECTION_TEXT:0:80}...${NC}"
echo ""

if [[ "$DRY_RUN" == "true" ]]; then
    echo -e "${YELLOW}DRY RUN - No API call made${NC}"
    echo ""
    echo "Full reflection text:"
    echo "$REFLECTION_TEXT"
    exit 0
fi

# Create output directory if needed
mkdir -p "$(dirname "$OUTPUT_PATH")"

# Generate audio
if generate_audio "$REFLECTION_TEXT" "$VOICE_ID" "$OUTPUT_PATH"; then
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}SUCCESS: Reflection audio generated${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Output JSON for manifest update
    echo ""
    echo "Add to manifest.json:"
    echo "{"
    echo "  \"reflectionAudioPath\": \"${STORY_ID}.reflection.mp3\","
    echo "  \"narratorVoiceKey\": \"$VOICE_KEY\""
    echo "}"
else
    echo -e "${RED}FAILED: Could not generate reflection audio${NC}"
    exit 1
fi

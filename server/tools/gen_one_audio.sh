#!/usr/bin/env bash
# gen_one_audio.sh
# Generates audio from a story text file using ElevenLabs API.
#
# Usage: AUDIO_ENABLED=1 ./gen_one_audio.sh <text_file> [voice_var]
# Example: AUDIO_ENABLED=1 ./gen_one_audio.sh assets/stories/parable_401_encouraging_5min.txt VOICE_JAMES_HUSKY
#
# Output: <text_file_basename>.mp3 (same directory as input)
#
# Requires:
#   - .env with ELEVENLABS_API_KEY and voice IDs
#   - AUDIO_ENABLED=1 to actually make the API call (safety guard)
#
# Robust curl pattern:
#   - Uses --connect-timeout 10 and --max-time 120
#   - Captures HTTP code via -w "%{http_code}"
#   - Reports curl exit code on failure

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# Source the guard for safety checks
source "$PROJECT_ROOT/server/elevenlabs_guard.sh"
trap elevenlabs_release_lock EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Load .env
if [[ ! -f "$ENV_FILE" ]]; then
    echo -e "${RED}Error: .env not found at $ENV_FILE${NC}"
    exit 1
fi

while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    export "$key=$value"
done < "$ENV_FILE"

# Validate required env vars
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

# Parse args
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Usage: AUDIO_ENABLED=1 $0 <text_file> [voice_var]${NC}"
    echo ""
    echo "Arguments:"
    echo "  text_file  - Path to story .txt file"
    echo "  voice_var  - Environment variable name for voice ID (default: VOICE_JAMES_HUSKY)"
    echo ""
    echo "Example:"
    echo "  AUDIO_ENABLED=1 $0 assets/stories/parable_401_encouraging_5min.txt VOICE_JAMES_HUSKY"
    echo ""
    echo "Available voices (from .env):"
    grep -E "^VOICE_" "$ENV_FILE" | sed 's/=.*//' | sed 's/^/  /'
    exit 1
fi

TEXT_FILE="$1"
VOICE_VAR="${2:-VOICE_JAMES_HUSKY}"

# Resolve to absolute path if relative
if [[ ! "$TEXT_FILE" = /* ]]; then
    TEXT_FILE="$PROJECT_ROOT/$TEXT_FILE"
fi

# Validate text file
if [[ ! -f "$TEXT_FILE" ]]; then
    echo -e "${RED}Error: Text file not found: $TEXT_FILE${NC}"
    exit 1
fi

# Determine output file (same basename, .mp3 extension)
OUTPUT_FILE="${TEXT_FILE%.txt}.mp3"

# Check if output already exists
if [[ -f "$OUTPUT_FILE" ]]; then
    echo -e "${YELLOW}Warning: Output file already exists: $OUTPUT_FILE${NC}"
    echo -e "${YELLOW}Refusing to overwrite. Delete manually to regenerate.${NC}"
    exit 1
fi

# Get voice ID from env var name
VOICE_ID="${!VOICE_VAR:-}"
if [[ -z "$VOICE_ID" ]]; then
    # Fallback to ELEVENLABS_VOICE_ID
    VOICE_ID="${ELEVENLABS_VOICE_ID:-}"
    if [[ -z "$VOICE_ID" ]]; then
        echo -e "${RED}Error: Voice not found: $VOICE_VAR (and no ELEVENLABS_VOICE_ID fallback)${NC}"
        exit 1
    fi
    echo -e "${YELLOW}Note: Using ELEVENLABS_VOICE_ID as fallback${NC}"
fi

# Read story text
STORY_TEXT=$(cat "$TEXT_FILE")
if [[ -z "$STORY_TEXT" ]]; then
    echo -e "${RED}Error: Text file is empty: $TEXT_FILE${NC}"
    exit 1
fi

CHAR_COUNT=$(printf '%s' "$STORY_TEXT" | wc -c | tr -d ' ')
WORD_COUNT=$(echo "$STORY_TEXT" | wc -w | tr -d ' ')

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  One-Off Audio Generation (ElevenLabs)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Input:      ${GREEN}$TEXT_FILE${NC}"
echo -e "Output:     ${GREEN}$OUTPUT_FILE${NC}"
echo -e "Voice:      ${GREEN}$VOICE_VAR${NC}"
echo -e "Word count: ${GREEN}$WORD_COUNT${NC}"
echo -e "Char count: ${GREEN}$CHAR_COUNT${NC}"
echo ""

# Use the guard (assumes 5min tier for short stories)
if ! elevenlabs_check_and_log "oneshot_audio" "$CHAR_COUNT" 5; then
    echo -e "${YELLOW}Audio generation blocked by safety guard.${NC}"
    exit 1
fi

# Build JSON payload
JSON_PAYLOAD=$(jq -n \
    --arg text "$STORY_TEXT" \
    '{
        text: $text,
        model_id: "eleven_multilingual_v2",
        voice_settings: {
            stability: 0.70,
            similarity_boost: 0.70,
            style: 0.0,
            use_speaker_boost: true
        }
    }')

echo -e "${BLUE}→ Calling ElevenLabs API...${NC}"

# Robust curl invocation with timeouts and proper error capture
HTTP_CODE=$(curl -sS \
    --connect-timeout 10 \
    --max-time 120 \
    -w "%{http_code}" \
    -o "$OUTPUT_FILE" \
    -X POST \
    "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}" \
    -H "xi-api-key: $ELEVENLABS_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$JSON_PAYLOAD" 2>&1) || {
    CURL_EXIT=$?
    echo -e "${RED}Curl failed with exit code: $CURL_EXIT${NC}"
    echo -e "${RED}HTTP code captured: $HTTP_CODE${NC}"
    rm -f "$OUTPUT_FILE"
    exit 1
}

# Release lock
elevenlabs_release_lock

if [[ "$HTTP_CODE" == "200" ]]; then
    # Verify file exists and has content
    if [[ ! -s "$OUTPUT_FILE" ]]; then
        echo -e "${RED}Error: Output file is empty despite HTTP 200${NC}"
        rm -f "$OUTPUT_FILE"
        exit 1
    fi

    FILE_SIZE=$(ls -lh "$OUTPUT_FILE" | awk '{print $5}')

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}✓ Audio Generated Successfully${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "File:     ${GREEN}$OUTPUT_FILE${NC}"
    echo -e "Size:     ${GREEN}$FILE_SIZE${NC}"
    echo -e "Credits:  ${GREEN}~$CHAR_COUNT${NC}"
    echo ""
    echo -e "${YELLOW}Note: .mp3 files are gitignored. Do not commit.${NC}"
else
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}✗ ElevenLabs API Error (HTTP $HTTP_CODE)${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Try to extract error message
    if [[ -f "$OUTPUT_FILE" ]]; then
        ERROR_MSG=$(jq -r '.detail.message // .detail // .message // empty' < "$OUTPUT_FILE" 2>/dev/null || cat "$OUTPUT_FILE" | head -200)
        if [[ -n "$ERROR_MSG" ]]; then
            echo -e "${RED}Error: $ERROR_MSG${NC}"
        fi
        rm -f "$OUTPUT_FILE"
    fi
    exit 1
fi

#!/bin/bash
# gen_one_story_api.sh
# Generates ONE story using Ollama HTTP API (reliable, no hangs).
#
# Usage: ./gen_one_story_api.sh <mood> <story_id>
# Example: ./gen_one_story_api.sh encouraging 401
#
# Output: assets/stories/parable_<ID>_<mood>_short.txt
#
# LOCKED SPEC: Generates SHORT bucket stories (250-600 words)
#
# Why HTTP API instead of CLI?
# - `ollama run` via command substitution hangs and leaves stray processes
# - HTTP API with stream:false returns complete output reliably

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROMPT_FILE="$PROJECT_ROOT/server/prompts/golden_trad_adult_short.prompt.txt"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Validate args
if [[ $# -lt 2 ]]; then
    echo -e "${RED}Usage: $0 <mood> <story_id>${NC}"
    echo ""
    echo "Arguments:"
    echo "  mood      - encouraging, joyful, weary, anxious, hurting, neutral"
    echo "  story_id  - numeric ID (e.g., 401)"
    echo ""
    echo "Example: $0 encouraging 401"
    echo "Output:  assets/stories/parable_401_encouraging_short.txt"
    exit 1
fi

MOOD="$1"
STORY_ID="$2"
OUTPUT_FILE="$OUTPUT_DIR/parable_${STORY_ID}_${MOOD}_short.txt"

# Validate mood
VALID_MOODS="encouraging joyful weary anxious hurting neutral"
if [[ ! " $VALID_MOODS " =~ " $MOOD " ]]; then
    echo -e "${RED}Invalid mood: $MOOD${NC}"
    echo "Valid moods: $VALID_MOODS"
    exit 1
fi

# Check if output already exists (safety: don't overwrite)
if [[ -f "$OUTPUT_FILE" ]]; then
    echo -e "${RED}Output file already exists: $OUTPUT_FILE${NC}"
    echo "Refusing to overwrite. Delete manually if regeneration is intended."
    exit 1
fi

# Check prompt file
if [[ ! -f "$PROMPT_FILE" ]]; then
    echo -e "${RED}Prompt file not found: $PROMPT_FILE${NC}"
    exit 1
fi

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  One-Off Story Generation (Ollama HTTP API)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Mood:     ${GREEN}$MOOD${NC}"
echo -e "Story ID: ${GREEN}$STORY_ID${NC}"
echo -e "Output:   ${GREEN}$OUTPUT_FILE${NC}"
echo ""

# Safety: kill any stray ollama run processes before starting
echo -e "${YELLOW}→ Cleaning up stray ollama run processes...${NC}"
if pkill -f "ollama run gemma" 2>/dev/null; then
    echo -e "${YELLOW}  Killed stray processes. Waiting 2s...${NC}"
    sleep 2
else
    echo -e "${GREEN}  No stray processes found.${NC}"
fi

# Build prompt with mood substitution
PROMPT=$(sed "s/{{MOOD}}/$MOOD/g" "$PROMPT_FILE")

# Check Ollama is running
if ! curl -s --connect-timeout 5 http://localhost:11434/api/tags >/dev/null 2>&1; then
    echo -e "${RED}Ollama is not running. Start it with: ollama serve${NC}"
    exit 1
fi

echo -e "${BLUE}→ Generating story via Ollama API (stream:false)...${NC}"

# Use HTTP API with stream:false for reliable output
RESPONSE=$(curl -sS --connect-timeout 10 --max-time 180 \
    http://localhost:11434/api/generate \
    -d "$(jq -n --arg prompt "$PROMPT" '{
        model: "gemma:7b",
        prompt: $prompt,
        stream: false,
        options: {
            temperature: 0.7,
            num_predict: 700
        }
    }')" 2>&1)

CURL_EXIT=$?
if [[ $CURL_EXIT -ne 0 ]]; then
    echo -e "${RED}Curl failed with exit code: $CURL_EXIT${NC}"
    echo -e "${RED}Response: $RESPONSE${NC}"
    exit 1
fi

# Extract story text from JSON response
STORY_TEXT=$(echo "$RESPONSE" | jq -r '.response // empty')

if [[ -z "$STORY_TEXT" ]]; then
    echo -e "${RED}No story text in response.${NC}"
    echo "Raw response:"
    echo "$RESPONSE" | head -500
    exit 1
fi

# Strip any residual ANSI codes (belt and suspenders)
STORY_TEXT=$(printf '%s' "$STORY_TEXT" | perl -pe '
    s/\e\[[0-9;?]*[a-zA-Z]//g;
    s/\e\][^\a]*\a//g;
    s/\e.//g;
    s/\r//g;
')

# Write to file
printf '%s\n' "$STORY_TEXT" > "$OUTPUT_FILE"

# Count words
WORD_COUNT=$(wc -w < "$OUTPUT_FILE" | tr -d ' ')
CHAR_COUNT=$(wc -c < "$OUTPUT_FILE" | tr -d ' ')

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Story Generated Successfully${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "File:       ${GREEN}$OUTPUT_FILE${NC}"
echo -e "Word count: ${GREEN}$WORD_COUNT${NC}"
echo -e "Char count: ${GREEN}$CHAR_COUNT${NC}"
echo ""

# Validate word count against LOCKED SPEC (SHORT bucket: 250-600)
if (( WORD_COUNT < 250 )); then
    echo -e "${YELLOW}⚠ Warning: Word count ($WORD_COUNT) is below SHORT bucket range (250-600).${NC}"
    echo -e "${YELLOW}  Consider regenerating with adjusted prompt.${NC}"
elif (( WORD_COUNT > 600 )); then
    echo -e "${YELLOW}⚠ Warning: Word count ($WORD_COUNT) is above SHORT bucket range (250-600).${NC}"
    echo -e "${YELLOW}  Consider regenerating with adjusted prompt.${NC}"
else
    echo -e "${GREEN}✓ Word count is within SHORT bucket range (250-600).${NC}"
fi

echo ""
echo "Preview (first 3 lines):"
head -3 "$OUTPUT_FILE"

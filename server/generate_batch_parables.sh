#!/bin/bash
# generate_batch_parables.sh - v1 MVP
# Generates a batch of 6 production parables for Bible PAL
# Usage: ./generate_batch_parables.sh [batch_number] [mood_rotation]
#
# Known v1 limitations (will fix in v2 after testing):
# - All 3×5min parables will be identical
# - Lengths are approximate, not precisely timed
# - No voice variety (all default narrator)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
OUTPUT_DIR="$PROJECT_ROOT/assets/stories"
MANIFEST_FILE="$OUTPUT_DIR/manifest.json"

# Source shared calibration and safety guard
source "$SCRIPT_DIR/story_calibration.sh"
source "$SCRIPT_DIR/elevenlabs_guard.sh"
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

while IFS='=' read -r key value; do
    [[ -z "$key" || "$key" =~ ^[[:space:]]*# ]] && continue
    value=$(echo "$value" | sed 's/[[:space:]]*#.*//')
    export "$key=$value"
done < "$ENV_FILE"

# Validate env vars
if [[ -z "${ELEVENLABS_API_KEY:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_API_KEY not found in .env${NC}"
    exit 1
fi

if [[ -z "${ELEVENLABS_VOICE_ID:-}" ]]; then
    echo -e "${RED}❌ Error: ELEVENLABS_VOICE_ID not found in .env${NC}"
    exit 1
fi

# Parse arguments
BATCH_NUM="${1:-1}"
MOOD_INDEX="${2:-0}"

# Mood rotation
MOODS=("joyful" "weary" "anxious" "hurting" "neutral")
CURRENT_MOOD="${MOODS[$((MOOD_INDEX % 5))]}"

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Bible PAL - Batch Parable Generation (v1 MVP)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Batch: ${GREEN}#$BATCH_NUM${NC}"
echo -e "Mood: ${GREEN}$CURRENT_MOOD${NC}"
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
    MANIFEST_JSON='{"parables":[]}'
fi

# Function to generate a single parable
generate_parable() {
    local length=$1
    local index=$2
    local mood=$3

    # Calculate story ID (simple sequential numbering)
    local total_parables=$(echo "$MANIFEST_JSON" | jq '.parables | length')
    local story_num=$((total_parables + 1))
    local story_id=$(printf "parable_%03d_%s_%dmin" "$story_num" "$mood" "$length")

    # Check if exists (safe for empty manifest)
    local exists=$(echo "$MANIFEST_JSON" | jq -r --arg id "$story_id" '(.parables // []) | map(select(.storyId == $id)) | length')
    if [[ "$exists" != "0" ]]; then
        echo -e "${YELLOW}⊙ Skipping $story_id (exists)${NC}"
        return 0
    fi

    echo -e "${BLUE}→ Generating: $story_id${NC}"

    # Generate story text
    local story_text=$(generate_story_text "$mood" "$length")

    # Check if story generation failed
    if [[ $? -ne 0 ]] || [[ -z "$story_text" ]]; then
        echo -e "${RED}✗ Story generation failed${NC}"
        continue
    fi

    # Generate title from story
    local title=$(generate_title "$mood" "$story_num" "$story_text")

    local audio_file="$OUTPUT_DIR/${story_id}.mp3"
    local text_file="$OUTPUT_DIR/${story_id}.txt"

    # Save text
    echo "$story_text" > "$text_file"

    # ELEVENLABS SAFETY GUARD
    local char_count=$(printf "%s" "$story_text" | wc -c | tr -d ' ')
    local audio_generated=false

    if elevenlabs_check_and_log "$story_id" "$char_count" "$length"; then
        local http_code=$(elevenlabs_call "$story_text" "$audio_file" "$ELEVENLABS_VOICE_ID" "$ELEVENLABS_API_KEY")

        if [[ "$http_code" == "200" ]]; then
            local file_size=$(ls -lh "$audio_file" | awk '{print $5}')
            echo -e "${GREEN}✓ Generated: $story_id ($file_size)${NC}"
            audio_generated=true
        else
            echo -e "${RED}✗ Audio generation failed for $story_id${NC}"
            audio_file=""
        fi
    else
        echo -e "${YELLOW}⚠ Audio generation skipped for $story_id${NC}"
        audio_file=""
    fi

    if [[ "$audio_generated" == true ]]; then

        # Add to manifest
        local new_entry=$(jq -n \
            --arg id "$story_id" \
            --arg title "$title" \
            --arg mood "$mood" \
            --argjson length "$length" \
            --arg audio "${story_id}.mp3" \
            --arg text "${story_id}.txt" \
            '{
                storyId: $id,
                title: $title,
                mood: $mood,
                length: $length,
                faithTradition: "Protestant",
                storytellingMode: "creative",
                audioFilePath: $audio,
                textFilePath: $text
            }')

        MANIFEST_JSON=$(echo "$MANIFEST_JSON" | jq ".parables += [$new_entry]")

    else
        echo -e "${RED}✗ API Error (HTTP $http_code)${NC}"
        if [[ -f "$audio_file" ]]; then
            local error_msg=$(jq -r '.detail.message // .message // empty' < "$audio_file" 2>/dev/null || cat "$audio_file")
            echo -e "${RED}Error: $error_msg${NC}"
            rm "$audio_file"
        fi
        return 1
    fi
}

# Story text generator (paraphrased, no direct Bible quotes)
generate_story_text() {
    local mood=$1
    local length=$2

    # Calculate target word count based on ~120 words/minute speaking rate
    # (ElevenLabs with current voice settings speaks slowly and contemplatively)
    local target_words=$((length * 120))
    local min_acceptable=$((target_words * 90 / 100))  # 90% of target

    # Chunk size for segmented generation (600-800 words per chunk)
    local chunk_size=700

    # Build mood-specific prompt
    local mood_context=""
    case "$mood" in
        joyful)
            mood_context="The listener is feeling joyful, grateful, and wants to celebrate God's goodness. Create a modern parable that acknowledges their joy while deepening their gratitude and encouraging them to share that joy with others."
            ;;
        weary)
            mood_context="The listener is feeling exhausted, burned out, and carrying heavy burdens. Create a modern parable about rest, release, and trusting God with what we cannot control. Show the beauty of Sabbath rest and divine provision."
            ;;
        anxious)
            mood_context="The listener is feeling anxious, worried, and overwhelmed by uncertainties. Create a modern parable about bringing fears to God in prayer, finding peace through trust, and experiencing God's presence in the midst of anxiety."
            ;;
        hurting)
            mood_context="The listener is experiencing deep pain, loss, or brokenness. Create a modern parable about God's nearness to the brokenhearted, the healing journey, and how our wounds can become places where grace enters."
            ;;
        neutral)
            mood_context="The listener is in a reflective, open state. Create a modern parable about finding God in ordinary moments, seeing the sacred in the everyday, and discovering meaning in routine tasks."
            ;;
    esac

    # Generate story in segments
    local full_story=""
    local current_words=0
    local segment_num=0
    local max_segments=10  # Safety limit

    while [[ $current_words -lt $min_acceptable ]] && [[ $segment_num -lt $max_segments ]]; do
        segment_num=$((segment_num + 1))
        local words_needed=$((target_words - current_words))
        local this_chunk=$((words_needed < chunk_size ? words_needed : chunk_size))

        local prompt=""
        if [[ $segment_num -eq 1 ]]; then
            # First segment - establish the story
            prompt="You are a compassionate storyteller creating modern Christian parables in the style of Jesus' parables - simple, relatable stories with profound spiritual truth.

Context: $mood_context

Write the BEGINNING of a parable (approximately $this_chunk words). This is part 1 of a longer story.

Requirements:
- Use modern settings and relatable characters (not biblical times)
- Write in a warm, contemplative narrative style
- Include concrete sensory details and emotional authenticity
- Introduce the main character and their situation
- Use Protestant Christian theology
- Write as continuous narrative prose
- Do NOT conclude the story yet
- Write approximately $this_chunk words

Begin the parable now:"
        else
            # Continuation segment - maintain flow
            prompt="Continue the following parable. Write the NEXT SECTION (approximately $this_chunk words).

Context: $mood_context

Story so far:
$full_story

Requirements:
- Continue naturally from where the story left off
- Maintain the same character, setting, and tone
- Deepen the spiritual insight and transformation
- If this brings us close to $target_words total words, bring the story to a meaningful conclusion with hope
- If not, continue developing the narrative
- Write approximately $this_chunk words

Continue the parable now:"
        fi

        # Generate segment using Ollama
        local segment
        segment=$(ollama run gemma:7b "$prompt" 2>&1)

        # Check if generation was successful
        if [[ $? -ne 0 ]]; then
            echo -e "${RED}Error: Gemma 7B generation failed on segment $segment_num${NC}" >&2
            return 1
        fi

        # Clean up ANSI escape codes and artifacts
        segment=$(echo "$segment" | sed $'s/\x1b\\[[0-9;]*[a-zA-Z]//g' | sed $'s/\x1b\\[?[0-9]*[a-z]//g')
        segment=$(echo "$segment" | tr -d '\r' | sed 's/\[K//g' | sed 's/\[?[0-9]*[hl]//g')
        segment=$(echo "$segment" | sed 's/^>.*$//')
        segment=$(echo "$segment" | sed '/^$/N;/^\n$/D')
        # Remove Unicode Braille pattern characters (Ollama spinner: U+2800-U+28FF)
        segment=$(echo "$segment" | sed 's/[⠀-⣿]//g')
        segment=$(echo "$segment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        # Append to full story
        if [[ -n "$full_story" ]]; then
            full_story="$full_story

$segment"
        else
            full_story="$segment"
        fi

        # Count words
        current_words=$(echo "$full_story" | wc -w | tr -d ' ')
    done

    echo "$full_story"
}

generate_title() {
    local mood=$1
    local num=$2
    local story_text=$3

    # Extract title from story using Gemma 7B
    local prompt="Read this parable and create a short, evocative title (3-6 words) that captures its essence. Return ONLY the title, nothing else.

Parable:
$story_text

Title:"

    local title
    title=$(ollama run gemma:7b "$prompt" 2>&1 | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | sed 's/^"//;s/"$//')

    # If title generation fails, use mood-based fallback
    if [[ -z "$title" ]] || [[ $? -ne 0 ]]; then
        case "$mood" in
            joyful) title="A Story of Joy" ;;
            weary) title="Finding Rest" ;;
            anxious) title="Peace in Uncertainty" ;;
            hurting) title="Healing and Hope" ;;
            neutral) title="Seeing the Sacred" ;;
        esac
    fi

    echo "$title"
}

# Generate batch
# Check if INCLUDE_20MIN is set
if [[ "${INCLUDE_20MIN:-false}" == "true" ]]; then
    echo -e "${BLUE}Generating 1 × 20min parable...${NC}"
    echo ""
    generate_parable 20 0 "$CURRENT_MOOD" || exit 1
else
    echo -e "${BLUE}Generating 3 parables (5min, 10min, 15min)...${NC}"
    echo ""

    # 1 × 5min
    generate_parable 5 0 "$CURRENT_MOOD" || exit 1
    sleep 1

    # 1 × 10min
    generate_parable 10 1 "$CURRENT_MOOD" || exit 1
    sleep 1

    # 1 × 15min
    generate_parable 15 2 "$CURRENT_MOOD" || exit 1
fi

# Save manifest
echo "$MANIFEST_JSON" | jq '.' > "$MANIFEST_FILE"

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✓ Batch #$BATCH_NUM complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Total parables: $(echo "$MANIFEST_JSON" | jq '.parables | length')"
echo -e "Next mood: ${MOODS[$(((MOOD_INDEX + 1) % 5))]}"
echo ""

#!/bin/sh
# Generate Adult Traditional 5-minute stories with CONTRACT ENFORCEMENT
# Uses Gemma-7B via Ollama for content generation
# Claude Code is infrastructure only - NO prose generation
#
# This script:
# 1. Loads contract + prompt template
# 2. Generates with Gemma
# 3. Validates word count
# 4. Retries/continues until valid (standard mode) OR regenerates fresh (golden mode)
# 5. Quarantines failures
#
# Usage:
#   ./generate_adult_traditional_stories.sh              # Standard mode (with continuation)
#   ./generate_adult_traditional_stories.sh --golden-prompt  # Golden mode (single-shot)

set -e

# === MODE SELECTION ===
GOLDEN_PROMPT_MODE=false
OUTPUT_SUFFIX="trad"

# Parse arguments
while [ $# -gt 0 ]; do
    case $1 in
        --golden-prompt)
            GOLDEN_PROMPT_MODE=true
            OUTPUT_SUFFIX="golden_trad"
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--golden-prompt]"
            echo ""
            echo "Options:"
            echo "  --golden-prompt  Use Golden Prompt mode (recommended for Gemma-7B)"
            echo "                   Single-shot generation, no continuation logic"
            echo "                   Outputs to parable_3XX_*_golden_trad.txt"
            echo ""
            echo "Without flags: Standard mode with continuation prompts"
            echo "               Outputs to parable_2XX_*_trad.txt"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# === PATHS ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
STORY_DIR="${PROJECT_ROOT}/assets/stories"
FAILED_DIR="${PROJECT_ROOT}/assets/stories_failed"
LOGS_DIR="${SCRIPT_DIR}/logs"

# === MODE-DEPENDENT PATHS AND CONFIG ===
MODEL="gemma:7b"
TARGET_WORDS=600

if [ "$GOLDEN_PROMPT_MODE" = true ]; then
    CONTRACT_FILE="${SCRIPT_DIR}/contracts/golden_contract_trad_adult_5min.yaml"
    PROMPT_TEMPLATE="${SCRIPT_DIR}/prompts/golden_trad_adult_5min.prompt.txt"
    MIN_WORDS=450
    MAX_RETRIES=2
    MODE_NAME="golden"
else
    CONTRACT_FILE="${SCRIPT_DIR}/contracts/story_contract_trad_adult_5min.yaml"
    PROMPT_TEMPLATE="${SCRIPT_DIR}/prompts/trad_adult_5min.prompt.txt"
    MIN_WORDS=510
    MAX_RETRIES=5
    MODE_NAME="standard"
fi

# === MODE GUARD ===
# Prevents mixing golden and standard modes in the same session
MODE_LOCK="${LOGS_DIR}/.active_generation_mode"
mkdir -p "$LOGS_DIR"

validate_mode_guard() {
    if [ -f "$MODE_LOCK" ]; then
        active_mode=$(cat "$MODE_LOCK")
        if [ "$active_mode" != "$MODE_NAME" ]; then
            echo "ERROR: Mode guard violation!"
            echo "  Active mode: $active_mode"
            echo "  Requested mode: $MODE_NAME"
            echo "  Cannot mix modes in same session."
            echo "  Wait for previous run to finish or delete: $MODE_LOCK"
            exit 1
        fi
    fi
    echo "$MODE_NAME" > "$MODE_LOCK"
}

clear_mode_guard() {
    rm -f "$MODE_LOCK"
}

# Ensure mode guard is cleared on exit
trap clear_mode_guard EXIT INT TERM

# === HELPER FUNCTIONS ===

count_words() {
    echo "$1" | wc -w | tr -d ' '
}

get_tags() {
    case "$1" in
        joyful) echo "gratitude,celebration,thankfulness" ;;
        weary) echo "exhaustion,burnout,perseverance" ;;
        anxious) echo "worry,fear,uncertainty" ;;
        hurting) echo "grief,loss,pain" ;;
        neutral) echo "reflection,contemplation,stillness" ;;
        encouraging) echo "hope,strength,motivation" ;;
        calm_peaceful) echo "serenity,rest,tranquility" ;;
        brave_courage) echo "courage,boldness,faith" ;;
        *) echo "general" ;;
    esac
}

build_prompt() {
    local mood=$1
    # Load template and substitute mood placeholder
    sed "s/{{MOOD}}/${mood}/g" "$PROMPT_TEMPLATE"
}

build_continue_prompt() {
    local current_words=$1
    local remaining=$((TARGET_WORDS - current_words))
    echo "Your story is incomplete. You wrote only ${current_words} words but need ${TARGET_WORDS}.

Continue the story EXACTLY where you left off. Write ${remaining} more words to complete it.

DO NOT restart. DO NOT summarize. Just continue the narrative and bring it to a proper closing reflection.

CONTINUE:"
}

generate_with_retries() {
    local mood=$1
    local story_id=$2
    local filename="parable_${story_id}_${mood}_5min_${OUTPUT_SUFFIX}.txt"
    local filepath="${STORY_DIR}/${filename}"
    local failed_path="${FAILED_DIR}/${filename}.failed"
    local tags=$(get_tags "$mood")
    local mode_label=$([ "$GOLDEN_PROMPT_MODE" = true ] && echo "golden_traditional" || echo "traditional")

    # Skip if file already exists
    if [ -f "$filepath" ]; then
        echo "SKIP: $filename already exists"
        return 0
    fi

    echo ""
    echo "=== Generating: $filename (mood: $mood, mode: $MODE_NAME) ==="

    local attempt=1
    local story_content=""
    local word_count=0

    # Initial generation
    echo "Attempt $attempt: Initial generation..."
    local prompt=$(build_prompt "$mood")
    story_content=$(ollama run "$MODEL" "$prompt" 2>/dev/null)
    word_count=$(count_words "$story_content")
    echo "  Generated $word_count words"

    # Retry logic - differs by mode
    if [ "$GOLDEN_PROMPT_MODE" = true ]; then
        # GOLDEN MODE: Fresh regeneration only (no continuation prompts)
        # Attempt 2 uses stricter structure (12 paragraphs instead of 10)
        while [ "$word_count" -lt "$MIN_WORDS" ] && [ "$attempt" -lt "$MAX_RETRIES" ]; do
            attempt=$((attempt + 1))
            echo "Attempt $attempt: Story too short ($word_count < $MIN_WORDS), regenerating fresh with stricter structure..."

            # Escalate structure: 10 paragraphs -> 12 paragraphs for attempt 2
            local prompt_stricter
            prompt_stricter=$(echo "$prompt" | sed 's/exactly 10 paragraphs/exactly 12 paragraphs/g' | sed 's/End after paragraph 10/End after paragraph 12/g')

            # Full regeneration with stricter structure
            story_content=$(ollama run "$MODEL" "$prompt_stricter" 2>/dev/null)
            word_count=$(count_words "$story_content")
            echo "  Generated $word_count words"
        done
    else
        # STANDARD MODE: Continuation prompts (original behavior)
        while [ "$word_count" -lt "$MIN_WORDS" ] && [ "$attempt" -lt "$MAX_RETRIES" ]; do
            attempt=$((attempt + 1))
            echo "Attempt $attempt: Story too short ($word_count < $MIN_WORDS), continuing..."

            # Build continuation prompt
            local continue_prompt=$(build_continue_prompt "$word_count")
            continue_prompt="${continue_prompt}

Previous text (continue from here):
---
${story_content}
---"

            # Get continuation
            local continuation=$(ollama run "$MODEL" "$continue_prompt" 2>/dev/null)

            # Append continuation
            story_content="${story_content}

${continuation}"
            word_count=$(count_words "$story_content")
            echo "  Now at $word_count words"
        done
    fi

    # Final validation
    if [ "$word_count" -lt "$MIN_WORDS" ]; then
        echo "FAILED: Could not reach $MIN_WORDS words after $attempt attempt(s)"
        echo "  Quarantining to: $failed_path"

        # Save to quarantine
        cat > "$failed_path" << EOF
---
story_id: parable_${story_id}_${mood}_5min_${OUTPUT_SUFFIX}
mood: ${mood}
length_min: 5
mode: ${mode_label}
kid_friendly: false
tradition: Unspecified
tags: [${tags}]
failure_reason: word_count_too_low
actual_words: ${word_count}
required_words: ${MIN_WORDS}
attempts: ${attempt}
---

${story_content}
EOF
        return 1
    fi

    # SUCCESS - write to assets/stories
    echo "SUCCESS: $filename ($word_count words in $attempt attempt(s))"

    cat > "$filepath" << EOF
---
story_id: parable_${story_id}_${mood}_5min_${OUTPUT_SUFFIX}
mood: ${mood}
length_min: 5
mode: ${mode_label}
kid_friendly: false
tradition: Unspecified
tags: [${tags}]
---

EOF

    echo "$story_content" >> "$filepath"
    return 0
}

# === MAIN EXECUTION ===

echo "=========================================="
echo "Adult Traditional Story Generator"
echo "=========================================="
if [ "$GOLDEN_PROMPT_MODE" = true ]; then
    echo "Mode: GOLDEN PROMPT (single-shot, no continuation)"
else
    echo "Mode: STANDARD (with continuation)"
fi
echo "Model: $MODEL"
echo "Contract: $CONTRACT_FILE"
echo "Template: $PROMPT_TEMPLATE"
echo "Output: $STORY_DIR"
echo "Quarantine: $FAILED_DIR"
echo "Min words: $MIN_WORDS"
echo "Max retries: $MAX_RETRIES"
echo "=========================================="

# Validate mode guard (prevents mixing modes in same session)
validate_mode_guard

# Verify files exist
if [ ! -f "$CONTRACT_FILE" ]; then
    echo "ERROR: Contract file not found: $CONTRACT_FILE"
    exit 1
fi

if [ ! -f "$PROMPT_TEMPLATE" ]; then
    echo "ERROR: Prompt template not found: $PROMPT_TEMPLATE"
    exit 1
fi

# Ensure directories exist
mkdir -p "$STORY_DIR" "$FAILED_DIR"

# Generate all moods
# Use 300-series IDs for golden mode, 200-series for standard
success_count=0
fail_count=0

if [ "$GOLDEN_PROMPT_MODE" = true ]; then
    MOOD_IDS="301:joyful 302:weary 303:anxious 304:hurting 305:neutral 306:encouraging 307:calm_peaceful 308:brave_courage"
else
    MOOD_IDS="201:joyful 202:weary 203:anxious 204:hurting 205:neutral 206:encouraging 207:calm_peaceful 208:brave_courage"
fi

for mood_id in $MOOD_IDS; do
    id="${mood_id%%:*}"
    mood="${mood_id##*:}"

    if generate_with_retries "$mood" "$id"; then
        success_count=$((success_count + 1))
    else
        fail_count=$((fail_count + 1))
    fi
done

echo ""
echo "=========================================="
echo "Generation Complete"
echo "=========================================="
echo "Successful: $success_count"
echo "Failed: $fail_count"
echo ""

if [ "$fail_count" -gt 0 ]; then
    echo "Failed stories are in: $FAILED_DIR"
    echo "Review and retry manually, or run this script again."
fi

echo "Next step: Update manifest.json if needed"

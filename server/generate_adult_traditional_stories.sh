#!/usr/bin/env bash
# Generate Adult Traditional stories with CONTRACT ENFORCEMENT
# Uses Gemma-7B via Ollama for content generation
# Claude Code is infrastructure only - NO prose generation
#
# This script:
# 1. Loads prompt template
# 2. Generates with Gemma
# 3. Validates word count with gate branching
# 4. Retries via continuation or regeneration
# 5. Quarantines failures
#
# Usage:
#   ./generate_adult_traditional_stories.sh              # Standard mode (with continuation)
#   ./generate_adult_traditional_stories.sh --golden-prompt  # Golden mode (SHORT bucket test)

set -euo pipefail

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
            echo "  --golden-prompt  Use Golden Prompt mode with SHORT bucket guardrails"
            echo "                   Accept gate: 300-700 words"
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

if [ "$GOLDEN_PROMPT_MODE" = true ]; then
    CONTRACT_FILE="${SCRIPT_DIR}/contracts/golden_contract_trad_adult_5min.yaml"
    PROMPT_TEMPLATE="${SCRIPT_DIR}/prompts/golden_trad_adult_5min.prompt.txt"
    # SHORT bucket test generation (NOT claiming 5-min calibration)
    ACCEPT_MIN=300       # Below this: needs continuation
    ACCEPT_MAX=700       # Above this: regenerate with tighter range
    PROMPT_TARGET=500    # Midpoint of 380-620 for prompt
    MODE_NAME="golden"
else
    CONTRACT_FILE="${SCRIPT_DIR}/contracts/story_contract_trad_adult_5min.yaml"
    PROMPT_TEMPLATE="${SCRIPT_DIR}/prompts/trad_adult_5min.prompt.txt"
    ACCEPT_MIN=510
    ACCEPT_MAX=720
    PROMPT_TARGET=600
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

# Strip ANSI/CSI escape sequences (portable for macOS/BSD sed)
strip_ansi() {
    printf '%s' "$1" | sed \
        -e $'s/\x1b\\[[0-9;?]*[ -/]*[@-~]//g' \
        -e $'s/\x1b.//g' \
        -e $'s/\r//g'
}

# Count words (strips ANSI first)
count_words() {
    local clean
    clean=$(strip_ansi "$1")
    printf '%s' "$clean" | wc -w | tr -d ' '
}

# Extract last 1-2 sentences for continuation context
extract_last_context() {
    local text="$1"
    local clean
    clean=$(strip_ansi "$text")

    # Normalize whitespace
    clean=$(printf '%s' "$clean" | tr '\n' ' ' | tr -s ' ')

    # Take last ~1000 chars
    local tail_text
    tail_text=$(printf '%s' "$clean" | tail -c 1000)

    # Try to extract last 1-2 sentences
    local sentences
    sentences=$(printf '%s' "$tail_text" | grep -oE '[^.!?]*[.!?]' | tail -2 | tr '\n' ' ')

    # Fallback: if sentence parse fails (<50 chars), use last 250 chars
    if [ ${#sentences} -lt 50 ]; then
        sentences=$(printf '%s' "$tail_text" | tail -c 250)
    fi

    printf '%s' "$sentences"
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

# Tighter prompt for over-length regeneration (350-600 range)
build_prompt_tight() {
    local mood=$1
    sed "s/{{MOOD}}/${mood}/g; s/380-620/350-600/g" "$PROMPT_TEMPLATE"
}

build_continue_prompt() {
    local current_text="$1"
    local current_words="$2"
    local remaining=$((PROMPT_TARGET - current_words))

    local context
    context=$(extract_last_context "$current_text")

    cat << EOF
Continue this story. Write approximately ${remaining} more words.

Pick up EXACTLY where this left off:
"${context}"

Continue the narrative now:
EOF
}

# Run ollama and capture both stdout and stderr
# Returns 1 if ollama fails or output is empty
run_ollama() {
    local prompt="$1"
    local tmpfile
    tmpfile=$(mktemp)
    local errfile
    errfile=$(mktemp)

    local result
    if ! ollama run "$MODEL" "$prompt" > "$tmpfile" 2> "$errfile"; then
        echo "ERROR: ollama command failed" >&2
        cat "$errfile" >&2
        rm -f "$tmpfile" "$errfile"
        return 1
    fi

    local output
    output=$(cat "$tmpfile")
    rm -f "$tmpfile" "$errfile"

    # Check for empty output
    if [ -z "$output" ]; then
        echo "ERROR: ollama returned empty output" >&2
        return 1
    fi

    printf '%s' "$output"
    return 0
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

    local prompt story_content word_count
    local continuation_attempts=0
    local regeneration_attempts=0

    # Initial generation
    echo "  Initial generation..."
    prompt=$(build_prompt "$mood")
    if ! story_content=$(run_ollama "$prompt"); then
        echo "  ERROR: Initial generation failed"
        return 1
    fi
    story_content=$(strip_ansi "$story_content")
    word_count=$(count_words "$story_content")
    echo "  Initial: $word_count words"

    if [ "$GOLDEN_PROMPT_MODE" = true ]; then
        # === GOLDEN MODE: Gate branching logic ===

        # GATE: Too short (<300) - try continuation (max 2 times)
        while [ "$word_count" -lt "$ACCEPT_MIN" ] && [ "$continuation_attempts" -lt 2 ]; do
            continuation_attempts=$((continuation_attempts + 1))
            echo "  Continuation attempt $continuation_attempts (wc=$word_count < $ACCEPT_MIN)..."

            local continue_prompt
            continue_prompt=$(build_continue_prompt "$story_content" "$word_count")
            local continuation
            if ! continuation=$(run_ollama "$continue_prompt"); then
                echo "    ERROR: Continuation failed"
                break
            fi
            continuation=$(strip_ansi "$continuation")

            story_content="${story_content}

${continuation}"
            word_count=$(count_words "$story_content")
            echo "    Now: $word_count words"
        done

        # GATE: Still too short after continuations - regenerate once from scratch
        if [ "$word_count" -lt "$ACCEPT_MIN" ] && [ "$regeneration_attempts" -lt 1 ]; then
            regeneration_attempts=$((regeneration_attempts + 1))
            echo "  Still short after continuations, regenerating from scratch..."

            if ! story_content=$(run_ollama "$prompt"); then
                echo "    ERROR: Regeneration failed"
            else
                story_content=$(strip_ansi "$story_content")
                word_count=$(count_words "$story_content")
                echo "    Regenerated: $word_count words"

                # One more continuation attempt if still short
                if [ "$word_count" -lt "$ACCEPT_MIN" ]; then
                    local continue_prompt
                    continue_prompt=$(build_continue_prompt "$story_content" "$word_count")
                    local continuation
                    if continuation=$(run_ollama "$continue_prompt"); then
                        continuation=$(strip_ansi "$continuation")
                        story_content="${story_content}

${continuation}"
                        word_count=$(count_words "$story_content")
                        echo "    After continuation: $word_count words"
                    fi
                fi
            fi
        fi

        # GATE: Too long (>700) - regenerate once with tighter range
        if [ "$word_count" -gt "$ACCEPT_MAX" ]; then
            echo "  Too long ($word_count > $ACCEPT_MAX), regenerating with tighter range..."

            local tighter_prompt
            tighter_prompt=$(build_prompt_tight "$mood")
            if story_content=$(run_ollama "$tighter_prompt"); then
                story_content=$(strip_ansi "$story_content")
                word_count=$(count_words "$story_content")
                echo "    Tighter regeneration: $word_count words"
            else
                echo "    ERROR: Tighter regeneration failed, keeping original"
            fi
        fi

    else
        # === STANDARD MODE: Original continuation logic ===
        local attempt=1
        while [ "$word_count" -lt "$ACCEPT_MIN" ] && [ "$attempt" -lt 5 ]; do
            attempt=$((attempt + 1))
            echo "  Attempt $attempt: Story too short ($word_count < $ACCEPT_MIN), continuing..."

            # Build continuation prompt with full story
            local continue_prompt="Your story is incomplete. You wrote only ${word_count} words but need ${PROMPT_TARGET}.

Continue the story EXACTLY where you left off. Write $((PROMPT_TARGET - word_count)) more words to complete it.

DO NOT restart. DO NOT summarize. Just continue the narrative and bring it to a proper closing reflection.

Previous text (continue from here):
---
${story_content}
---

CONTINUE:"

            local continuation
            if ! continuation=$(run_ollama "$continue_prompt"); then
                echo "    ERROR: Continuation failed"
                break
            fi
            continuation=$(strip_ansi "$continuation")

            story_content="${story_content}

${continuation}"
            word_count=$(count_words "$story_content")
            echo "    Now at $word_count words"
        done
    fi

    # Final validation
    if [ "$word_count" -lt "$ACCEPT_MIN" ]; then
        echo "FAILED: Could not reach $ACCEPT_MIN words"
        echo "  Quarantining to: $failed_path"

        # Save to quarantine (with metadata for debugging)
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
required_words: ${ACCEPT_MIN}
---

${story_content}
EOF
        return 1
    fi

    # SUCCESS - write prose-only (no metadata header)
    echo "SUCCESS: $filename ($word_count words)"
    printf '%s\n' "$story_content" > "$filepath"
    return 0
}

# === MAIN EXECUTION ===

echo "=========================================="
echo "Adult Traditional Story Generator"
echo "=========================================="
if [ "$GOLDEN_PROMPT_MODE" = true ]; then
    echo "Mode: GOLDEN PROMPT (SHORT bucket test)"
    echo "Accept gate: $ACCEPT_MIN - $ACCEPT_MAX words"
else
    echo "Mode: STANDARD (with continuation)"
fi
echo "Model: $MODEL"
echo "Contract: $CONTRACT_FILE (documentation only)"
echo "Template: $PROMPT_TEMPLATE"
echo "Output: $STORY_DIR"
echo "Quarantine: $FAILED_DIR"
echo "=========================================="

# Validate mode guard (prevents mixing modes in same session)
validate_mode_guard

# Verify prompt template exists
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

# === VERIFICATION COMMANDS (run manually) ===
# Word count check:
#   wc -w assets/stories/parable_30*_golden_trad.txt
# ANSI escape check:
#   grep -l $'\x1b' assets/stories/parable_30*_golden_trad.txt || echo "No ANSI codes"

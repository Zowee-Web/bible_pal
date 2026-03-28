#!/bin/bash
# bakeoff_claude_vs_gpt41.sh — Claude vs GPT-4.1 bakeoff for Creative stories
# Tests 5 stories × 3 models (GPT-4.1, Claude Sonnet 4, Claude Opus 4)
# Same prompt, same DNA, same validators — quality comparison only.
#
# Usage: bash server/bakeoff_claude_vs_gpt41.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Load .env
set -a
source "$ENV_FILE"
set +a

if [[ -z "${OPENAI_API_KEY:-}" ]]; then
    echo -e "${RED}FATAL: OPENAI_API_KEY not set in .env${NC}"
    exit 1
fi
if [[ -z "${ANTHROPIC_API_KEY:-}" ]] || [[ "${ANTHROPIC_API_KEY}" == "your-key-here" ]]; then
    echo -e "${RED}FATAL: ANTHROPIC_API_KEY not set in .env${NC}"
    exit 1
fi

# =============================================================================
# TEST MATRIX — 5 stories with diverse mood/DNA combos
# =============================================================================

# Format: "character_name|mood|opening|structure|setting|archetype|tone|narrator|kid"
# Round 2: All kid-friendly WEB creative
STORIES=(
    "Kael|anxious|action|unexpected_encounter|medium|healer|wonder|fireside|true"
    "Miriam|hurting|question|problem_solution|low|farmer|gentle|literary|true"
    "Tobias|calm_peaceful|conflict|journey|high|shepherd|solemn|folk_tale|true"
    "Esther|joyful|dialogue|flashback|medium|child|bittersweet|spare|true"
    "Rowan|brave_courage|memory|witness|low|craftsman|hopeful|fireside|true"
)

MODELS=(
    "gpt-4.1|openai"
    "claude-sonnet-4-20250514|anthropic"
    "claude-opus-4-20250514|anthropic"
)

# =============================================================================
# PROMPT BUILDER
# =============================================================================

build_prompt() {
    local char_name="$1" mood="$2" opening="$3" structure="$4"
    local setting="$5" archetype="$6" tone="$7" narrator="$8" kid="${9:-false}"

    local template
    template=$(cat "$SCRIPT_DIR/prompts/creative_prompt.template.txt" | grep -v '^#')

    template="${template//\{\{MOOD\}\}/$mood}"
    template="${template//\{\{LENGTH_BUCKET\}\}/full}"
    template="${template//\{\{LANGUAGE_STYLE\}\}/WEB}"
    template="${template//\{\{CHARACTER_NAME\}\}/$char_name}"
    template="${template//\{\{CHARACTER_ARCHETYPE\}\}/$archetype}"
    template="${template//\{\{OPENING_TYPE\}\}/$opening}"
    template="${template//\{\{STRUCTURE_TYPE\}\}/$structure}"
    template="${template//\{\{SETTING_EMPHASIS\}\}/$setting}"
    template="${template//\{\{TONE\}\}/$tone}"
    template="${template//\{\{NARRATOR_VOICE\}\}/$narrator}"
    template="${template//\{\{PLACE_NAMES_AVOID\}\}/}"
    template="${template//\{\{SCENE_BLUEPRINT\}\}/}"

    # Remove KJV conditional block
    template=$(echo "$template" | sed '/{{#if LANGUAGE_STYLE == KJV}}/,/{{\/if}}/d')

    # Add kid-safe constraints if needed
    if [[ "$kid" == "true" ]]; then
        template="$template

## ADDITIONAL: KID-FRIENDLY REQUIREMENTS
- Write for a child aged 5-9
- Use simple words and short sentences (average 12 words or fewer)
- Avoid frightening, violent, or complex emotional content
- Focus on wonder, kindness, safety, and gentle lessons
- No references to death, war, weapons, or monsters
- Characters should feel safe and cared for throughout"
    fi

    echo "$template"
}

# =============================================================================
# GENERATION FUNCTIONS
# =============================================================================

generate_openai() {
    local model="$1" prompt="$2"
    local response
    response=$(curl -s --connect-timeout 10 --max-time 600 \
        -X POST "https://api.openai.com/v1/responses" \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$model" --arg input "$prompt" \
            '{model: $model, input: $input, max_output_tokens: 2048}')")

    local error_msg
    error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$error_msg" ]]; then
        echo "API_ERROR: $error_msg"
        return 1
    fi

    echo "$response" | jq -r '.output[0].content[0].text // empty'
}

generate_anthropic() {
    local model="$1" prompt="$2"
    local response
    response=$(curl -s --connect-timeout 10 --max-time 600 \
        -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: ${ANTHROPIC_API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$model" --arg prompt "$prompt" \
            '{model: $model, max_tokens: 2048, messages: [{role: "user", content: $prompt}]}')")

    local error_msg
    error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$error_msg" ]]; then
        echo "API_ERROR: $error_msg"
        return 1
    fi

    echo "$response" | jq -r '.content[0].text // empty'
}

# Sanitize: strip metadata lines, trim whitespace
sanitize() {
    local text="$1"
    text=$(echo "$text" | sed '/^[Ww]ord [Cc]ount/d; /^\*\*/d; /^(source:/d; /^---/d')
    text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "$text"
}

# =============================================================================
# CRAFT VALIDATOR (same logic as generate_v2_batch.sh)
# =============================================================================

validate_craft() {
    local text="$1"
    local char_name="$2"
    local failures=""

    # Opening violations (first 2 lines)
    local opening
    opening=$(echo "$text" | head -2)

    if echo "$opening" | grep -qiE '^in the heart of'; then
        failures="${failures}opening:in_the_heart_of; "
    fi
    if echo "$opening" | grep -qiE '^there was'; then
        failures="${failures}opening:there_was; "
    fi
    if echo "$opening" | grep -qiE '^once'; then
        failures="${failures}opening:once; "
    fi
    if echo "$opening" | grep -qiE '^as[[:space:]]'; then
        failures="${failures}opening:as; "
    fi

    # Summary language (whole text)
    local summary_phrases=("he felt" "she felt" "they felt" "he realized" "she realized" "he understood" "she understood" "a sense of")
    for phrase in "${summary_phrases[@]}"; do
        if echo "$text" | grep -qi "$phrase"; then
            local tag
            tag=$(echo "$phrase" | tr ' ' '_')
            failures="${failures}summary:${tag}; "
        fi
    done

    # Ending violations (last 3 lines)
    local ending
    ending=$(echo "$text" | tail -3)

    local ending_phrases=("from then on" "and so" "he learned that" "she learned that" "he knew that" "she knew that")
    for phrase in "${ending_phrases[@]}"; do
        if echo "$ending" | grep -qi "$phrase"; then
            local tag
            tag=$(echo "$phrase" | tr ' ' '_')
            failures="${failures}ending:${tag}; "
        fi
    done

    # Protagonist name
    if [[ -n "$char_name" ]]; then
        if ! echo "$text" | grep -q "$char_name"; then
            failures="${failures}protagonist:missing_${char_name}; "
        fi
    fi

    # Word count check (full bucket: 450-650)
    local wc
    wc=$(echo "$text" | wc -w | tr -d ' ')
    if [[ $wc -lt 350 ]]; then
        failures="${failures}wordcount:too_short(${wc}); "
    elif [[ $wc -gt 800 ]]; then
        failures="${failures}wordcount:too_long(${wc}); "
    fi

    if [[ -z "$failures" ]]; then
        echo "PASS"
    else
        echo "$failures"
    fi
}

# =============================================================================
# RUN BAKEOFF
# =============================================================================

echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${BLUE}  CREATIVE STORY BAKEOFF — Claude vs GPT-4.1 (KID-FRIENDLY)${NC}"
echo -e "${BOLD}${BLUE}  5 stories × 3 models = 15 generations${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

RESULTS_DIR="$PROJECT_ROOT/server/bakeoff_results"
mkdir -p "$RESULTS_DIR"

# Track results for summary table
declare -a SUMMARY_LINES=()

story_num=0
for story_def in "${STORIES[@]}"; do
    story_num=$((story_num + 1))
    IFS='|' read -r char_name mood opening structure setting archetype tone narrator kid <<< "$story_def"

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  STORY $story_num: $char_name | mood=$mood | opening=$opening | structure=$structure${NC}"
    echo -e "${BOLD}${CYAN}  archetype=$archetype | tone=$tone | narrator=$narrator | kid=$kid${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    PROMPT=$(build_prompt "$char_name" "$mood" "$opening" "$structure" "$setting" "$archetype" "$tone" "$narrator" "$kid")

    for model_def in "${MODELS[@]}"; do
        IFS='|' read -r model_name provider <<< "$model_def"

        # Short label for filenames
        local_label=""
        case "$model_name" in
            gpt-4.1) local_label="gpt41" ;;
            claude-sonnet-4-20250514) local_label="claude_sonnet" ;;
            claude-opus-4-20250514) local_label="claude_opus" ;;
        esac

        echo -e "  ${BOLD}>>> $model_name${NC} ${BLUE}(generating...)${NC}"

        TEXT=""
        if [[ "$provider" == "openai" ]]; then
            TEXT=$(generate_openai "$model_name" "$PROMPT") || true
        else
            TEXT=$(generate_anthropic "$model_name" "$PROMPT") || true
        fi

        if [[ -z "$TEXT" ]] || [[ "$TEXT" == API_ERROR* ]]; then
            echo -e "  ${RED}FAILED: ${TEXT:-empty response}${NC}"
            SUMMARY_LINES+=("$(printf "%-16s %-18s %-10s %-6s %s" "$local_label" "$mood" "ERROR" "0" "${TEXT:-empty}")")
            echo ""
            continue
        fi

        TEXT=$(sanitize "$TEXT")
        WC=$(echo "$TEXT" | wc -w | tr -d ' ')
        VALID=$(validate_craft "$TEXT" "$char_name")

        # Save text
        outfile="$RESULTS_DIR/${local_label}_kid_story${story_num}_${mood}.txt"
        echo "$TEXT" > "$outfile"

        # Display result
        if [[ "$VALID" == "PASS" ]]; then
            echo -e "  ${GREEN}PASS${NC} | ${WC} words | saved → ${outfile##*/}"
        else
            echo -e "  ${RED}FAIL${NC} | ${WC} words | ${YELLOW}${VALID}${NC}"
            echo -e "  saved → ${outfile##*/}"
        fi

        SUMMARY_LINES+=("$(printf "%-16s %-18s %-10s %-6s %s" "$local_label" "$mood" "$([ "$VALID" = "PASS" ] && echo "PASS" || echo "FAIL")" "$WC" "$([ "$VALID" = "PASS" ] && echo "-" || echo "$VALID")")")
        echo ""
    done
done

# =============================================================================
# SUMMARY TABLE
# =============================================================================

echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${BLUE}  BAKEOFF SUMMARY${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
printf "%-16s %-18s %-10s %-6s %s\n" "MODEL" "MOOD" "VALIDATOR" "WORDS" "FAILURES"
printf "%-16s %-18s %-10s %-6s %s\n" "────────" "──────────" "─────────" "─────" "────────"

for line in "${SUMMARY_LINES[@]}"; do
    echo "$line"
done

# Save summary to file
{
    printf "%-16s %-18s %-10s %-6s %s\n" "MODEL" "MOOD" "VALIDATOR" "WORDS" "FAILURES"
    printf "%-16s %-18s %-10s %-6s %s\n" "────────" "──────────" "─────────" "─────" "────────"
    for line in "${SUMMARY_LINES[@]}"; do
        echo "$line"
    done
} > "$RESULTS_DIR/bakeoff_kid_summary.txt"

echo ""
echo -e "Results saved to: ${CYAN}$RESULTS_DIR/${NC}"
echo -e "${YELLOW}Review the story texts to compare quality across models.${NC}"

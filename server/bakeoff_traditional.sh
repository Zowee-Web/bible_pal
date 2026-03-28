#!/bin/bash
# bakeoff_traditional.sh — GPT-4.1 vs Claude Opus 4.6 for Traditional stories
# 5 stories × 2 models = 10 generations
# Uses real narrative anchors from traditional_seeds.json
#
# Usage: bash server/bakeoff_traditional.sh

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

SEEDS_FILE="$SCRIPT_DIR/seeds/traditional_seeds.json"

# =============================================================================
# TEST MATRIX — 5 stories with diverse passages
# =============================================================================

# Format: "seed_key|mood|length_bucket"
STORIES=(
    "lost_sheep|joyful|short"
    "woman_at_well|hurting|full"
    "road_to_emmaus|weary|full"
    "daniel_lions_den|brave_courage|full"
    "david_and_goliath|brave_courage|full"
)

MODELS=(
    "gpt-4.1|openai"
    "claude-opus-4-6|anthropic"
)

# =============================================================================
# PROMPT BUILDER
# =============================================================================

build_traditional_prompt() {
    local seed_key="$1" mood="$2" length_bucket="$3"

    # Extract seed data
    local bible_ref characters setting conflict turning_point theme sensory passage_final
    bible_ref=$(jq -r --arg k "$seed_key" '.[$k].bibleSourceRef' "$SEEDS_FILE")
    characters=$(jq -r --arg k "$seed_key" '.[$k].characters | join(", ")' "$SEEDS_FILE")
    setting=$(jq -r --arg k "$seed_key" '.[$k].setting' "$SEEDS_FILE")
    conflict=$(jq -r --arg k "$seed_key" '.[$k].conflict' "$SEEDS_FILE")
    turning_point=$(jq -r --arg k "$seed_key" '.[$k].turning_point' "$SEEDS_FILE")
    theme=$(jq -r --arg k "$seed_key" '.[$k].theme' "$SEEDS_FILE")
    sensory=$(jq -r --arg k "$seed_key" '.[$k].sensory_atmosphere' "$SEEDS_FILE")
    passage_final=$(jq -r --arg k "$seed_key" '.[$k].passageFinalLine' "$SEEDS_FILE")

    # Build narrative anchors block
    local anchors="## NARRATIVE ANCHORS (from story seed)
- Characters: ${characters}
- Setting: ${setting}
- Conflict: ${conflict}
- Turning Point: ${turning_point}
- Theme: ${theme}
- Sensory Atmosphere: ${sensory}
"

    local passage_final_block="The FINAL LINE of the passage is:
\"${passage_final}\"
Your story must build toward this line and end at or immediately after it. Do not continue past this point."

    # Load and substitute template
    local template
    template=$(cat "$SCRIPT_DIR/prompts/traditional_prompt.template.txt" | grep -v '^#')

    template="${template//\{\{BIBLE_SOURCE_REF\}\}/$bible_ref}"
    template="${template//\{\{MOOD\}\}/$mood}"
    template="${template//\{\{LENGTH_BUCKET\}\}/$length_bucket}"
    template="${template//\{\{LANGUAGE_STYLE\}\}/WEB}"
    template="${template//\{\{NARRATIVE_ANCHORS\}\}/$anchors}"
    template="${template//\{\{PASSAGE_FINAL_LINE\}\}/$passage_final_block}"
    template="${template//\{\{SCENE_BLUEPRINT\}\}/}"

    echo "$template"
}

# =============================================================================
# GENERATION FUNCTIONS
# =============================================================================

generate_openai() {
    local model="$1" prompt="$2"
    local max_tokens="$3"
    local response
    response=$(curl -s --connect-timeout 10 --max-time 600 \
        -X POST "https://api.openai.com/v1/responses" \
        -H "Authorization: Bearer ${OPENAI_API_KEY}" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$model" --arg input "$prompt" --argjson max "$max_tokens" \
            '{model: $model, input: $input, max_output_tokens: $max}')")

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
    local max_tokens="$3"
    local response
    response=$(curl -s --connect-timeout 10 --max-time 600 \
        -X POST "https://api.anthropic.com/v1/messages" \
        -H "x-api-key: ${ANTHROPIC_API_KEY}" \
        -H "anthropic-version: 2023-06-01" \
        -H "Content-Type: application/json" \
        -d "$(jq -n --arg model "$model" --arg prompt "$prompt" --argjson max "$max_tokens" \
            '{model: $model, max_tokens: $max, messages: [{role: "user", content: $prompt}]}')")

    local error_msg
    error_msg=$(echo "$response" | jq -r '.error.message // empty' 2>/dev/null)
    if [[ -n "$error_msg" ]]; then
        echo "API_ERROR: $error_msg"
        return 1
    fi

    echo "$response" | jq -r '.content[0].text // empty'
}

# Sanitize: strip metadata lines
sanitize() {
    local text="$1"
    text=$(echo "$text" | sed '/^[Ww]ord [Cc]ount/d; /^\*\*/d; /^(source:/d; /^---/d')
    text=$(echo "$text" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    echo "$text"
}

# =============================================================================
# TRADITIONAL VALIDATOR
# =============================================================================

validate_traditional() {
    local text="$1"
    local length_bucket="$2"
    local failures=""

    local wc
    wc=$(echo "$text" | wc -w | tr -d ' ')

    # Word count checks per bucket
    case "$length_bucket" in
        short)
            [[ $wc -lt 250 ]] && failures="${failures}wordcount:too_short(${wc}); "
            [[ $wc -gt 600 ]] && failures="${failures}wordcount:too_long(${wc}); "
            ;;
        full)
            [[ $wc -lt 500 ]] && failures="${failures}wordcount:too_short(${wc}); "
            [[ $wc -gt 1200 ]] && failures="${failures}wordcount:too_long(${wc}); "
            ;;
        long)
            [[ $wc -lt 1000 ]] && failures="${failures}wordcount:too_short(${wc}); "
            [[ $wc -gt 2000 ]] && failures="${failures}wordcount:too_long(${wc}); "
            ;;
    esac

    # Drift detection — check last 30% for continuation phrases
    local total_lines
    total_lines=$(echo "$text" | wc -l | tr -d ' ')
    local tail_start=$(( total_lines * 70 / 100 ))
    [[ $tail_start -lt 1 ]] && tail_start=1
    local tail_text
    tail_text=$(echo "$text" | tail -n +"$tail_start")

    local drift_phrases=("as evening fell" "in the days that followed" "from then on" "the lesson lingered" "and from that day" "in the silence that followed" "rest now" "enough for today" "one long breath" "at last, peace")
    for phrase in "${drift_phrases[@]}"; do
        if echo "$tail_text" | grep -qi "$phrase"; then
            local tag
            tag=$(echo "$phrase" | tr ' ' '_')
            failures="${failures}drift:${tag}; "
        fi
    done

    # MoDC violations
    local modc_phrases=("this teaches us" "we should" "let us" "dear friend" "I sit with you" "I am here")
    for phrase in "${modc_phrases[@]}"; do
        if echo "$text" | grep -qi "$phrase"; then
            local tag
            tag=$(echo "$phrase" | tr ' ' '_')
            failures="${failures}modc:${tag}; "
        fi
    done

    # Metadata leakage
    if echo "$text" | grep -qiE '^\*\*|^word count|^title:|^source:'; then
        failures="${failures}metadata_leak; "
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
echo -e "${BOLD}${BLUE}  TRADITIONAL STORY BAKEOFF — GPT-4.1 vs Claude Opus 4.6${NC}"
echo -e "${BOLD}${BLUE}  5 stories × 2 models = 10 generations${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

RESULTS_DIR="$PROJECT_ROOT/server/bakeoff_results"
mkdir -p "$RESULTS_DIR"

declare -a SUMMARY_LINES=()

story_num=0
for story_def in "${STORIES[@]}"; do
    story_num=$((story_num + 1))
    IFS='|' read -r seed_key mood length_bucket <<< "$story_def"

    local_bible_ref=$(jq -r --arg k "$seed_key" '.[$k].bibleSourceRef' "$SEEDS_FILE")

    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${CYAN}  STORY $story_num: $seed_key | $local_bible_ref | mood=$mood | length=$length_bucket${NC}"
    echo -e "${BOLD}${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    PROMPT=$(build_traditional_prompt "$seed_key" "$mood" "$length_bucket")

    # Token budget based on length
    max_tokens=4096
    case "$length_bucket" in
        short) max_tokens=2048 ;;
        full)  max_tokens=4096 ;;
        long)  max_tokens=6144 ;;
    esac

    for model_def in "${MODELS[@]}"; do
        IFS='|' read -r model_name provider <<< "$model_def"

        local_label=""
        case "$model_name" in
            gpt-4.1) local_label="gpt41" ;;
            claude-opus-4-6) local_label="opus46" ;;
        esac

        echo -e "  ${BOLD}>>> $model_name${NC} ${BLUE}(generating...)${NC}"

        TEXT=""
        if [[ "$provider" == "openai" ]]; then
            TEXT=$(generate_openai "$model_name" "$PROMPT" "$max_tokens") || true
        else
            TEXT=$(generate_anthropic "$model_name" "$PROMPT" "$max_tokens") || true
        fi

        if [[ -z "$TEXT" ]] || [[ "$TEXT" == API_ERROR* ]]; then
            echo -e "  ${RED}FAILED: ${TEXT:-empty response}${NC}"
            SUMMARY_LINES+=("$(printf "%-10s %-22s %-8s %-10s %-6s %s" "$local_label" "$seed_key" "$length_bucket" "ERROR" "0" "${TEXT:-empty}")")
            echo ""
            continue
        fi

        TEXT=$(sanitize "$TEXT")
        WC=$(echo "$TEXT" | wc -w | tr -d ' ')
        VALID=$(validate_traditional "$TEXT" "$length_bucket")

        outfile="$RESULTS_DIR/${local_label}_trad_${seed_key}.txt"
        echo "$TEXT" > "$outfile"

        if [[ "$VALID" == "PASS" ]]; then
            echo -e "  ${GREEN}PASS${NC} | ${WC} words | saved → ${outfile##*/}"
        else
            echo -e "  ${RED}FAIL${NC} | ${WC} words | ${YELLOW}${VALID}${NC}"
            echo -e "  saved → ${outfile##*/}"
        fi

        SUMMARY_LINES+=("$(printf "%-10s %-22s %-8s %-10s %-6s %s" "$local_label" "$seed_key" "$length_bucket" "$([ "$VALID" = "PASS" ] && echo "PASS" || echo "FAIL")" "$WC" "$([ "$VALID" = "PASS" ] && echo "-" || echo "$VALID")")")
        echo ""
    done
done

# =============================================================================
# SUMMARY TABLE
# =============================================================================

echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BOLD}${BLUE}  TRADITIONAL BAKEOFF SUMMARY${NC}"
echo -e "${BOLD}${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
printf "%-10s %-22s %-8s %-10s %-6s %s\n" "MODEL" "PASSAGE" "LENGTH" "VALIDATOR" "WORDS" "FAILURES"
printf "%-10s %-22s %-8s %-10s %-6s %s\n" "────────" "────────────────" "──────" "─────────" "─────" "────────"

for line in "${SUMMARY_LINES[@]}"; do
    echo "$line"
done

{
    printf "%-10s %-22s %-8s %-10s %-6s %s\n" "MODEL" "PASSAGE" "LENGTH" "VALIDATOR" "WORDS" "FAILURES"
    printf "%-10s %-22s %-8s %-10s %-6s %s\n" "────────" "────────────────" "──────" "─────────" "─────" "────────"
    for line in "${SUMMARY_LINES[@]}"; do
        echo "$line"
    done
} > "$RESULTS_DIR/bakeoff_traditional_summary.txt"

echo ""
echo -e "Results saved to: ${CYAN}$RESULTS_DIR/${NC}"
echo -e "${YELLOW}Review the story texts to compare quality — especially passage boundary compliance and Daniel Standard feel.${NC}"

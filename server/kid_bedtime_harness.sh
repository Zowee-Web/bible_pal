#!/bin/bash
# kid_bedtime_harness.sh
# ======================
# Harness wrapper for Kid Bedtime Safe story generation.
# Wraps Gemma generation with validation and automatic regeneration on failure.
#
# Usage: ./kid_bedtime_harness.sh <prompt_file> <output_file> [options]
#
# Options:
#   --max-attempts N    Maximum regeneration attempts (default: 3)
#   --model MODEL       Ollama model to use (default: gemma:7b)
#   --word-target N     Target word count (default: 600)
#   --length-minutes N  Story length bucket for word count validation (3, 5, 10, 15, 20)
#
# Exit codes:
#   0 = Success (kid-safe story generated)
#   1 = Failed after max attempts (story marked unsafe)
#   2 = Error (missing files, Ollama error, etc.)
#
# The harness:
#   1. Injects the Kid Bedtime Contract into the prompt
#   2. Calls Ollama/Gemma to generate story
#   3. Validates output against contract
#   4. If validation fails, regenerates with repair instruction
#   5. Repeats until valid or max attempts reached

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACT_FILE="$SCRIPT_DIR/../docs/prompts/kid_bedtime_contract.txt"
VALIDATOR="$SCRIPT_DIR/kid_bedtime_validator.sh"

# Default configuration
MAX_ATTEMPTS=3
MODEL="gemma:7b"
WORD_TARGET=600
LENGTH_MINUTES=""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================================
# Parse Arguments
# ============================================================================
usage() {
    echo "Usage: $0 <prompt_file> <output_file> [options]"
    echo ""
    echo "Options:"
    echo "  --max-attempts N    Maximum regeneration attempts (default: 3)"
    echo "  --model MODEL       Ollama model to use (default: gemma:7b)"
    echo "  --word-target N     Target word count (default: 600)"
    exit 2
}

if [[ $# -lt 2 ]]; then
    usage
fi

PROMPT_FILE="$1"
OUTPUT_FILE="$2"
shift 2

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --max-attempts)
            MAX_ATTEMPTS="$2"
            shift 2
            ;;
        --model)
            MODEL="$2"
            shift 2
            ;;
        --word-target)
            WORD_TARGET="$2"
            shift 2
            ;;
        --length-minutes)
            LENGTH_MINUTES="$2"
            shift 2
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}" >&2
            usage
            ;;
    esac
done

# ============================================================================
# Validate Prerequisites
# ============================================================================
if [[ ! -f "$PROMPT_FILE" ]]; then
    echo -e "${RED}Error: Prompt file not found: $PROMPT_FILE${NC}" >&2
    exit 2
fi

if [[ ! -f "$CONTRACT_FILE" ]]; then
    echo -e "${RED}Error: Contract file not found: $CONTRACT_FILE${NC}" >&2
    exit 2
fi

if [[ ! -f "$VALIDATOR" ]]; then
    echo -e "${RED}Error: Validator not found: $VALIDATOR${NC}" >&2
    exit 2
fi

if ! command -v ollama &> /dev/null; then
    echo -e "${RED}Error: Ollama not installed or not in PATH${NC}" >&2
    exit 2
fi

# ============================================================================
# Helper Functions
# ============================================================================
log_header() {
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Kid Bedtime Safe Harness - $1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

build_prompt() {
    local base_prompt="$1"
    local repair_instruction="${2:-}"

    # Read contract
    local contract
    contract=$(cat "$CONTRACT_FILE")

    # Build full prompt
    echo "=== KID BEDTIME STORY CONTRACT (MUST FOLLOW) ==="
    echo ""
    echo "$contract"
    echo ""
    echo "=== STORY REQUIREMENTS ==="
    echo ""
    echo "$base_prompt"
    echo ""
    echo "Target length: approximately $WORD_TARGET words."
    echo ""

    if [[ -n "$repair_instruction" ]]; then
        echo "=== REPAIR INSTRUCTION (CRITICAL) ==="
        echo ""
        echo "$repair_instruction"
        echo ""
    fi

    echo "Now write the story following all requirements above."
}

generate_story() {
    local full_prompt="$1"
    local temp_file="$2"

    # Call Ollama with the prompt
    echo "$full_prompt" | ollama run "$MODEL" > "$temp_file" 2>/dev/null

    # Return success if file has content
    if [[ -s "$temp_file" ]]; then
        return 0
    else
        return 1
    fi
}

build_repair_instruction() {
    local validation_json="$1"

    echo "YOUR PREVIOUS STORY FAILED VALIDATION. YOU MUST FIX THESE ISSUES:"
    echo ""

    # Extract forbidden words
    local forbidden
    forbidden=$(echo "$validation_json" | grep -o '"forbiddenWordsFound":\s*\[[^]]*\]' | sed 's/"forbiddenWordsFound":\s*\[//' | sed 's/\]//' | tr ',' '\n' | sed 's/"//g' | sed 's/^ *//')

    if [[ -n "$forbidden" ]]; then
        echo "FORBIDDEN WORDS DETECTED - Remove or replace these words:"
        echo "$forbidden" | while read -r word; do
            [[ -n "$word" ]] && echo "  - \"$word\""
        done
        echo ""
    fi

    # Extract structure violations
    local structure
    structure=$(echo "$validation_json" | grep -o '"structureViolations":\s*\[[^]]*\]' | sed 's/"structureViolations":\s*\[//' | sed 's/\]//' | tr ',' '\n' | sed 's/"//g' | sed 's/^ *//')

    if [[ -n "$structure" ]]; then
        echo "STRUCTURE PROBLEMS:"
        echo "$structure" | while read -r v; do
            [[ -n "$v" ]] && echo "  - $v"
        done
        echo ""
    fi

    # Extract other violations
    local other
    other=$(echo "$validation_json" | grep -o '"otherViolations":\s*\[[^]]*\]' | sed 's/"otherViolations":\s*\[//' | sed 's/\]//' | tr ',' '\n' | sed 's/"//g' | sed 's/^ *//')

    if [[ -n "$other" ]]; then
        echo "OTHER ISSUES:"
        echo "$other" | while read -r v; do
            [[ -n "$v" ]] && echo "  - $v"
        done
        echo ""
    fi

    echo "REWRITE THE ENTIRE STORY to fix ALL issues above."
    echo "Remember: This is for children ages 5-9 at BEDTIME."
    echo "It MUST be calm, peaceful, gentle, and sleep-inducing."
    echo "Use short, simple sentences. End with bedtime/sleep imagery."
}

# ============================================================================
# Main Harness Loop
# ============================================================================
log_header "Starting"

echo -e "${BLUE}Prompt file:${NC} $PROMPT_FILE"
echo -e "${BLUE}Output file:${NC} $OUTPUT_FILE"
echo -e "${BLUE}Max attempts:${NC} $MAX_ATTEMPTS"
echo -e "${BLUE}Model:${NC} $MODEL"
echo -e "${BLUE}Word target:${NC} $WORD_TARGET"
echo ""

# Read base prompt
BASE_PROMPT=$(cat "$PROMPT_FILE")

# Create temp files
TEMP_STORY=$(mktemp)
TEMP_VALIDATION=$(mktemp)
trap "rm -f '$TEMP_STORY' '$TEMP_VALIDATION'" EXIT

REPAIR_INSTRUCTION=""
ATTEMPT=1
IS_VALID=false
BEST_STORY=""

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
    log_header "Attempt $ATTEMPT of $MAX_ATTEMPTS"

    # Build prompt (with repair instruction if this is a retry)
    FULL_PROMPT=$(build_prompt "$BASE_PROMPT" "$REPAIR_INSTRUCTION")

    # Generate story
    echo -e "${BLUE}→ Calling Ollama ($MODEL)...${NC}"
    if ! generate_story "$FULL_PROMPT" "$TEMP_STORY"; then
        echo -e "${RED}✗ Ollama generation failed${NC}"
        ATTEMPT=$((ATTEMPT + 1))
        continue
    fi

    WORD_COUNT=$(wc -w < "$TEMP_STORY" | tr -d ' ')
    echo -e "${GREEN}✓ Generated story: $WORD_COUNT words${NC}"

    # Save as best attempt so far
    BEST_STORY=$(cat "$TEMP_STORY")

    # Validate story
    echo -e "${BLUE}→ Validating against Kid Bedtime Contract...${NC}"
    VALIDATOR_ARGS=("$TEMP_STORY")
    if [[ -n "$LENGTH_MINUTES" ]]; then
        VALIDATOR_ARGS+=("--length-minutes" "$LENGTH_MINUTES")
    fi
    if "$VALIDATOR" "${VALIDATOR_ARGS[@]}" > "$TEMP_VALIDATION" 2>&1; then
        echo -e "${GREEN}✓ Story PASSED validation!${NC}"
        IS_VALID=true
        break
    else
        echo -e "${YELLOW}✗ Story FAILED validation${NC}"

        # Build repair instruction for next attempt
        REPAIR_INSTRUCTION=$(build_repair_instruction "$(cat "$TEMP_VALIDATION")")

        echo -e "${YELLOW}  Will retry with repair instruction...${NC}"
    fi

    ATTEMPT=$((ATTEMPT + 1))
done

# ============================================================================
# Final Output
# ============================================================================
log_header "Complete"

if [[ "$IS_VALID" == "true" ]]; then
    echo -e "${GREEN}✓ Kid-safe story generated successfully!${NC}"
    echo -e "${GREEN}  Attempts: $ATTEMPT${NC}"

    # Save to output file
    echo "$BEST_STORY" > "$OUTPUT_FILE"
    echo -e "${GREEN}  Saved to: $OUTPUT_FILE${NC}"

    # Create metadata marker
    echo '{"kidSafe": true, "attempts": '$ATTEMPT', "validationFailures": []}' > "${OUTPUT_FILE}.meta.json"

    exit 0
else
    echo -e "${RED}✗ Failed to generate kid-safe story after $MAX_ATTEMPTS attempts${NC}"
    echo -e "${RED}  Story is marked as UNSAFE and should NOT be used${NC}"

    # Save best attempt with unsafe marker
    echo "$BEST_STORY" > "$OUTPUT_FILE"

    # Extract final violations from last validation
    FINAL_VIOLATIONS=$(cat "$TEMP_VALIDATION" 2>/dev/null || echo '{}')

    # Create metadata marker indicating unsafe
    cat > "${OUTPUT_FILE}.meta.json" << EOF
{
  "kidSafe": false,
  "attempts": $MAX_ATTEMPTS,
  "validationFailures": $FINAL_VIOLATIONS
}
EOF

    echo -e "${RED}  Saved unsafe story to: $OUTPUT_FILE${NC}"
    echo -e "${RED}  Metadata: ${OUTPUT_FILE}.meta.json${NC}"

    exit 1
fi

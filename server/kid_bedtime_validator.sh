#!/bin/bash
# kid_bedtime_validator.sh
# ========================
# Post-generation validator for Kid Bedtime Safe stories.
# Checks story text against the Kid Bedtime Contract requirements.
#
# Usage: ./kid_bedtime_validator.sh <story_file.txt> [--length-minutes N]
# Options:
#   --length-minutes N   Target story length for word count validation (3, 5, 10, 15, 20)
# Exit codes:
#   0 = Valid (kid-safe)
#   1 = Invalid (contains forbidden words or structure issues)
#   2 = Error (file not found, etc.)
#
# Output: JSON object with validation results

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORBIDDEN_FILE="$SCRIPT_DIR/kid_bedtime_forbidden.txt"
CONTRACT_FILE="$SCRIPT_DIR/../docs/prompts/kid_bedtime_contract.txt"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Get word count range for a given length in minutes
# Returns: "MIN_WORDS MAX_WORDS" or empty string if unknown
get_word_count_range() {
    local minutes="$1"
    case "$minutes" in
        3)  echo "270 400" ;;
        5)  echo "540 720" ;;
        10) echo "900 1200" ;;
        15) echo "1350 1800" ;;
        20) echo "1800 2400" ;;
        *)  echo "" ;;
    esac
}

# Check arguments
if [[ $# -lt 1 ]]; then
    echo "Usage: $0 <story_file.txt> [--length-minutes N]" >&2
    exit 2
fi

STORY_FILE="$1"
LENGTH_MINUTES=""
shift

# Parse optional arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --length-minutes)
            LENGTH_MINUTES="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 2
            ;;
    esac
done

if [[ ! -f "$STORY_FILE" ]]; then
    echo -e "${RED}Error: Story file not found: $STORY_FILE${NC}" >&2
    exit 2
fi

if [[ ! -f "$FORBIDDEN_FILE" ]]; then
    echo -e "${RED}Error: Forbidden vocabulary file not found: $FORBIDDEN_FILE${NC}" >&2
    exit 2
fi

# Read story content
STORY_TEXT=$(cat "$STORY_FILE")
STORY_LOWER=$(echo "$STORY_TEXT" | tr '[:upper:]' '[:lower:]')

# Initialize result variables
FORBIDDEN_FOUND=()
STRUCTURE_VIOLATIONS=()
OTHER_VIOLATIONS=()
IS_VALID=true

# ============================================================================
# Check 1: Forbidden Words
# ============================================================================
while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    # Skip empty lines and comments
    [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue

    # Convert to lowercase for matching
    pattern_lower=$(echo "$pattern" | tr '[:upper:]' '[:lower:]')

    # Check if pattern exists in story (word boundary matching with grep)
    if echo "$STORY_LOWER" | grep -qiw "$pattern_lower" 2>/dev/null; then
        FORBIDDEN_FOUND+=("$pattern")
        IS_VALID=false
    fi
done < "$FORBIDDEN_FILE"

# ============================================================================
# Check 2: Story Structure (minimum sections)
# ============================================================================
# Count paragraphs (sections separated by blank lines, min 50 chars each)
PARAGRAPH_COUNT=$(echo "$STORY_TEXT" | awk -v RS='\n\n+' 'length > 50 {count++} END {print count+0}')

if [[ "$PARAGRAPH_COUNT" -lt 3 ]]; then
    STRUCTURE_VIOLATIONS+=("Story needs at least 3 distinct sections (found $PARAGRAPH_COUNT)")
    IS_VALID=false
fi

# Check word count based on target length
WORD_COUNT=$(echo "$STORY_TEXT" | wc -w | tr -d ' ')

WORD_RANGE=""
if [[ -n "$LENGTH_MINUTES" ]]; then
    WORD_RANGE=$(get_word_count_range "$LENGTH_MINUTES")
fi

if [[ -n "$LENGTH_MINUTES" ]] && [[ -n "$WORD_RANGE" ]]; then
    # Use length-specific word count range
    read -r MIN_WORDS MAX_WORDS <<< "$WORD_RANGE"

    if [[ "$WORD_COUNT" -lt "$MIN_WORDS" ]]; then
        STRUCTURE_VIOLATIONS+=("Story too short for ${LENGTH_MINUTES}min ($WORD_COUNT words, need $MIN_WORDS-$MAX_WORDS). Expand sections 2-4 with more gentle, calm details.")
        IS_VALID=false
    elif [[ "$WORD_COUNT" -gt "$MAX_WORDS" ]]; then
        STRUCTURE_VIOLATIONS+=("Story too long for ${LENGTH_MINUTES}min ($WORD_COUNT words, max $MAX_WORDS)")
        IS_VALID=false
    fi
else
    # Default: minimum 200 words
    if [[ "$WORD_COUNT" -lt 200 ]]; then
        STRUCTURE_VIOLATIONS+=("Story too short ($WORD_COUNT words, minimum 200)")
        IS_VALID=false
    fi
fi

# ============================================================================
# Check 3: Bedtime Closing Signal
# ============================================================================
# Get last 200 characters
CLOSING_SECTION=$(echo "$STORY_TEXT" | tail -c 200 | tr '[:upper:]' '[:lower:]')

# Check for bedtime/sleep-related signals
BEDTIME_SIGNALS="sleep|slept|sleeping|rest|rested|resting|dream|dreams|dreaming|peaceful|peace|calm|quiet|softly|gently|warm|cozy|safe|eyes closed|closed eyes|night|stars|moon|blanket|pillow|bed|goodnight|good night"

if ! echo "$CLOSING_SECTION" | grep -qiE "$BEDTIME_SIGNALS"; then
    OTHER_VIOLATIONS+=("Story ending lacks bedtime/sleep signals")
    IS_VALID=false
fi

# ============================================================================
# Check 4: Average Sentence Length
# ============================================================================
# Count sentences (roughly - by counting .!?)
SENTENCE_COUNT=$(echo "$STORY_TEXT" | grep -o '[.!?]' | wc -l | tr -d ' ')

if [[ "$SENTENCE_COUNT" -gt 0 ]]; then
    AVG_WORDS_PER_SENTENCE=$((WORD_COUNT / SENTENCE_COUNT))

    if [[ "$AVG_WORDS_PER_SENTENCE" -gt 15 ]]; then
        OTHER_VIOLATIONS+=("Sentences too long (avg ~$AVG_WORDS_PER_SENTENCE words, max 15)")
        IS_VALID=false
    fi
else
    AVG_WORDS_PER_SENTENCE=0
fi

# ============================================================================
# Output Results
# ============================================================================
# Build JSON output
echo "{"
echo "  \"isValid\": $IS_VALID,"
echo "  \"storyFile\": \"$STORY_FILE\","
echo "  \"wordCount\": $WORD_COUNT,"
echo "  \"paragraphCount\": $PARAGRAPH_COUNT,"
echo "  \"avgWordsPerSentence\": $AVG_WORDS_PER_SENTENCE,"

# Forbidden words array
echo -n "  \"forbiddenWordsFound\": ["
if [[ ${#FORBIDDEN_FOUND[@]} -gt 0 ]]; then
    first=true
    for word in "${FORBIDDEN_FOUND[@]}"; do
        if $first; then
            first=false
        else
            echo -n ", "
        fi
        echo -n "\"$word\""
    done
fi
echo "],"

# Structure violations array
echo -n "  \"structureViolations\": ["
if [[ ${#STRUCTURE_VIOLATIONS[@]} -gt 0 ]]; then
    first=true
    for v in "${STRUCTURE_VIOLATIONS[@]}"; do
        if $first; then
            first=false
        else
            echo -n ", "
        fi
        echo -n "\"$v\""
    done
fi
echo "],"

# Other violations array
echo -n "  \"otherViolations\": ["
if [[ ${#OTHER_VIOLATIONS[@]} -gt 0 ]]; then
    first=true
    for v in "${OTHER_VIOLATIONS[@]}"; do
        if $first; then
            first=false
        else
            echo -n ", "
        fi
        echo -n "\"$v\""
    done
fi
echo "]"

echo "}"

# ============================================================================
# Terminal Summary
# ============================================================================
if [[ "$IS_VALID" == "true" ]]; then
    echo -e "${GREEN}✓ Story PASSED kid bedtime validation${NC}" >&2
    exit 0
else
    echo -e "${RED}✗ Story FAILED kid bedtime validation${NC}" >&2

    if [[ ${#FORBIDDEN_FOUND[@]} -gt 0 ]]; then
        echo -e "${YELLOW}  Forbidden words: ${FORBIDDEN_FOUND[*]}${NC}" >&2
    fi

    if [[ ${#STRUCTURE_VIOLATIONS[@]} -gt 0 ]]; then
        for v in "${STRUCTURE_VIOLATIONS[@]}"; do
            echo -e "${YELLOW}  Structure: $v${NC}" >&2
        done
    fi

    if [[ ${#OTHER_VIOLATIONS[@]} -gt 0 ]]; then
        for v in "${OTHER_VIOLATIONS[@]}"; do
            echo -e "${YELLOW}  Other: $v${NC}" >&2
        done
    fi

    exit 1
fi

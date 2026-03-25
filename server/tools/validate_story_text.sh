#!/usr/bin/env bash
# validate_story_text.sh
# Pre-audio validation for story text files.
# Catches objective issues before spending ElevenLabs credits.
#
# Usage: ./validate_story_text.sh <story_dir>
# Example: ./validate_story_text.sh assets/stories/creative/501
#
# Checks:
#   - All required text files exist and are non-empty
#   - Word counts within length bucket ranges
#   - No duplicate paragraphs
#   - No duplicate sentences (threshold: 2+ occurrences)
#   - Protagonist name consistency across all files
#   - Reflection uses same character name as stories

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

ERRORS=0
WARNINGS=0

error() {
    echo -e "  ${RED}FAIL${NC}  $1"
    ERRORS=$((ERRORS + 1))
}

warn() {
    echo -e "  ${YELLOW}WARN${NC}  $1"
    WARNINGS=$((WARNINGS + 1))
}

pass() {
    echo -e "  ${GREEN}OK${NC}    $1"
}

# Parse args
if [[ $# -lt 1 ]]; then
    echo -e "${RED}Usage: $0 <story_dir>${NC}"
    echo ""
    echo "Example: $0 assets/stories/creative/501"
    exit 1
fi

STORY_DIR="$1"

# Resolve to absolute path if relative
if [[ ! "$STORY_DIR" = /* ]]; then
    STORY_DIR="$PROJECT_ROOT/$STORY_DIR"
fi

if [[ ! -d "$STORY_DIR" ]]; then
    echo -e "${RED}Error: Directory not found: $STORY_DIR${NC}"
    exit 1
fi

# Find meta file
META_FILE=$(find "$STORY_DIR" -name "meta_*.json" -maxdepth 1 | head -1)
if [[ -z "$META_FILE" ]]; then
    echo -e "${RED}Error: No meta file found in $STORY_DIR${NC}"
    exit 1
fi

# Extract info from meta
STORY_ID=$(jq -r '.storyId' "$META_FILE")
MODE=$(jq -r '.mode' "$META_FILE")
KID_FRIENDLY=$(jq -r '.kidFriendly' "$META_FILE")

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Story Text Validation — Story $STORY_ID ($MODE)${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# ─── Word count ranges by mode ───────────────────────────────────
# From STORY_FACTORY.md
get_word_range() {
    local mode="$1"
    local kid="$2"
    local length="$3"

    if [[ "$mode" == "traditional" ]]; then
        case "$length" in
            short) echo "300 500" ;;
            full)  echo "501 900" ;;
            long)  echo "901 1500" ;;
        esac
    elif [[ "$kid" == "true" ]]; then
        case "$length" in
            short) echo "200 500" ;;
            full)  echo "501 900" ;;
            long)  echo "901 1400" ;;
        esac
    else
        case "$length" in
            short) echo "200 400" ;;
            full)  echo "401 700" ;;
            long)  echo "701 1100" ;;
        esac
    fi
}

# ─── Check 1: Required files exist ──────────────────────────────
echo -e "${BOLD}Files${NC}"

SHORT_FILE=$(jq -r '.files.short.storyText // empty' "$META_FILE")
FULL_FILE=$(jq -r '.files.full.storyText // empty' "$META_FILE")
LONG_FILE=$(jq -r '.files.long.storyText // empty' "$META_FILE")
REFL_FILE=$(jq -r '.files.reflection.reflectionText // empty' "$META_FILE")

declare -a TEXT_FILES=()
declare -a TEXT_LABELS=()
declare -a TEXT_LENGTHS=()

for pair in "short:$SHORT_FILE" "full:$FULL_FILE" "long:$LONG_FILE" "reflection:$REFL_FILE"; do
    label="${pair%%:*}"
    file="${pair#*:}"

    if [[ -z "$file" ]]; then
        error "$label: not defined in meta"
        continue
    fi

    filepath="$STORY_DIR/$file"
    if [[ ! -f "$filepath" ]]; then
        error "$label: file missing — $file"
    elif [[ ! -s "$filepath" ]]; then
        error "$label: file is empty — $file"
    else
        pass "$label: $file"
        TEXT_FILES+=("$filepath")
        TEXT_LABELS+=("$label")
        TEXT_LENGTHS+=("$label")
    fi
done

echo ""

# ─── Check 2: Word counts ───────────────────────────────────────
echo -e "${BOLD}Word counts${NC}"

for i in "${!TEXT_FILES[@]}"; do
    filepath="${TEXT_FILES[$i]}"
    label="${TEXT_LABELS[$i]}"
    wc_actual=$(wc -w < "$filepath" | tr -d ' ')

    if [[ "$label" == "reflection" ]]; then
        if (( wc_actual > 200 )); then
            warn "reflection: $wc_actual words (above 200)"
        elif (( wc_actual < 10 )); then
            error "reflection: $wc_actual words (min 10)"
        else
            pass "reflection: $wc_actual words"
        fi
        continue
    fi

    range=$(get_word_range "$MODE" "$KID_FRIENDLY" "$label")
    min_words=$(echo "$range" | awk '{print $1}')
    max_words=$(echo "$range" | awk '{print $2}')

    if (( wc_actual < min_words )); then
        warn "$label: $wc_actual words (below $min_words for $MODE $label)"
    elif (( wc_actual > max_words )); then
        warn "$label: $wc_actual words (above $max_words for $MODE $label)"
    else
        pass "$label: $wc_actual words (range: ${min_words}-${max_words})"
    fi
done

echo ""

# ─── Check 3: Duplicate paragraphs ──────────────────────────────
echo -e "${BOLD}Duplicate paragraphs${NC}"

found_dupes=0
for i in "${!TEXT_FILES[@]}"; do
    filepath="${TEXT_FILES[$i]}"
    label="${TEXT_LABELS[$i]}"

    # Split on blank lines, normalize whitespace, skip section dividers, find duplicates
    dupes=$(awk 'BEGIN{RS=""; ORS="\n"} {gsub(/[[:space:]]+/, " "); print}' "$filepath" \
        | grep -vE '^[⸻─━—\-]{1,5}$' \
        | awk 'NF >= 3' \
        | sort | uniq -d)

    if [[ -n "$dupes" ]]; then
        error "$label: duplicate paragraph found"
        echo -e "         ${RED}$(echo "$dupes" | head -c 100)...${NC}"
        found_dupes=1
    fi
done

if [[ "$found_dupes" -eq 0 ]]; then
    pass "No duplicate paragraphs"
fi

echo ""

# ─── Check 4: Duplicate sentences ───────────────────────────────
echo -e "${BOLD}Duplicate sentences${NC}"

found_sent_dupes=0
for i in "${!TEXT_FILES[@]}"; do
    filepath="${TEXT_FILES[$i]}"
    label="${TEXT_LABELS[$i]}"

    # Split on sentence-ending punctuation, normalize, find duplicates
    dupes=$(sed 's/[.!?]/\n/g' "$filepath" \
        | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//' \
        | awk 'NF >= 4' \
        | sort | uniq -d)

    if [[ -n "$dupes" ]]; then
        error "$label: repeated sentence(s)"
        echo "$dupes" | head -3 | while read -r line; do
            echo -e "         ${RED}\"$(echo "$line" | head -c 80)\"${NC}"
        done
        found_sent_dupes=1
    fi
done

if [[ "$found_sent_dupes" -eq 0 ]]; then
    pass "No duplicate sentences"
fi

echo ""

# ─── Check 5: Protagonist consistency ───────────────────────────
echo -e "${BOLD}Protagonist consistency${NC}"

# Extract likely protagonist: most frequent capitalized name (not common words)
# that appears in dialogue or as a subject
COMMON_SKIP="The|And|But|She|He|They|Her|His|Him|Its|It|That|This|When|Then|As|In|On|At|For|With|From|One|Two|God|Lord|Jesus|Christ|Bible|Some|Yet|Still|Not|Now|All|Who|What|How|Why|Where|Each|Every|Your|You|Our|Their|Master|Ninety|Nine"

extract_names() {
    local file="$1"
    grep -oE '\b[A-Z][a-z]{2,}\b' "$file" \
        | grep -vE "^($COMMON_SKIP)$" \
        | sort | uniq -c | sort -rn | head -5 \
        | awk '$1 >= 3 {print $2}'
}

if [[ "$MODE" == "traditional" ]]; then
    pass "Skipped for traditional stories (biblical characters use varied references)"
else
    # Get the top name from the full story (most representative)
    FULL_PATH=""
    for i in "${!TEXT_FILES[@]}"; do
        if [[ "${TEXT_LABELS[$i]}" == "full" ]]; then
            FULL_PATH="${TEXT_FILES[$i]}"
            break
        fi
    done

    if [[ -n "$FULL_PATH" ]]; then
        MAIN_NAME=$(extract_names "$FULL_PATH" | head -1)

        if [[ -n "$MAIN_NAME" ]]; then
            name_ok=1
            for i in "${!TEXT_FILES[@]}"; do
                filepath="${TEXT_FILES[$i]}"
                label="${TEXT_LABELS[$i]}"

                if ! grep -q "$MAIN_NAME" "$filepath"; then
                    if [[ "$label" == "reflection" ]]; then
                        warn "$label: protagonist '$MAIN_NAME' not found (reflections often use generic voice)"
                    else
                        warn "$label: protagonist '$MAIN_NAME' not found"
                    fi
                    name_ok=0
                fi
            done

            if [[ "$name_ok" -eq 1 ]]; then
                pass "Protagonist '$MAIN_NAME' appears in all files"
            fi
        else
            pass "No dominant name detected (3+ occurrences required)"
        fi
    else
        warn "No full story file to detect protagonist from"
    fi
fi

echo ""

# ─── Check 6: World consistency (basic) ─────────────────────────
echo -e "${BOLD}World consistency${NC}"

# Flag if a character is described as both a plant/object AND a human
world_issue=0
for i in "${!TEXT_FILES[@]}"; do
    filepath="${TEXT_FILES[$i]}"
    label="${TEXT_LABELS[$i]}"

    has_plant=$(grep -ciE 'seedling|sprout|petal|root|soil|bloomed|wilted' "$filepath" || true)
    has_human=$(grep -ciE 'walked|ran|said|whispered|smiled|laughed|hand|fingers|toes|barefoot' "$filepath" || true)

    if (( has_plant > 3 && has_human > 3 )); then
        warn "$label: mixed plant/human language detected ($has_plant plant refs, $has_human human refs) — check world consistency"
        world_issue=1
    fi
done

if [[ "$world_issue" -eq 0 ]]; then
    pass "No world-switching detected"
fi

echo ""

# ─── Summary ────────────────────────────────────────────────────
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ "$ERRORS" -gt 0 ]]; then
    echo -e "${RED}  FAILED${NC}  $ERRORS error(s), $WARNINGS warning(s)"
    echo -e "${RED}  Do not generate audio until errors are fixed.${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 1
elif [[ "$WARNINGS" -gt 0 ]]; then
    echo -e "${YELLOW}  PASSED with warnings${NC}  $WARNINGS warning(s)"
    echo -e "${YELLOW}  Review warnings before generating audio.${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
else
    echo -e "${GREEN}  PASSED${NC}  All checks clean"
    echo -e "${GREEN}  Ready for audio generation.${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    exit 0
fi
#!/bin/bash
# Quality gates for generated kid-friendly Bible stories
# Run after full batch generation to catch silent failures

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STORIES_DIR="$PROJECT_ROOT/assets/stories"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}  Quality Gates for Kid-Friendly Bible Stories${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

PASS_COUNT=0
FAIL_COUNT=0

# Gate 1: Check for scene heading leaks
echo -e "${BLUE}[1/4] Checking for scene heading leaks...${NC}"
if grep -RIn -- "##\s*Scene\|^Scene\s\+[0-9]\|^CHAPTER\s\+[0-9]\|^Chapter\s\+[0-9]" "$STORIES_DIR"/parable_*_kid_trad.txt 2>/dev/null; then
    echo -e "${RED}✗ FAIL: Found scene headings in story text${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    echo -e "${GREEN}✓ PASS: No scene headings found${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
fi
echo ""

# Gate 2: Check for bullet lists
echo -e "${BLUE}[2/4] Checking for bullet list formatting...${NC}"
if grep -RIn -- "^\s*[-*]\s" "$STORIES_DIR"/parable_*_kid_trad.txt 2>/dev/null; then
    echo -e "${RED}✗ FAIL: Found bullet lists in story text${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    echo -e "${GREEN}✓ PASS: No bullet lists found${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
fi
echo ""

# Gate 3: Verify file count
echo -e "${BLUE}[3/4] Verifying file count...${NC}"
EXPECTED_COUNT=16
ACTUAL_COUNT=$(ls -1 "$STORIES_DIR"/parable_*_kid_trad.txt 2>/dev/null | wc -l | tr -d ' ')

if [[ "$ACTUAL_COUNT" -eq "$EXPECTED_COUNT" ]]; then
    echo -e "${GREEN}✓ PASS: Found $ACTUAL_COUNT/$EXPECTED_COUNT story files${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
elif [[ "$ACTUAL_COUNT" -lt "$EXPECTED_COUNT" && "$ACTUAL_COUNT" -ge 1 ]]; then
    echo -e "${YELLOW}⚠ WARNING: Found $ACTUAL_COUNT/$EXPECTED_COUNT files (partial batch)${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗ FAIL: Expected $EXPECTED_COUNT files, found $ACTUAL_COUNT${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# Gate 4: Check for invented content and structural leaks
echo -e "${BLUE}[4/5] Checking for invented content patterns and structural leaks...${NC}"

# A) Common hallucination patterns (Biblical drift)
# NOTE: These patterns must be specific enough to avoid false positives on legitimate Biblical content
HALLUCINATION_PATTERNS=(
    "\bmagic spell"
    "\bmagical powers"
    "\bmagical staff"
    "\bmagical object"
    "\bportal\b"
    "\bwizard\b"
    "\bdragon\b"
    "\benchanted object"
    "\bmystical powers"
    "\bamulet\b"
    "new prophet appeared"
    "mysterious stranger arrived"
    "army of villagers"
    "extra battle"
    "second giant"
    "multiple giants"
    "hidden tunnel"
    "cave chase"
    "secret passage"
)

# B) Structural non-prose leaks
STRUCTURAL_PATTERNS=(
    "^OK$"
    "^OK\."
    "^Resolution:"
    "^Chapter [0-9]"
    "^Scene [0-9]"
    "^## Scene"
    "^## Chapter"
    "^\s*[-*]\s"
)

INVENTED_COUNT=0
FOUND_ISSUES=()

# Check hallucination patterns
for pattern in "${HALLUCINATION_PATTERNS[@]}"; do
    while IFS= read -r match; do
        filename=$(echo "$match" | cut -d: -f1)
        line_num=$(echo "$match" | cut -d: -f2)
        content=$(echo "$match" | cut -d: -f3-)
        echo -e "${YELLOW}  • $(basename "$filename"):$line_num - Pattern '$pattern' found: ${content:0:60}...${NC}"
        FOUND_ISSUES+=("$filename:$line_num - hallucination '$pattern'")
        INVENTED_COUNT=$((INVENTED_COUNT + 1))
    done < <(grep -iEn "$pattern" "$STORIES_DIR"/parable_*_kid_trad.txt 2>/dev/null || true)
done

# Check structural patterns
for pattern in "${STRUCTURAL_PATTERNS[@]}"; do
    while IFS= read -r match; do
        filename=$(echo "$match" | cut -d: -f1)
        line_num=$(echo "$match" | cut -d: -f2)
        content=$(echo "$match" | cut -d: -f3-)
        echo -e "${YELLOW}  • $(basename "$filename"):$line_num - Structural leak '$pattern' found: ${content:0:60}...${NC}"
        FOUND_ISSUES+=("$filename:$line_num - structural leak '$pattern'")
        INVENTED_COUNT=$((INVENTED_COUNT + 1))
    done < <(grep -En "$pattern" "$STORIES_DIR"/parable_*_kid_trad.txt 2>/dev/null || true)
done

if [[ $INVENTED_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS: No invented content or structural leaks detected${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗ FAIL: Found $INVENTED_COUNT issues (${#FOUND_ISSUES[@]} total matches)${NC}"
    echo -e "${RED}  Stories contain hallucinations or structural artifacts${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# Gate 5: Check for empty or truncated files
echo -e "${BLUE}[5/6] Checking for empty or very short files...${NC}"
MIN_WORDS=400
EMPTY_FILES=0

for file in "$STORIES_DIR"/parable_*_kid_trad.txt; do
    if [[ ! -f "$file" ]]; then
        continue
    fi

    word_count=$(wc -w < "$file" | tr -d ' ')
    if [[ $word_count -lt $MIN_WORDS ]]; then
        echo -e "${YELLOW}  WARNING: $(basename "$file") has only $word_count words (expected >$MIN_WORDS)${NC}"
        EMPTY_FILES=$((EMPTY_FILES + 1))
    fi
done

if [[ $EMPTY_FILES -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS: All files have adequate length${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗ FAIL: $EMPTY_FILES files are suspiciously short${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# Gate 6: Bible Facts Anchor Check (story-specific keyword validation)
echo -e "${BLUE}[6/6] Checking Bible Facts Anchors (story-specific keywords)...${NC}"

# Function to get required anchors for a story ID
get_story_anchors() {
    local id=$1
    case "$id" in
        101) echo "David|Goliath|stone|sling" ;;  # David and Goliath
        102) echo "Daniel|lions|den" ;;  # Daniel in the Lions' Den
        103) echo "Noah|ark|flood|rainbow" ;;  # Noah and the Rainbow Promise
        104) echo "Samaritan|inn|neighbor" ;;  # The Good Samaritan
        105) echo "Jesus|storm|disciples|boat" ;;  # Jesus Calms the Storm
        106) echo "shepherd|sheep|lost" ;;  # The Lost Sheep
        107) echo "Jesus|loaves|fish|five thousand" ;;  # Feeding the Five Thousand
        108) echo "Joseph|brothers|Egypt" ;;  # Joseph Forgives His Brothers
        109) echo "Ruth|Naomi|Boaz" ;;  # Ruth's Loyal Kindness
        110) echo "Esther|king|Haman" ;;  # Esther's Brave Choice
        111) echo "builder|rock|sand|house" ;;  # Wise and Foolish Builders
        112) echo "prodigal|son|father" ;;  # The Prodigal Son
        113) echo "Jonah|fish|Nineveh" ;;  # Jonah Learns About Mercy
        114) echo "Samuel|Eli|voice|Lord" ;;  # The Boy Samuel Hears God
        115) echo "sower|seed|soil" ;;  # The Parable of the Sower
        116) echo "Zacchaeus|tree|tax" ;;  # Zacchaeus Meets Jesus
        *) echo "" ;;
    esac
}

ANCHOR_FAIL_COUNT=0
ANCHOR_CHECKED=0

for file in "$STORIES_DIR"/parable_*_kid_trad.txt; do
    if [[ ! -f "$file" ]]; then
        continue
    fi

    # Extract story ID from filename (e.g., parable_101_... -> 101)
    story_id=$(basename "$file" | sed -E 's/parable_([0-9]+)_.*/\1/')

    # Get anchors for this story
    anchors=$(get_story_anchors "$story_id")

    # Skip if no anchor defined for this story
    if [[ -z "$anchors" ]]; then
        continue
    fi

    ANCHOR_CHECKED=$((ANCHOR_CHECKED + 1))

    # Check if ALL required keywords are present (case-insensitive)
    missing_keywords=()
    IFS='|' read -ra keywords <<< "$anchors"
    for keyword in "${keywords[@]}"; do
        if ! grep -iq "$keyword" "$file"; then
            missing_keywords+=("$keyword")
        fi
    done

    if [[ ${#missing_keywords[@]} -gt 0 ]]; then
        echo -e "${YELLOW}  • $(basename "$file") - MISSING keywords: ${missing_keywords[*]}${NC}"
        ANCHOR_FAIL_COUNT=$((ANCHOR_FAIL_COUNT + 1))
    fi
done

if [[ $ANCHOR_FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓ PASS: All $ANCHOR_CHECKED stories contain required Bible fact keywords${NC}"
    PASS_COUNT=$((PASS_COUNT + 1))
else
    echo -e "${RED}✗ FAIL: $ANCHOR_FAIL_COUNT/$ANCHOR_CHECKED stories missing required keywords${NC}"
    echo -e "${RED}  Stories may have drifted from Biblical source material${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
echo ""

# Gate 7: Kid Safety Scan (Layer 2 of Kid Safety Contract Invariant)
echo -e "${BLUE}[7/7] Kid Safety Scan - checking kid-friendly stories for inappropriate content...${NC}"

# Load blocklist patterns from centralized file
BLOCKLIST_FILE="$SCRIPT_DIR/kid_safety_blocklist.txt"

if [[ ! -f "$BLOCKLIST_FILE" ]]; then
    echo -e "${RED}✗ FAIL: Blocklist file not found: $BLOCKLIST_FILE${NC}"
    FAIL_COUNT=$((FAIL_COUNT + 1))
else
    # Extract non-comment, non-empty lines from blocklist
    SAFETY_PATTERNS=()
    while IFS= read -r line; do
        # Skip empty lines and comments
        if [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]]; then
            continue
        fi
        SAFETY_PATTERNS+=("$line")
    done < "$BLOCKLIST_FILE"

    echo -e "${BLUE}  Loaded ${#SAFETY_PATTERNS[@]} blocklist patterns${NC}"

    # Find all kid-safe story files
    KID_SAFE_FILES=("$STORIES_DIR"/parable_*_kid_*.txt)

    # Check if any kid-safe files exist
    if [[ ! -f "${KID_SAFE_FILES[0]}" ]]; then
        echo -e "${YELLOW}⚠ WARNING: No kid-safe story files found (this is OK if not generating kid content)${NC}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        SAFETY_VIOLATIONS=0
        VIOLATION_DETAILS=()

        # Scan each kid-safe file
        for file in "${KID_SAFE_FILES[@]}"; do
            if [[ ! -f "$file" ]]; then
                continue
            fi

            # Check each pattern against the file
            for pattern in "${SAFETY_PATTERNS[@]}"; do
                # Use grep with line numbers, case-insensitive
                while IFS= read -r match; do
                    filename=$(basename "$file")
                    line_num=$(echo "$match" | cut -d: -f1)
                    content=$(echo "$match" | cut -d: -f2-)

                    echo -e "${RED}  ✗ $filename:$line_num - Pattern '$pattern' found: ${content:0:60}...${NC}"
                    VIOLATION_DETAILS+=("$filename:$line_num - '$pattern'")
                    SAFETY_VIOLATIONS=$((SAFETY_VIOLATIONS + 1))
                done < <(grep -iEn "$pattern" "$file" 2>/dev/null || true)
            done
        done

        if [[ $SAFETY_VIOLATIONS -eq 0 ]]; then
            echo -e "${GREEN}✓ PASS: No inappropriate content detected in kid-safe stories${NC}"
            PASS_COUNT=$((PASS_COUNT + 1))
        else
            echo -e "${RED}✗ FAIL: Found $SAFETY_VIOLATIONS inappropriate content violations in kid-safe stories${NC}"
            echo -e "${RED}  Kid-safe stories contain content forbidden by blocklist${NC}"
            echo -e "${RED}  Review and remove inappropriate content before deployment${NC}"
            FAIL_COUNT=$((FAIL_COUNT + 1))
        fi
    fi
fi
echo ""

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓✓✓ ALL QUALITY GATES PASSED ($PASS_COUNT/7)${NC}"
    exit 0
else
    echo -e "${RED}✗ QUALITY GATES FAILED: $FAIL_COUNT failures, $PASS_COUNT passes${NC}"
    exit 1
fi

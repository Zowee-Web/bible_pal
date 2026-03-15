#!/usr/bin/env bash
# test_opening_validation.sh — Tests for validate_and_retry_opening()
# Run: bash server/test_opening_validation.sh
#
# Tests the word-count guard: opening retry must not discard a
# word-count-compliant draft in favor of a non-compliant retry.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0
FAIL=0
TOTAL=0

# --- Color stubs (suppress ANSI in test output) ---
RED="" GREEN="" YELLOW="" BLUE="" CYAN="" NC=""

# --- Test helpers ---
assert_eq() {
    local label="$1" expected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$expected" = "$actual" ]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label"
        echo "  expected: $expected"
        echo "  actual:   $actual"
        FAIL=$((FAIL + 1))
    fi
}

# --- Source only the functions we need ---
# We need: check_opening_compliance, get_opening_anchor, extract_first_sentence,
#           validate_and_retry_opening, sanitize_story_text

# extract_first_sentence (copied dependency)
extract_first_sentence() {
    local text="$1"
    echo "$text" | sed -E 's/([.!?])[[:space:]].*/\1/' | head -1
}

# Source from generate_v2_batch.sh — extract just the functions
eval "$(sed -n '/^check_opening_compliance()/,/^}/p' "$SCRIPT_DIR/generate_v2_batch.sh")"
eval "$(sed -n '/^get_opening_anchor()/,/^}/p' "$SCRIPT_DIR/generate_v2_batch.sh")"
eval "$(sed -n '/^validate_and_retry_opening()/,/^}/p' "$SCRIPT_DIR/generate_v2_batch.sh")"

# sanitize_story_text stub — pass through (real sanitizer removes metadata lines)
sanitize_story_text() { echo "$1"; }

# ============================================================
# Mock control: set MOCK_RETRY_TEXT before calling validate_and_retry_opening
# to control what generate_text returns on retry.
# ============================================================
MOCK_RETRY_TEXT=""

generate_text() {
    echo "$MOCK_RETRY_TEXT"
}

echo "========================================================="
echo "Opening Validation Tests"
echo "========================================================="

# --- Test 1: Original passes opening → returned as-is ---
echo "Test 1: Original passes opening validation — returned unchanged"
result=$(validate_and_retry_opening '"Hello," said the man.' "dialogue" "prompt" "1200" "short" "200" "400" 2>/dev/null)
assert_eq "dialogue-compliant original returned" '"Hello," said the man.' "$result"

# --- Test 2: Original fails opening, retry passes both opening + word count → retry accepted ---
echo "Test 2: Retry passes opening + word count → retry accepted"
# Original: 10 words, fails dialogue (no quote), range 5-50
# Retry: 8 words, passes dialogue (starts with quote), in range
MOCK_RETRY_TEXT='"Why do you worry so much?" the old woman asked gently.'
result=$(validate_and_retry_opening "The sun rose over the hills and the man walked slowly onward." "dialogue" "prompt" "1200" "short" "5" "50" 2>/dev/null)
assert_eq "retry accepted when compliant" "$MOCK_RETRY_TEXT" "$result"

# --- Test 3: REGRESSION — Original passes word count, retry fails word count → keep original ---
echo "Test 3: Retry fails word count → original kept (regression guard)"
# Original: fails dialogue (no quote), but 15 words — in range 10-20
original_text="The farmer looked across his field and wondered what the harvest would bring this year."
# Retry: passes dialogue but only 5 words — below min_wc of 10
MOCK_RETRY_TEXT='"Hello," said she briefly.'
result=$(validate_and_retry_opening "$original_text" "dialogue" "prompt" "1200" "short" "10" "20" 2>/dev/null)
assert_eq "original kept when retry breaks word count" "$original_text" "$result"

# --- Test 4: Retry exceeds max word count → keep original ---
echo "Test 4: Retry exceeds max word count → original kept"
original_text="The river flowed quietly past the village as morning broke."
# Generate a retry that's way too long (simulate with a long string)
MOCK_RETRY_TEXT='"Tell me," she said, "what brings you to this far corner of the world where the hills meet the sea and the winds carry stories from ancient lands across the valleys and through the forests where the birds sing their endless songs of hope and renewal and the flowers bloom in colors that no painter could capture on any canvas ever made by human hands in all the centuries of art and beauty that have graced this earth since the very beginning of time itself when the first light shone upon the waters."'
result=$(validate_and_retry_opening "$original_text" "dialogue" "prompt" "1200" "short" "5" "15" 2>/dev/null)
assert_eq "original kept when retry exceeds max" "$original_text" "$result"

# --- Test 5: Non-validated opening type (action) → original returned without retry ---
echo "Test 5: Non-validated opening type bypasses retry entirely"
MOCK_RETRY_TEXT="should not be used"
result=$(validate_and_retry_opening "He ran through the streets." "action" "prompt" "1200" "short" "5" "50" 2>/dev/null)
assert_eq "action type bypasses validation" "He ran through the streets." "$result"

# --- Test 6: Retry fails opening but passes word count → retry accepted ---
echo "Test 6: Retry fails opening but passes word count → retry accepted"
original_text="The dawn broke slowly over the sleeping village."
MOCK_RETRY_TEXT="Morning light crept across the cobblestones as people stirred."
result=$(validate_and_retry_opening "$original_text" "dialogue" "prompt" "1200" "short" "5" "50" 2>/dev/null)
assert_eq "retry accepted when it fails opening but passes word count" "$MOCK_RETRY_TEXT" "$result"

# --- Test 7: Empty retry → original kept ---
echo "Test 7: Empty retry text → original kept"
MOCK_RETRY_TEXT=""
result=$(validate_and_retry_opening "The road stretched ahead endlessly." "dialogue" "prompt" "1200" "short" "5" "50" 2>/dev/null)
assert_eq "original kept on empty retry" "The road stretched ahead endlessly." "$result"

# --- Test 8: Default min/max when not provided → backward compatible ---
echo "Test 8: No min/max args → defaults allow any word count (backward compat)"
MOCK_RETRY_TEXT='"Short."'
result=$(validate_and_retry_opening "The village slept." "dialogue" "prompt" "1200" "short" 2>/dev/null)
assert_eq "backward compat with no min/max" "$MOCK_RETRY_TEXT" "$result"

# --- Results ---
echo ""
echo "========================================================="
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================================="
[ $FAIL -eq 0 ] && exit 0 || exit 1

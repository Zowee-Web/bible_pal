#!/usr/bin/env bash
# test_story_dna.sh — Unit tests for Story DNA planner
# Run: bash server/test_story_dna.sh
# Compatible with macOS bash 3.2 (no associative arrays, no [[ in subshells)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/story_dna.sh"

PASS=0
FAIL=0
TOTAL=0

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

assert_ne() {
    local label="$1" unexpected="$2" actual="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$unexpected" != "$actual" ]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (got '$actual', should differ)"
        FAIL=$((FAIL + 1))
    fi
}

assert_ge() {
    local label="$1" actual="$2" threshold="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" -ge "$threshold" ]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (got $actual, need >= $threshold)"
        FAIL=$((FAIL + 1))
    fi
}

assert_le() {
    local label="$1" actual="$2" threshold="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" -le "$threshold" ]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (got $actual, need <= $threshold)"
        FAIL=$((FAIL + 1))
    fi
}

assert_lt() {
    local label="$1" actual="$2" threshold="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$actual" -lt "$threshold" ]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (got $actual, need < $threshold)"
        FAIL=$((FAIL + 1))
    fi
}

assert_cmd_fails() {
    local label="$1"
    shift
    TOTAL=$((TOTAL + 1))
    if "$@"; then
        echo "FAIL: $label (command should have failed)"
        FAIL=$((FAIL + 1))
    else
        PASS=$((PASS + 1))
    fi
}

assert_cmd_passes() {
    local label="$1"
    shift
    TOTAL=$((TOTAL + 1))
    if "$@"; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $label (command should have passed)"
        FAIL=$((FAIL + 1))
    fi
}

# Count unique non-empty values in a newline-delimited list
count_unique() {
    echo "$1" | grep -v '^$' | sort -u | wc -l | tr -d ' '
}

echo "=== Story DNA Planner Tests ==="
echo ""

# --- Test 1: Determinism ---
echo "Test 1: Determinism (same index produces same output)"
dna_a=$(compute_story_dna 0 500)
dna_b=$(compute_story_dna 0 500)
assert_eq "index 0 is deterministic" "$dna_a" "$dna_b"

dna_c=$(compute_story_dna 5 505)
dna_d=$(compute_story_dna 5 505)
assert_eq "index 5 is deterministic" "$dna_c" "$dna_d"

# --- Test 2: Different indices produce different DNA ---
echo "Test 2: Adjacent indices differ"
dna_0=$(compute_story_dna 0 500)
dna_1=$(compute_story_dna 1 501)
assert_ne "index 0 vs 1 differ" "$dna_0" "$dna_1"

# --- Test 3: Pool coverage (opening_type) ---
echo "Test 3: Opening type pool coverage over 80 iterations"
all_openings=""
for i in $(seq 0 79); do
    o=$(compute_story_dna "$i" "$((500+i))" | jq -r '.opening_type')
    all_openings="${all_openings}${o}
"
done
unique_openings=$(count_unique "$all_openings")
assert_eq "all 8 opening types seen" "8" "$unique_openings"

# --- Test 4: Pool coverage (structure_type) ---
echo "Test 4: Structure type pool coverage over 80 iterations"
all_structures=""
for i in $(seq 0 79); do
    s=$(compute_story_dna "$i" "$((500+i))" | jq -r '.structure_type')
    all_structures="${all_structures}${s}
"
done
unique_structures=$(count_unique "$all_structures")
assert_eq "all 8 structure types seen" "8" "$unique_structures"

# --- Test 5: Pool coverage (setting_emphasis) ---
echo "Test 5: Setting emphasis pool coverage"
all_settings=""
for i in $(seq 0 79); do
    se=$(compute_story_dna "$i" "$((500+i))" | jq -r '.setting_emphasis')
    all_settings="${all_settings}${se}
"
done
unique_settings=$(count_unique "$all_settings")
assert_eq "all 3 setting emphasis values seen" "3" "$unique_settings"

# --- Test 6: Setting emphasis bias (low should appear most) ---
echo "Test 6: Setting emphasis weighted toward low"
low_count=0
for i in $(seq 0 79); do
    se=$(compute_story_dna "$i" "$((500+i))" | jq -r '.setting_emphasis')
    [ "$se" = "low" ] && low_count=$((low_count + 1))
done
assert_ge "low appears at least 25 times in 80" "$low_count" 25

# --- Test 7: Anti-lockstep (opening and structure don't move in sync) ---
echo "Test 7: Anti-lockstep (prime offsets prevent paired rotation)"
lockstep=0
for i in $(seq 0 7); do
    dna=$(compute_story_dna "$i" "$((500+i))")
    ot=$(echo "$dna" | jq -r '.opening_type')
    st=$(echo "$dna" | jq -r '.structure_type')
    if [ "$ot" = "${DNA_OPENING_TYPES[$i]}" ] && \
       [ "$st" = "${DNA_STRUCTURE_TYPES[$i]}" ]; then
        lockstep=$((lockstep + 1))
    fi
done
assert_lt "fewer than 3 lockstep pairs in first 8" "$lockstep" 3

# --- Test 8: Repetition guard — consecutive opening collision ---
echo "Test 8: Repetition guard detects consecutive opening collisions"
init_dna_guard

record_dna '{"opening_type":"dialogue","structure_type":"journey"}'
record_dna '{"opening_type":"dialogue","structure_type":"witness"}'

assert_cmd_fails "guard rejects 3rd consecutive 'dialogue'" check_repetition_guard "dialogue" "flashback"
assert_cmd_passes "different opening passes guard" check_repetition_guard "action" "flashback"

# --- Test 9: Repetition guard — consecutive structure collision ---
echo "Test 9: Repetition guard detects structure collisions"
init_dna_guard
record_dna '{"opening_type":"action","structure_type":"journey"}'
record_dna '{"opening_type":"conflict","structure_type":"journey"}'

assert_cmd_fails "guard rejects 3rd consecutive 'journey'" check_repetition_guard "memory" "journey"

# --- Test 10: get_story_dna auto-advances past collision ---
echo "Test 10: get_story_dna auto-advances past collision"
init_dna_guard

idx0_opening=$(compute_story_dna 0 500 | jq -r '.opening_type')
record_dna "{\"opening_type\":\"$idx0_opening\",\"structure_type\":\"x\"}"
record_dna "{\"opening_type\":\"$idx0_opening\",\"structure_type\":\"y\"}"

result=$(get_story_dna 0 500)
result_opening=$(echo "$result" | jq -r '.opening_type')
assert_ne "get_story_dna avoids collision" "$idx0_opening" "$result_opening"

# --- Test 11: JSON structure has all required fields ---
echo "Test 11: DNA JSON has all required fields"
dna=$(compute_story_dna 3 503)
for field in opening_type structure_type setting_emphasis character_archetype tone narrator_voice story_id; do
    val=$(echo "$dna" | jq -r ".$field")
    TOTAL=$((TOTAL + 1))
    if [ -n "$val" ] && [ "$val" != "null" ]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: missing field '$field' in DNA JSON"
        FAIL=$((FAIL + 1))
    fi
done

# --- Test 12: Adjacent repetition behavior (end-to-end batch simulation) ---
echo "Test 12: 16-story batch has no 3+ consecutive identical openings or structures"
init_dna_guard
max_consec_opening=1
max_consec_structure=1
prev_opening=""
prev_structure=""
consec_opening=1
consec_structure=1

for i in $(seq 0 15); do
    dna=$(get_story_dna "$i" "$((500+i))")
    opening=$(echo "$dna" | jq -r '.opening_type')
    structure=$(echo "$dna" | jq -r '.structure_type')

    if [ "$opening" = "$prev_opening" ]; then
        consec_opening=$((consec_opening + 1))
    else
        consec_opening=1
    fi
    if [ "$structure" = "$prev_structure" ]; then
        consec_structure=$((consec_structure + 1))
    else
        consec_structure=1
    fi

    [ $consec_opening -gt $max_consec_opening ] && max_consec_opening=$consec_opening
    [ $consec_structure -gt $max_consec_structure ] && max_consec_structure=$consec_structure
    prev_opening="$opening"
    prev_structure="$structure"
done

assert_le "max consecutive same opening <= 2" "$max_consec_opening" 2
assert_le "max consecutive same structure <= 2" "$max_consec_structure" 2

# --- Test 13: Pool coverage (narrator_voice) ---
echo "Test 13: Narrator voice pool coverage over 80 iterations"
all_narrators=""
for i in $(seq 0 79); do
    nv=$(compute_story_dna "$i" "$((500+i))" | jq -r '.narrator_voice')
    all_narrators="${all_narrators}${nv}
"
done
unique_narrators=$(count_unique "$all_narrators")
assert_eq "all 4 narrator voices seen" "4" "$unique_narrators"

# --- Test 14: Anti-lockstep (narrator_voice vs tone) ---
echo "Test 14: Narrator voice and tone don't rotate in lockstep"
lockstep_nt=0
for i in $(seq 0 7); do
    dna=$(compute_story_dna "$i" "$((500+i))")
    nv=$(echo "$dna" | jq -r '.narrator_voice')
    tn=$(echo "$dna" | jq -r '.tone')
    # If both follow raw index, they'd lockstep. Prime offsets prevent this.
    nv_raw="${DNA_NARRATOR_VOICES[ $(( i % ${#DNA_NARRATOR_VOICES[@]} )) ]}"
    tn_raw="${DNA_TONES[ $(( i % ${#DNA_TONES[@]} )) ]}"
    if [ "$nv" = "$nv_raw" ] && [ "$tn" = "$tn_raw" ]; then
        lockstep_nt=$((lockstep_nt + 1))
    fi
done
assert_lt "fewer than 3 narrator/tone lockstep pairs in first 8" "$lockstep_nt" 3

# --- Test 15: compute_creative_ordinal (single-story index regression) ---
echo "Test 15: compute_creative_ordinal (single-story index regression)"

test_batch=(
    "504|creative|false|joyful|V1||"
    "505|creative|false|anxious|V2||"
    "809|traditional|false|anxious|V3|Mark 4|key1"
    "506|creative|false|hurting|V4||"
    "810|traditional|false|hurting|V5|John 4|key2"
    "514|creative|false|calm|V6||"
)

ordinal_504=$(compute_creative_ordinal "504" "${test_batch[@]}")
assert_eq "story 504 is creative ordinal 0" "0" "$ordinal_504"

ordinal_505=$(compute_creative_ordinal "505" "${test_batch[@]}")
assert_eq "story 505 is creative ordinal 1" "1" "$ordinal_505"

ordinal_506=$(compute_creative_ordinal "506" "${test_batch[@]}")
assert_eq "story 506 is creative ordinal 2 (traditional skipped)" "2" "$ordinal_506"

ordinal_514=$(compute_creative_ordinal "514" "${test_batch[@]}")
assert_eq "story 514 is creative ordinal 3 (traditional skipped)" "3" "$ordinal_514"

# --- Cleanup ---
rm -f "${SCRIPT_DIR}/.dna_history.json"

# --- Results ---
echo ""
echo "========================================================="
echo "Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================================="
[ $FAIL -eq 0 ] && exit 0 || exit 1

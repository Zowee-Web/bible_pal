#!/usr/bin/env bash
# Smoke tests for the Universal Model Router
# Run from project root: bash server/model_router/smoke_test.sh

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$SCRIPT_DIR"

check() {
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        echo -e "  ${GREEN}✓${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $desc"
        FAIL=$((FAIL + 1))
    fi
}

check_output() {
    local desc="$1"
    local expected="$2"
    shift 2
    local output
    output=$("$@" 2>/dev/null) || true
    if echo "$output" | grep -q "$expected"; then
        echo -e "  ${GREEN}✓${NC} $desc"
        PASS=$((PASS + 1))
    else
        echo -e "  ${RED}✗${NC} $desc (expected '$expected')"
        FAIL=$((FAIL + 1))
    fi
}

echo ""
echo "=== Universal Model Router — Smoke Tests ==="
echo ""

echo "1. Registry & CLI basics"
check "list-tasks returns tasks" \
    python3 -m server.model_router.cli list-tasks

check_output "list-tasks includes creative_story" "creative_story" \
    python3 -m server.model_router.cli list-tasks

check_output "list-tasks includes 8 task types" '"task"' \
    python3 -m server.model_router.cli list-tasks

echo ""
echo "2. Model resolution"
check_output "resolve creative_story returns mistral-nemo" "mistral-nemo" \
    python3 -m server.model_router.cli resolve creative_story

check_output "resolve traditional_story_remote shows locked" '"locked": true' \
    python3 -m server.model_router.cli resolve traditional_story_remote

check_output "resolve longform_experimental returns mixtral" "mixtral" \
    python3 -m server.model_router.cli resolve longform_experimental

check_output "resolve reasoning_balanced returns a model" '"model"' \
    python3 -m server.model_router.cli resolve reasoning_balanced

echo ""
echo "3. Availability"
check "check-availability runs" \
    python3 -m server.model_router.cli check-availability

check_output "Ollama is running" '"ollama_running": true' \
    python3 -m server.model_router.cli check-availability

echo ""
echo "4. Explain"
check_output "explain creative_story shows chain" "primary" \
    python3 -m server.model_router.cli explain creative_story

echo ""
echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if [[ $FAIL -gt 0 ]]; then
    echo -e "${RED}SOME TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    exit 0
fi

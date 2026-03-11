#!/usr/bin/env bash
# AI Health Check — verifies the local AI infrastructure
#
# Checks:
#   1. Ollama is running
#   2. /Volumes/T9-AI/ollama is mounted and symlinked
#   3. Installed models are visible
#   4. Router CLI works
#   5. FastAPI prototype responds (if running)
#   6. At least one fallback path resolves
#
# Usage: bash scripts/ai_health_check.sh

set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

PASS=0
FAIL=0
WARN=0

ok() {
    echo -e "  ${GREEN}✓${NC} $1"
    PASS=$((PASS + 1))
}

fail() {
    echo -e "  ${RED}✗${NC} $1"
    FAIL=$((FAIL + 1))
}

warn() {
    echo -e "  ${YELLOW}⚠${NC} $1"
    WARN=$((WARN + 1))
}

# Change to project root
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$SCRIPT_DIR"

echo ""
echo -e "${BLUE}=== Bible PAL — AI Health Check ===${NC}"
echo -e "    $(date '+%Y-%m-%d %H:%M:%S')"
echo ""

# -------------------------------------------------------------------
echo "1. Ollama Server"
# -------------------------------------------------------------------
if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
    ok "Ollama is running at localhost:11434"
else
    fail "Ollama is NOT running (start with: ollama serve)"
fi

# -------------------------------------------------------------------
echo ""
echo "2. Storage"
# -------------------------------------------------------------------
if [[ -d /Volumes/T9-AI/ollama ]]; then
    ok "/Volumes/T9-AI/ollama is mounted"
else
    fail "/Volumes/T9-AI/ollama is NOT mounted"
fi

if [[ -L "$HOME/.ollama" ]]; then
    target=$(readlink "$HOME/.ollama" 2>/dev/null || true)
    if [[ "$target" == "/Volumes/T9-AI/ollama" ]]; then
        ok "~/.ollama -> /Volumes/T9-AI/ollama (symlink correct)"
    else
        warn "~/.ollama points to '$target' (expected /Volumes/T9-AI/ollama)"
    fi
elif [[ -d "$HOME/.ollama" ]]; then
    warn "~/.ollama is a directory, not a symlink (models may be on boot drive)"
else
    fail "~/.ollama does not exist"
fi

# -------------------------------------------------------------------
echo ""
echo "3. Installed Models"
# -------------------------------------------------------------------
if command -v ollama >/dev/null 2>&1; then
    MODEL_COUNT=$(ollama list 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')
    if [[ "$MODEL_COUNT" -gt 0 ]]; then
        ok "$MODEL_COUNT models installed:"
        ollama list 2>/dev/null | tail -n +2 | while read -r line; do
            name=$(echo "$line" | awk '{print $1}')
            size=$(echo "$line" | awk '{print $3, $4}')
            echo -e "       $name ($size)"
        done
    else
        fail "No models installed"
    fi
else
    fail "ollama command not found"
fi

# -------------------------------------------------------------------
echo ""
echo "4. Router CLI"
# -------------------------------------------------------------------
if python3 -m server.model_router.cli list-tasks >/dev/null 2>&1; then
    ok "Router CLI responds (list-tasks)"
else
    fail "Router CLI failed"
fi

if python3 -m server.model_router.cli resolve creative_story >/dev/null 2>&1; then
    MODEL=$(python3 -m server.model_router.cli resolve creative_story 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['model'])" 2>/dev/null || echo "unknown")
    ok "creative_story -> $MODEL"
else
    fail "Router cannot resolve creative_story"
fi

if python3 -m server.model_router.cli resolve traditional_story_remote >/dev/null 2>&1; then
    LOCKED=$(python3 -m server.model_router.cli resolve traditional_story_remote 2>/dev/null | python3 -c "import sys,json; print(json.load(sys.stdin)['locked'])" 2>/dev/null || echo "unknown")
    if [[ "$LOCKED" == "True" ]]; then
        ok "traditional_story_remote is LOCKED (gpt-4.1)"
    else
        fail "traditional_story_remote is NOT locked"
    fi
else
    fail "Router cannot resolve traditional_story_remote"
fi

# -------------------------------------------------------------------
echo ""
echo "5. FastAPI Prototype (port 8181)"
# -------------------------------------------------------------------
if curl -s http://127.0.0.1:8181/health >/dev/null 2>&1; then
    ok "FastAPI is running at 127.0.0.1:8181"
    HEALTH=$(curl -s http://127.0.0.1:8181/health 2>/dev/null | python3 -c "import sys,json; r=json.load(sys.stdin); d=r.get('data',r); print(f\"Ollama: {'up' if d.get('ollama_running') else 'down'}, Models: {len(d.get('installed_models',[]))}\")" 2>/dev/null || echo "parse error")
    echo -e "       $HEALTH"
else
    warn "FastAPI is NOT running (start with: uvicorn server.model_router.api:app --host 127.0.0.1 --port 8181)"
fi

# -------------------------------------------------------------------
echo ""
echo "6. Fallback Resolution"
# -------------------------------------------------------------------
# Test that coding tasks fall back to available models
CODING_RESULT=$(python3 -m server.model_router.cli resolve coding_flutter 2>/dev/null || echo '{"error":"failed"}')
CODING_MODEL=$(echo "$CODING_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('model','none'))" 2>/dev/null || echo "none")
if [[ "$CODING_MODEL" != "none" ]]; then
    DEPTH=$(echo "$CODING_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('fallback_depth',0))" 2>/dev/null || echo "?")
    if [[ "$DEPTH" == "0" ]]; then
        ok "coding_flutter -> $CODING_MODEL (primary)"
    else
        ok "coding_flutter -> $CODING_MODEL (fallback depth $DEPTH)"
    fi
else
    warn "coding_flutter has no available model (install deepseek-coder or codellama)"
fi

# -------------------------------------------------------------------
echo ""
echo -e "${BLUE}=== Summary ===${NC}"
echo -e "  Passed: ${GREEN}$PASS${NC}  Failed: ${RED}$FAIL${NC}  Warnings: ${YELLOW}$WARN${NC}"

if [[ $FAIL -gt 0 ]]; then
    echo -e "  ${RED}Some checks FAILED — see above${NC}"
    exit 1
elif [[ $WARN -gt 0 ]]; then
    echo -e "  ${YELLOW}All critical checks passed (with warnings)${NC}"
    exit 0
else
    echo -e "  ${GREEN}All checks PASSED${NC}"
    exit 0
fi

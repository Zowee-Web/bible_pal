#!/bin/bash
# =============================================================================
# run_critical_tests.sh
# Fast-fail CRITICAL invariant tests for Bible PAL
# =============================================================================
#
# This script runs ONLY the tests in test/critical/ and fails immediately
# if any invariant is violated. Use this before the full test suite to catch
# contract breaches early.
#
# CRITICAL tests enforce:
# - Bible translation compliance (no banned translations)
# - Traditional mode = real Bible story invariant (ADR-010)
# - One bibleStoryKey per mood
# - Canonical story map alignment
# - Mode persistence
# - Reflection system requirements
# - Kid safety content segregation
# - Voice consent requirements
#
# Usage:
#   ./scripts/run_critical_tests.sh
#
# Exit codes:
#   0 = All CRITICAL tests passed
#   1 = One or more CRITICAL tests failed (invariant violation)
#
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")/.." || exit 1

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo ""
echo "=============================================="
echo -e "${YELLOW}🔒 CRITICAL INVARIANT TESTS${NC}"
echo "=============================================="
echo ""
echo "Running fast-fail tests for contract enforcement..."
echo "These tests MUST pass before proceeding with full suite."
echo ""

# Count critical test files
CRITICAL_COUNT=$(find test/critical -name '*_test.dart' | wc -l | tr -d ' ')
echo "Found ${CRITICAL_COUNT} critical test files in test/critical/"
echo ""

# Run critical tests with fail-fast
# --fail-fast stops at first failure
# --reporter expanded shows detailed output
if flutter test test/critical/ --fail-fast; then
    echo ""
    echo "=============================================="
    echo -e "${GREEN}✅ ALL CRITICAL TESTS PASSED${NC}"
    echo "=============================================="
    echo ""
    echo "Invariants verified. Safe to run full test suite."
    exit 0
else
    echo ""
    echo "=============================================="
    echo -e "${RED}🚨 CRITICAL TEST FAILURE${NC}"
    echo "=============================================="
    echo ""
    echo "One or more invariants are violated!"
    echo "DO NOT proceed until these are fixed."
    echo ""
    echo "Common fixes:"
    echo "  - Check test/critical/ output for specific violation"
    echo "  - Review docs/INVARIANTS.md for requirements"
    echo "  - Ensure manifest.json aligns with canonical maps"
    echo ""
    exit 1
fi

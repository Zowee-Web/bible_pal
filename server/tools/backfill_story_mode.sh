#!/bin/bash
# backfill_story_mode.sh - Story Mode Contracts v2 Migration Helper
#
# Per SPEC.md Story Mode Contracts v2 and INVARIANTS.md
#
# This script helps migrate existing stories to comply with Contracts v2:
# - Adds languageStyle field (defaults to matching translationId)
# - For Traditional stories: REQUIRES manual bibleSourceRef entry
# - For Creative stories: Ensures bibleSourceRef is absent
#
# IMPORTANT: This script does NOT guess bibleSourceRef values.
# Traditional stories without bibleSourceRef will be flagged for manual entry.

set -euo pipefail

MANIFEST_PATH="${1:-assets/stories/manifest.json}"
OUTPUT_PATH="${2:-assets/stories/manifest_migrated.json}"
REPORT_PATH="${3:-assets/stories/migration_report.txt}"

echo "=== Story Mode Contracts v2 Migration ==="
echo "Manifest: $MANIFEST_PATH"
echo "Output: $OUTPUT_PATH"
echo "Report: $REPORT_PATH"
echo ""

if [ ! -f "$MANIFEST_PATH" ]; then
    echo "ERROR: Manifest file not found: $MANIFEST_PATH"
    exit 1
fi

# Initialize counters
total_stories=0
traditional_with_ref=0
traditional_missing_ref=0
creative_valid=0
creative_with_ref=0
added_language_style=0

# Create report file
echo "Story Mode Contracts v2 Migration Report" > "$REPORT_PATH"
echo "Generated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")" >> "$REPORT_PATH"
echo "========================================" >> "$REPORT_PATH"
echo "" >> "$REPORT_PATH"

# Process manifest using jq
echo "Analyzing stories..."

# Get story counts by mode
total_stories=$(jq '.parables | length' "$MANIFEST_PATH")
traditional_count=$(jq '[.parables[] | select(.storytellingMode == "traditional")] | length' "$MANIFEST_PATH")
creative_count=$(jq '[.parables[] | select(.storytellingMode == "creative")] | length' "$MANIFEST_PATH")

echo "Total stories: $total_stories"
echo "Traditional: $traditional_count"
echo "Creative: $creative_count"
echo "" >> "$REPORT_PATH"
echo "Story Counts:" >> "$REPORT_PATH"
echo "- Total: $total_stories" >> "$REPORT_PATH"
echo "- Traditional: $traditional_count" >> "$REPORT_PATH"
echo "- Creative: $creative_count" >> "$REPORT_PATH"
echo "" >> "$REPORT_PATH"

# Check Traditional stories for bibleSourceRef
echo "" >> "$REPORT_PATH"
echo "=== TRADITIONAL STORIES ===" >> "$REPORT_PATH"
echo "" >> "$REPORT_PATH"

traditional_missing=$(jq -r '
  [.parables[] |
   select(.storytellingMode == "traditional") |
   select(.bibleSourceRef == null or .bibleSourceRef == "")] |
  .[].storyId' "$MANIFEST_PATH" 2>/dev/null || echo "")

if [ -n "$traditional_missing" ]; then
    echo "⚠️  ATTENTION REQUIRED: Traditional stories missing bibleSourceRef"
    echo "" >> "$REPORT_PATH"
    echo "❌ MISSING bibleSourceRef (MANUAL ENTRY REQUIRED):" >> "$REPORT_PATH"
    echo "$traditional_missing" | while read -r story_id; do
        if [ -n "$story_id" ]; then
            echo "  - $story_id" >> "$REPORT_PATH"
            ((traditional_missing_ref++)) || true
        fi
    done
    echo ""
    echo "These stories will be EXCLUDED from Traditional mode until bibleSourceRef is added."
else
    echo "✅ All Traditional stories have bibleSourceRef"
    echo "✅ All Traditional stories have bibleSourceRef" >> "$REPORT_PATH"
fi

# Check Creative stories for incorrect bibleSourceRef
echo "" >> "$REPORT_PATH"
echo "=== CREATIVE STORIES ===" >> "$REPORT_PATH"
echo "" >> "$REPORT_PATH"

creative_with_ref_list=$(jq -r '
  [.parables[] |
   select(.storytellingMode == "creative") |
   select(.bibleSourceRef != null and .bibleSourceRef != "")] |
  .[].storyId' "$MANIFEST_PATH" 2>/dev/null || echo "")

if [ -n "$creative_with_ref_list" ]; then
    echo "⚠️  WARNING: Creative stories with bibleSourceRef (should be removed)"
    echo "" >> "$REPORT_PATH"
    echo "⚠️  HAS bibleSourceRef (SHOULD BE REMOVED):" >> "$REPORT_PATH"
    echo "$creative_with_ref_list" | while read -r story_id; do
        if [ -n "$story_id" ]; then
            echo "  - $story_id" >> "$REPORT_PATH"
            ((creative_with_ref++)) || true
        fi
    done
    echo ""
else
    echo "✅ No Creative stories have incorrect bibleSourceRef"
    echo "✅ All Creative stories correctly lack bibleSourceRef" >> "$REPORT_PATH"
fi

# Check for missing languageStyle
echo "" >> "$REPORT_PATH"
echo "=== LANGUAGE STYLE ===" >> "$REPORT_PATH"
echo "" >> "$REPORT_PATH"

missing_language_style=$(jq '[.parables[] | select(.languageStyle == null)] | length' "$MANIFEST_PATH")
if [ "$missing_language_style" -gt 0 ]; then
    echo "📝 Stories missing languageStyle: $missing_language_style (will default from translationId)"
    echo "Stories missing languageStyle: $missing_language_style" >> "$REPORT_PATH"
    echo "These will be migrated to use translationId value as default." >> "$REPORT_PATH"
else
    echo "✅ All stories have languageStyle"
    echo "✅ All stories have languageStyle" >> "$REPORT_PATH"
fi

# Generate migrated manifest
echo ""
echo "Generating migrated manifest..."

jq '
  .parables = [.parables[] |
    # Add languageStyle if missing (default from translationId or "WEB")
    . + {languageStyle: (.languageStyle // .translationId // "WEB")}
  ]
' "$MANIFEST_PATH" > "$OUTPUT_PATH"

echo ""
echo "=== MIGRATION SUMMARY ===" >> "$REPORT_PATH"
echo "" >> "$REPORT_PATH"

# Final summary
echo ""
echo "=== MIGRATION SUMMARY ==="
echo ""

traditional_missing_count=$(echo "$traditional_missing" | grep -c . || echo "0")
creative_with_ref_count=$(echo "$creative_with_ref_list" | grep -c . || echo "0")

if [ "$traditional_missing_count" -gt 0 ]; then
    echo "❌ $traditional_missing_count Traditional stories need manual bibleSourceRef"
    echo "❌ $traditional_missing_count Traditional stories need manual bibleSourceRef" >> "$REPORT_PATH"
fi

if [ "$creative_with_ref_count" -gt 0 ]; then
    echo "⚠️  $creative_with_ref_count Creative stories have bibleSourceRef to remove"
    echo "⚠️  $creative_with_ref_count Creative stories have bibleSourceRef to remove" >> "$REPORT_PATH"
fi

if [ "$traditional_missing_count" -eq 0 ] && [ "$creative_with_ref_count" -eq 0 ]; then
    echo "✅ All stories comply with Story Mode Contracts v2"
    echo "✅ All stories comply with Story Mode Contracts v2" >> "$REPORT_PATH"
fi

echo ""
echo "Output written to: $OUTPUT_PATH"
echo "Report written to: $REPORT_PATH"
echo ""
echo "NEXT STEPS:"
echo "1. Review $REPORT_PATH for stories requiring manual entry"
echo "2. Add bibleSourceRef to Traditional stories (DO NOT GUESS)"
echo "3. Remove bibleSourceRef from Creative stories"
echo "4. Run: flutter test test/critical/story_mode_contracts_test.dart"
echo "5. Replace manifest: mv $OUTPUT_PATH $MANIFEST_PATH"

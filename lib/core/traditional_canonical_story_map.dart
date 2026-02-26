// Traditional Mode Canonical Story Map - Single Source of Truth
// Per ADR-010 (docs/DECISIONS.md) and INVARIANTS.md
//
// =============================================================================
// THIS MAP IS AUTHORITATIVE.
// =============================================================================
//
// Traditional mode requires that each mood maps to exactly ONE canonical
// Bible story. This constant defines that mapping.
//
// RULES:
// 1. Every Traditional story in the manifest MUST use the bibleStoryKey
//    specified here for its mood.
// 2. Adding a new Traditional mood requires updating this map FIRST.
// 3. Changing a canonical story requires updating this map FIRST.
// 4. Tests enforce alignment between this map and the manifest.
//
// The test in test/critical/traditional_canonical_story_map_test.dart will
// FAIL if the manifest drifts from this canonical mapping.
//
// =============================================================================

/// Canonical Bible story per mood for Traditional mode.
///
/// Key: mood (e.g., 'joyful', 'brave_courage')
/// Value: bibleStoryKey (e.g., 'lost_sheep', 'daniel_lions_den')
///
/// This is the SINGLE SOURCE OF TRUTH for which Bible story is served
/// for each mood in Traditional mode. All Traditional stories for a given
/// mood MUST use the bibleStoryKey specified here.
const Map<String, String> kTraditionalCanonicalStoryByMood = {
  'anxious': 'jesus_calms_storm', // Mark 4:35-41
  'brave_courage': 'daniel_lions_den', // Daniel 6
  'calm_peaceful': 'samuel_listens', // 1 Samuel 3
  'encouraging': 'queen_esther', // Esther 4-7
  'hurting': 'woman_at_well', // John 4:4-26
  'joyful': 'lost_sheep', // Luke 15:3-7
  'neutral': 'road_to_emmaus', // Luke 24:13-35
  'weary': 'rest_for_the_weary', // Matthew 11:28-30
};

/// Set of moods that have Traditional story coverage.
///
/// Derived from [kTraditionalCanonicalStoryByMood] keys.
/// Use this to check if a mood has Traditional content available.
Set<String> get kTraditionalCoveredMoods =>
    kTraditionalCanonicalStoryByMood.keys.toSet();

/// Moods that exist in the app but do NOT yet have Traditional coverage.
/// These moods only have Creative content.
///
/// When adding Traditional stories for these moods:
/// 1. Add the mood -> bibleStoryKey entry to [kTraditionalCanonicalStoryByMood]
/// 2. Generate the Traditional story with that bibleStoryKey
/// 3. Update manifest.json
/// 4. Run tests to verify alignment
const Set<String> kMoodsWithoutTraditionalCoverage = {};

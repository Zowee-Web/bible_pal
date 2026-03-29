/// Canonical similar mood map per SPEC.md 15b and INVARIANTS.md.
/// Modifying this map requires owner approval.
class MoodSimilarity {
  MoodSimilarity._();

  static const Map<String, List<String>> similarMoods = {
    'anxious': ['calm_peaceful', 'encouraging', 'weary'],
    'calm_peaceful': ['anxious', 'grateful', 'encouraging'],
    'brave_courage': ['encouraging', 'hurting', 'anxious'],
    'encouraging': ['brave_courage', 'calm_peaceful', 'grateful'],
    'grateful': ['joyful', 'calm_peaceful', 'encouraging'],
    'hurting': ['weary', 'encouraging', 'calm_peaceful'],
    'joyful': ['grateful', 'encouraging', 'calm_peaceful'],
    'weary': ['hurting', 'calm_peaceful', 'encouraging'],
  };

  /// Returns similar moods for the given mood, or empty list if unknown.
  static List<String> getSimilar(String mood) =>
      similarMoods[mood] ?? const [];
}

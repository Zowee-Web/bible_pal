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

  /// Kid-ONLY mood bridges, layered on top of [similarMoods] when kidMode=true.
  ///
  /// The adult map deliberately expands distress (anxious/hurting) only to GENTLE
  /// moods — correct for grown-ups, but it strands the "triumphant" kid stories:
  /// a SCARED child can't reach the Fiery Furnace (brave_courage), and a child who
  /// "got in trouble" can't reach the Loving Father (grateful). These bridges open
  /// those paths for KIDS only. The relatability tags then rank the right story to
  /// the top, and the tier keeps gentle exact-mood stories first, so a brave story
  /// is deeper-rotation, not the first thing a scared child hears.
  ///
  /// Adult selection never passes kidMode, so [similarMoods] (the owner-approved
  /// SPEC 15b map) is unchanged for adults.
  static const Map<String, List<String>> _kidBridges = {
    'anxious': ['brave_courage'],
    'hurting': ['brave_courage', 'grateful'],
  };

  /// Returns similar moods for the given mood, or empty list if unknown.
  ///
  /// When [kidMode] is true, kid-only bridges are unioned in (adult moods first,
  /// then any new bridge moods — deduplicated). When false (the default, and
  /// always the case for adult selection) the adult map is returned verbatim.
  static List<String> getSimilar(String mood, {bool kidMode = false}) {
    final base = similarMoods[mood] ?? const <String>[];
    if (!kidMode) return base;
    final bridges = _kidBridges[mood];
    if (bridges == null) return base;
    return [...base, ...bridges.where((m) => !base.contains(m))];
  }
}

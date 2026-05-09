/// Canonical PALs Paths theme vocabulary (SPEC Feature 50).
///
/// **Expanded from the original 8-tag locked vocab in PR β** to cover the full
/// theological terrain present in the 1287-story corpus. The 58 values below
/// are the corpus's authored canonical themes; rejecting them would mean
/// remapping ~430 metadata uses across the corpus to fewer tags, losing
/// information for no gain.
///
/// Future additions still require an owner-approved expansion edit:
///   1. Owner approval
///   2. SPEC update (Feature 50)
///   3. An additive edit to [ThemeTag] below
///   4. Updated tests in `test/features/paths/theme_vocabulary_test.dart`
///   5. Updated manifest annotations as needed
///
/// Wire IDs appear in `Parable.themeTags[]`, in the `themes` path type's
/// `path_id` telemetry field, and in `assets/stories/paths_index.json`.
/// They must not drift.
enum ThemeTag {
  // Original locked-8 (v1)
  faith,
  hope,
  mercy,
  courage,
  obedience,
  provision,
  patience,
  forgiveness,
  // PR β expansion — corpus-canonical themes
  promise,
  presence,
  trust,
  guidance,
  prayer,
  calling,
  lament,
  gratitude,
  suffering,
  praise,
  deliverance,
  love,
  perseverance,
  restoration,
  endurance,
  faithfulness,
  transformation,
  rest,
  fear,
  healing,
  rebuilding,
  blessing,
  celebration,
  wisdom,
  peace,
  waiting,
  freedom,
  testing,
  covenant,
  longing,
  redemption,
  comfort,
  repentance,
  sacrifice,
  protection,
  refuge,
  witness,
  scripture,
  humility,
  service,
  kingdom,
  loyalty,
  shame,
  abandonment,
  justice,
  wrestling,
  grief,
  joy,
  hospitality,
  devotion,
}

extension ThemeTagWire on ThemeTag {
  /// Wire-format ID — must match SPEC Feature 50 vocabulary exactly.
  /// All wire IDs are the lowercase enum name; this is enforced by the
  /// snake_case test in `theme_vocabulary_test.dart`.
  String get wireId => name;

  /// User-facing display label. Capitalized for UI.
  /// Default is Title Case of the wire id with underscores replaced. The
  /// expanded vocab uses single-word lowercase identifiers, so this returns
  /// the capitalized version.
  String get displayLabel {
    final w = wireId;
    if (w.isEmpty) return w;
    return w[0].toUpperCase() + w.substring(1);
  }
}

extension ThemeTagParse on ThemeTag {
  /// Parse a wire-format string into a [ThemeTag]. Returns null for
  /// unknown values so manifest readers can skip unknown tags as "story
  /// not eligible for that theme path" rather than crashing the app.
  static ThemeTag? fromWire(String? wire) {
    if (wire == null) return null;
    for (final tag in ThemeTag.values) {
      if (tag.wireId == wire) return tag;
    }
    return null;
  }

  /// True if the given wire string is in the expanded vocabulary.
  /// Useful for manifest-annotation integrity tests.
  static bool isValid(String wire) {
    return fromWire(wire) != null;
  }

  /// All valid wire IDs as a set — for integrity scans.
  static Set<String> get allWireIds {
    return {for (final tag in ThemeTag.values) tag.wireId};
  }
}

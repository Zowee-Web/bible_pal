/// Canonical PALs Paths theme vocabulary (SPEC Feature 50 — LOCKED for v1).
///
/// Eight values. The list is LOCKED pending owner-approved SPEC update.
/// Every `themeTags[]` entry in any annotated story MUST be one of these
/// wire-format strings. Adding a ninth theme requires:
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
  faith,
  hope,
  mercy,
  courage,
  obedience,
  provision,
  patience,
  forgiveness,
}

extension ThemeTagWire on ThemeTag {
  /// Wire-format ID — must match SPEC Feature 50 vocabulary exactly.
  String get wireId {
    switch (this) {
      case ThemeTag.faith:
        return 'faith';
      case ThemeTag.hope:
        return 'hope';
      case ThemeTag.mercy:
        return 'mercy';
      case ThemeTag.courage:
        return 'courage';
      case ThemeTag.obedience:
        return 'obedience';
      case ThemeTag.provision:
        return 'provision';
      case ThemeTag.patience:
        return 'patience';
      case ThemeTag.forgiveness:
        return 'forgiveness';
    }
  }

  /// User-facing display label. Capitalized for UI.
  String get displayLabel {
    switch (this) {
      case ThemeTag.faith:
        return 'Faith';
      case ThemeTag.hope:
        return 'Hope';
      case ThemeTag.mercy:
        return 'Mercy';
      case ThemeTag.courage:
        return 'Courage';
      case ThemeTag.obedience:
        return 'Obedience';
      case ThemeTag.provision:
        return 'Provision';
      case ThemeTag.patience:
        return 'Patience';
      case ThemeTag.forgiveness:
        return 'Forgiveness';
    }
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

  /// True if the given wire string is in the locked vocabulary.
  /// Useful for manifest-annotation integrity tests.
  static bool isValid(String wire) {
    return fromWire(wire) != null;
  }

  /// All valid wire IDs as a set — for integrity scans.
  static Set<String> get allWireIds {
    return {for (final tag in ThemeTag.values) tag.wireId};
  }
}

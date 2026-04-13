/// Canonical PALs Paths path types (SPEC Feature 50.1 — LOCKED).
///
/// The enum is LOCKED for v1. Wire-format IDs (the strings that appear in
/// telemetry and asset JSON) must match SPEC 50.10 exactly and never change
/// without an owner-approved SPEC update.
///
/// Five path types:
/// - [jesusLife] — SPECIAL featured path (curated, see SPEC 50.1b). Not a
///   Character Path. Jesus is never enumerated under [characters].
/// - [bibleOrder] — canonical Bible order, grouped by book
/// - [timeline] — grouped by one of 9 canonical eras (see [TimelineEra])
/// - [themes] — grouped by `themeTags[]` entries
/// - [characters] — grouped by `primaryCharacterId` (excluding `jesus`)
enum PathType {
  jesusLife,
  bibleOrder,
  timeline,
  themes,
  characters,
}

extension PathTypeWire on PathType {
  /// Wire format used in telemetry payloads and asset JSON.
  /// LOCKED — must match SPEC Feature 50.10 exactly.
  String get wireId {
    switch (this) {
      case PathType.jesusLife:
        return 'jesus_life';
      case PathType.bibleOrder:
        return 'bible_order';
      case PathType.timeline:
        return 'timeline';
      case PathType.themes:
        return 'themes';
      case PathType.characters:
        return 'characters';
    }
  }

  /// User-facing display label.
  String get displayLabel {
    switch (this) {
      case PathType.jesusLife:
        return 'The Life of Jesus';
      case PathType.bibleOrder:
        return 'Bible Order';
      case PathType.timeline:
        return 'Timeline';
      case PathType.themes:
        return 'Themes';
      case PathType.characters:
        return 'Characters';
    }
  }

  /// True for the special featured path — used by the PALs Paths page to
  /// render [jesusLife] as a distinct featured tile (SPEC Feature 50.1b).
  bool get isFeatured => this == PathType.jesusLife;
}

extension PathTypeParse on PathType {
  /// Parse a wire-format string back into a [PathType]. Throws if the
  /// string is not one of the five canonical values.
  static PathType fromWire(String wire) {
    switch (wire) {
      case 'jesus_life':
        return PathType.jesusLife;
      case 'bible_order':
        return PathType.bibleOrder;
      case 'timeline':
        return PathType.timeline;
      case 'themes':
        return PathType.themes;
      case 'characters':
        return PathType.characters;
      default:
        throw ArgumentError('Unknown PathType wire id: "$wire"');
    }
  }
}

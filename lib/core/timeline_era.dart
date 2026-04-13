/// Canonical timeline eras for the PALs Paths `timeline` path
/// (SPEC Feature 50.2 — LOCKED).
///
/// The nine era IDs are LOCKED for v1 and require owner approval to change.
/// Wire-format IDs appear in story metadata (`timelineEra` field) and in
/// telemetry (`path_id` for the timeline path type).
enum TimelineEra {
  creation,
  patriarchs,
  exodus,
  judges,
  kingdom,
  exile,
  returnFromExile,
  jesusMinistry,
  earlyChurch,
}

extension TimelineEraWire on TimelineEra {
  /// Wire-format ID — must match SPEC Feature 50.2 exactly.
  String get wireId {
    switch (this) {
      case TimelineEra.creation:
        return 'creation';
      case TimelineEra.patriarchs:
        return 'patriarchs';
      case TimelineEra.exodus:
        return 'exodus';
      case TimelineEra.judges:
        return 'judges';
      case TimelineEra.kingdom:
        return 'kingdom';
      case TimelineEra.exile:
        return 'exile';
      case TimelineEra.returnFromExile:
        return 'return';
      case TimelineEra.jesusMinistry:
        return 'jesus_ministry';
      case TimelineEra.earlyChurch:
        return 'early_church';
    }
  }

  /// User-facing display label.
  String get displayLabel {
    switch (this) {
      case TimelineEra.creation:
        return 'Creation';
      case TimelineEra.patriarchs:
        return 'Patriarchs';
      case TimelineEra.exodus:
        return 'Exodus';
      case TimelineEra.judges:
        return 'Judges';
      case TimelineEra.kingdom:
        return 'Kingdom';
      case TimelineEra.exile:
        return 'Exile';
      case TimelineEra.returnFromExile:
        return 'Return';
      case TimelineEra.jesusMinistry:
        return 'Jesus Ministry';
      case TimelineEra.earlyChurch:
        return 'Early Church';
    }
  }
}

extension TimelineEraParse on TimelineEra {
  /// Parse a wire-format string into a [TimelineEra]. Returns null for
  /// unknown values so callers (e.g. manifest readers) can treat unknown
  /// eras as "story not eligible for the timeline path" rather than
  /// crashing the app.
  static TimelineEra? fromWire(String? wire) {
    if (wire == null) return null;
    for (final era in TimelineEra.values) {
      if (era.wireId == wire) return era;
    }
    return null;
  }
}

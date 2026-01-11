/// Story length buckets for user-facing selection
/// Based on SPEC.md Feature #6: Story Length Buckets
///
/// Word count ranges (for generation validation):
/// - Short: 300–700 words
/// - Full: 900–1400 words
/// - Long: 1700–2600 words
enum StoryLengthBucket {
  short,
  full,
  long;

  /// User-facing display label
  String get displayLabel {
    switch (this) {
      case StoryLengthBucket.short:
        return 'Short Story';
      case StoryLengthBucket.full:
        return 'Full Story';
      case StoryLengthBucket.long:
        return 'Long Story';
    }
  }

  /// Word count range for generation validation (min, max)
  (int, int) get wordCountRange {
    switch (this) {
      case StoryLengthBucket.short:
        return (300, 700);
      case StoryLengthBucket.full:
        return (900, 1400);
      case StoryLengthBucket.long:
        return (1700, 2600);
    }
  }

  /// Serialize to string for storage/telemetry
  String toJson() => name;

  /// Deserialize from string
  static StoryLengthBucket fromJson(String value) {
    return StoryLengthBucket.values.firstWhere(
      (b) => b.name == value,
      orElse: () => StoryLengthBucket.short, // Safe default
    );
  }
}

/// Maps legacy minute-based length to bucket
/// Used for compatibility with existing story assets
///
/// Mapping:
/// - 5 min  → short
/// - 10 min → short
/// - 15 min → full
/// - 20 min → long
StoryLengthBucket lengthMinutesToBucket(int lengthMinutes) {
  switch (lengthMinutes) {
    case 5:
    case 10:
      return StoryLengthBucket.short;
    case 15:
      return StoryLengthBucket.full;
    case 20:
      return StoryLengthBucket.long;
    default:
      // Fallback for unexpected values: use closest bucket
      if (lengthMinutes <= 10) return StoryLengthBucket.short;
      if (lengthMinutes <= 15) return StoryLengthBucket.full;
      return StoryLengthBucket.long;
  }
}

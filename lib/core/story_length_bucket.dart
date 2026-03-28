/// Story length buckets for user-facing selection
/// Based on SPEC.md Feature #6: Story Length Buckets
///
/// Word count ranges (LOCKED - for generation validation):
/// - Short: 250–600 words
/// - Full: 601–1200 words
/// - Long: 1201–2000 words
enum StoryLengthBucket {
  short,
  full,
  long;

  /// User-facing display label
  String get displayLabel {
    switch (this) {
      case StoryLengthBucket.short:
        return 'A Quick Moment';
      case StoryLengthBucket.full:
        return 'A Quiet Story';
      case StoryLengthBucket.long:
        return 'A Longer Listen';
    }
  }

  /// Subtitle hint for length selection UI
  String get subtitle {
    switch (this) {
      case StoryLengthBucket.short:
        return 'For a pause in your day';
      case StoryLengthBucket.full:
        return 'Settle in for a few minutes';
      case StoryLengthBucket.long:
        return 'When you have time to linger';
    }
  }

  /// Approximate duration label
  String get durationLabel {
    switch (this) {
      case StoryLengthBucket.short:
        return '~2 min';
      case StoryLengthBucket.full:
        return '~5 min';
      case StoryLengthBucket.long:
        return '~10 min';
    }
  }

  /// Word count range for generation validation (min, max)
  /// LOCKED SPEC: short=250-600, full=601-1200, long=1201-2000
  (int, int) get wordCountRange {
    switch (this) {
      case StoryLengthBucket.short:
        return (250, 600);
      case StoryLengthBucket.full:
        return (601, 1200);
      case StoryLengthBucket.long:
        return (1201, 2000);
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
/// Used for compatibility with existing story assets that don't have storyLength
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

/// Computes storyLength bucket from word count
/// LOCKED SPEC thresholds:
/// - short: <= 600 words
/// - full: 601-1200 words
/// - long: 1201-2000 words
StoryLengthBucket wordCountToBucket(int wordCount) {
  if (wordCount <= 600) return StoryLengthBucket.short;
  if (wordCount <= 1200) return StoryLengthBucket.full;
  return StoryLengthBucket.long;
}

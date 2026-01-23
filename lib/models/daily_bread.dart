import '../core/bible_translation_registry.dart';

/// Daily Bread model - represents the daily verse display
/// Based on SPEC.md Features #19, #20: Daily Bread Verse Display and Thematic Alignment
///
/// SCRIPTURE LICENSING COMPLIANCE:
/// translation field MUST ONLY contain allowed translations from BibleTranslationRegistry.
class DailyBread {
  final String verse;
  final String reference; // e.g., "Psalm 16:11"
  final String
      translation; // e.g., "WEB", "KJV", "ASV" - validated against allowlist
  final DateTime date;
  final String? theme; // Optional: for thematic alignment with parable

  const DailyBread({
    required this.verse,
    required this.reference,
    required this.translation,
    required this.date,
    this.theme,
  });

  /// Create from JSON
  factory DailyBread.fromJson(Map<String, dynamic> json) {
    // RUNTIME GUARD: Validate translation against allowlist
    final rawTranslation = json['translation'] as String;
    final validatedTranslation =
        BibleTranslationRegistry.validateAndSanitize(rawTranslation);

    return DailyBread(
      verse: json['verse'] as String,
      reference: json['reference'] as String,
      translation: validatedTranslation, // Guaranteed to be allowed translation
      date: DateTime.parse(json['date'] as String),
      theme: json['theme'] as String?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'verse': verse,
      'reference': reference,
      'translation': translation,
      'date': date.toIso8601String(),
      'theme': theme,
    };
  }

  /// Get formatted display text
  String get displayText => '"$verse" — $reference';

  /// Check if this is for today
  bool get isToday {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }
}

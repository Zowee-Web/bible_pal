import '../core/bible_translation_registry.dart';

/// User Preferences model
/// Stores user settings from onboarding and settings screen
/// Based on SPEC.md Features #17, #18, #21, #22, #23
///
/// SCRIPTURE LICENSING COMPLIANCE:
/// bibleTranslation field MUST ONLY contain open-source/public-domain translations.
/// ALL translations are validated against BibleTranslationRegistry.
/// Banned translations are automatically reset to default.
class UserPreferences {
  final String faithTradition; // Catholic, Protestant, Orthodox, etc.
  final String bibleTranslation; // ONLY open-source: 'WEB', 'KJV', 'ASV'
  final String storytellingMode; // 'creative' or 'traditional'
  final bool contentFilteringEnabled; // Feature #24
  final bool kidFriendlyOnly; // Filter to kid-friendly content only
  final bool hasCompletedOnboarding;

  const UserPreferences({
    required this.faithTradition,
    required this.bibleTranslation,
    this.storytellingMode = 'creative',
    this.contentFilteringEnabled = true,
    this.kidFriendlyOnly = false,
    this.hasCompletedOnboarding = false,
  });

  /// Default preferences for first-time users
  factory UserPreferences.defaults() {
    return const UserPreferences(
      faithTradition: '',
      bibleTranslation: 'WEB', // World English Bible (public domain)
      storytellingMode: 'creative',
      contentFilteringEnabled: true,
      kidFriendlyOnly: false,
      hasCompletedOnboarding: false,
    );
  }

  /// Create from JSON
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    // RUNTIME GUARD: Validate translation against allowlist
    final rawTranslation = json['bibleTranslation'] as String? ?? 'WEB';
    final validatedTranslation = BibleTranslationRegistry.validateAndSanitize(rawTranslation);

    return UserPreferences(
      faithTradition: json['faithTradition'] as String? ?? '',
      bibleTranslation: validatedTranslation, // Guaranteed to be allowed translation
      storytellingMode: json['storytellingMode'] as String? ?? 'creative',
      contentFilteringEnabled:
          json['contentFilteringEnabled'] as bool? ?? true,
      kidFriendlyOnly: json['kidFriendlyOnly'] as bool? ?? false,
      hasCompletedOnboarding:
          json['hasCompletedOnboarding'] as bool? ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'faithTradition': faithTradition,
      'bibleTranslation': bibleTranslation,
      'storytellingMode': storytellingMode,
      'contentFilteringEnabled': contentFilteringEnabled,
      'kidFriendlyOnly': kidFriendlyOnly,
      'hasCompletedOnboarding': hasCompletedOnboarding,
    };
  }

  /// Create a copy with modified fields
  UserPreferences copyWith({
    String? faithTradition,
    String? bibleTranslation,
    String? storytellingMode,
    bool? contentFilteringEnabled,
    bool? kidFriendlyOnly,
    bool? hasCompletedOnboarding,
  }) {
    // RUNTIME GUARD: Validate translation if provided
    final validatedTranslation = bibleTranslation != null
        ? BibleTranslationRegistry.validateAndSanitize(bibleTranslation)
        : this.bibleTranslation;

    return UserPreferences(
      faithTradition: faithTradition ?? this.faithTradition,
      bibleTranslation: validatedTranslation,
      storytellingMode: storytellingMode ?? this.storytellingMode,
      contentFilteringEnabled:
          contentFilteringEnabled ?? this.contentFilteringEnabled,
      kidFriendlyOnly: kidFriendlyOnly ?? this.kidFriendlyOnly,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
    );
  }

  /// Check if onboarding is complete (has required fields)
  bool get isOnboardingComplete =>
      hasCompletedOnboarding &&
      faithTradition.isNotEmpty &&
      bibleTranslation.isNotEmpty;
}

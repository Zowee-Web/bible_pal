import '../core/bible_translation_registry.dart';

/// User Preferences model
/// Stores user settings from onboarding and settings screen
/// Based on SPEC.md Features #17, #18, #21, #22, #23
///
/// SCRIPTURE LICENSING COMPLIANCE:
/// bibleTranslation field MUST ONLY contain open-source/public-domain translations.
/// ALL translations are validated against BibleTranslationRegistry.
/// Banned translations are automatically reset to default.
/// Allowed values for storyLanguage (stricter than bibleTranslation)
const List<String> allowedStoryLanguages = ['WEB', 'KJV'];

/// Validates and sanitizes storyLanguage, returning 'WEB' if invalid
String _validateStoryLanguage(String? value) {
  if (value == null || !allowedStoryLanguages.contains(value)) {
    return 'WEB'; // Default to WEB if invalid
  }
  return value;
}

class UserPreferences {
  final String faithTradition; // Catholic, Protestant, Orthodox, etc.
  final String bibleTranslation; // ONLY open-source: 'WEB', 'KJV', 'ASV', 'YLT', 'DRA' (for Daily Bread)
  final String storyLanguage; // ONLY 'WEB' or 'KJV' (for story filtering, stricter than bibleTranslation)
  final String storytellingMode; // 'creative' or 'traditional'
  final bool contentFilteringEnabled; // Feature #24
  final bool kidFriendlyOnly; // Filter to kid-friendly content only
  final bool showEverydayReflections; // Feature #34: Post-story reflections
  final bool hasCompletedOnboarding;

  const UserPreferences({
    required this.faithTradition,
    required this.bibleTranslation,
    this.storyLanguage = 'WEB', // Default to Modern (WEB) for stories
    this.storytellingMode = 'creative',
    this.contentFilteringEnabled = true,
    this.kidFriendlyOnly = false,
    this.showEverydayReflections = true, // Default ON per SPEC.md #34
    this.hasCompletedOnboarding = false,
  });

  /// Default preferences for first-time users
  factory UserPreferences.defaults() {
    return const UserPreferences(
      faithTradition: '',
      bibleTranslation: 'WEB', // World English Bible (public domain) - for Daily Bread
      storyLanguage: 'WEB', // Modern stories (WEB) - for story filtering
      storytellingMode: 'creative',
      contentFilteringEnabled: true,
      kidFriendlyOnly: false,
      showEverydayReflections: true, // Default ON per SPEC.md #34
      hasCompletedOnboarding: false,
    );
  }

  /// Create from JSON
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    // RUNTIME GUARD: Validate bibleTranslation against allowlist
    final rawTranslation = json['bibleTranslation'] as String? ?? 'WEB';
    final validatedTranslation = BibleTranslationRegistry.validateAndSanitize(rawTranslation);

    // RUNTIME GUARD: Validate storyLanguage (stricter: only WEB or KJV)
    final rawStoryLanguage = json['storyLanguage'] as String?;
    final validatedStoryLanguage = _validateStoryLanguage(rawStoryLanguage);

    return UserPreferences(
      faithTradition: json['faithTradition'] as String? ?? '',
      bibleTranslation: validatedTranslation, // Guaranteed to be allowed translation
      storyLanguage: validatedStoryLanguage, // Guaranteed to be WEB or KJV
      storytellingMode: json['storytellingMode'] as String? ?? 'creative',
      contentFilteringEnabled:
          json['contentFilteringEnabled'] as bool? ?? true,
      kidFriendlyOnly: json['kidFriendlyOnly'] as bool? ?? false,
      showEverydayReflections:
          json['showEverydayReflections'] as bool? ?? true, // Default ON
      hasCompletedOnboarding:
          json['hasCompletedOnboarding'] as bool? ?? false,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'faithTradition': faithTradition,
      'bibleTranslation': bibleTranslation,
      'storyLanguage': storyLanguage,
      'storytellingMode': storytellingMode,
      'contentFilteringEnabled': contentFilteringEnabled,
      'kidFriendlyOnly': kidFriendlyOnly,
      'showEverydayReflections': showEverydayReflections,
      'hasCompletedOnboarding': hasCompletedOnboarding,
    };
  }

  /// Create a copy with modified fields
  UserPreferences copyWith({
    String? faithTradition,
    String? bibleTranslation,
    String? storyLanguage,
    String? storytellingMode,
    bool? contentFilteringEnabled,
    bool? kidFriendlyOnly,
    bool? showEverydayReflections,
    bool? hasCompletedOnboarding,
  }) {
    // RUNTIME GUARD: Validate translation if provided
    final validatedTranslation = bibleTranslation != null
        ? BibleTranslationRegistry.validateAndSanitize(bibleTranslation)
        : this.bibleTranslation;

    // RUNTIME GUARD: Validate storyLanguage if provided (stricter: only WEB or KJV)
    final validatedStoryLanguage = storyLanguage != null
        ? _validateStoryLanguage(storyLanguage)
        : this.storyLanguage;

    return UserPreferences(
      faithTradition: faithTradition ?? this.faithTradition,
      bibleTranslation: validatedTranslation,
      storyLanguage: validatedStoryLanguage,
      storytellingMode: storytellingMode ?? this.storytellingMode,
      contentFilteringEnabled:
          contentFilteringEnabled ?? this.contentFilteringEnabled,
      kidFriendlyOnly: kidFriendlyOnly ?? this.kidFriendlyOnly,
      showEverydayReflections:
          showEverydayReflections ?? this.showEverydayReflections,
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

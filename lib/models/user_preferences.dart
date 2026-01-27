import '../core/bible_translation_registry.dart';

/// User Preferences model
/// Stores user settings from onboarding and settings screen
/// Based on SPEC.md Features #17, #18, #21, #22, #23
/// Updated for Story Mode Contracts v2 (SPEC.md)
///
/// SCRIPTURE LICENSING COMPLIANCE:
/// bibleTranslation field MUST ONLY contain open-source/public-domain translations.
/// ALL translations are validated against BibleTranslationRegistry.
/// Banned translations are automatically reset to default.

/// Allowed values for languageStyle (story presentation diction)
/// Contracts v2: languageStyle is separate from bibleTranslation (compliance)
const List<String> allowedLanguageStyles = ['WEB', 'KJV'];

/// Current voice consent schema version.
/// Increment this to re-prompt users for consent (e.g., if we add new voice features).
const int currentVoiceConsentVersion = 1;

/// Validates and sanitizes languageStyle, returning 'WEB' if invalid
String _validateLanguageStyle(String? value) {
  if (value == null || !allowedLanguageStyles.contains(value)) {
    return 'WEB'; // Default to WEB (modern) if invalid
  }
  return value;
}

class UserPreferences {
  final String
      userName; // User's name (collected during first-launch onboarding)
  final String
      bibleTranslation; // ONLY open-source: 'WEB', 'KJV', 'ASV', 'YLT', 'DRA' (for Daily Bread)
  final String
      languageStyle; // 'WEB' or 'KJV' - story presentation diction (Contracts v2)
  final String
      storytellingMode; // 'creative' or 'traditional' - DEFAULT is 'traditional' (Contracts v2)
  final bool contentFilteringEnabled; // Feature #24
  final bool kidFriendlyOnly; // Filter to kid-friendly content only
  final bool showEverydayReflections; // Feature #34: Post-story reflections
  final bool hasCompletedOnboarding;

  // Voice consent fields (Phase 3)
  // null = not asked yet, true = enabled, false = disabled
  final bool? storyNarrationEnabled; // Audio playback of stories
  final bool? palGreetingsEnabled; // PAL voice greetings (future)
  final int? voiceConsentVersion; // Schema version when consent was given

  const UserPreferences({
    this.userName = '',
    required this.bibleTranslation,
    this.languageStyle =
        'WEB', // Default to Modern (WEB) for story presentation
    this.storytellingMode =
        'traditional', // DEFAULT is Traditional per Contracts v2
    this.contentFilteringEnabled = true,
    this.kidFriendlyOnly = false,
    this.showEverydayReflections = true, // Default ON per SPEC.md #34
    this.hasCompletedOnboarding = false,
    this.storyNarrationEnabled, // null = not asked
    this.palGreetingsEnabled, // null = not asked
    this.voiceConsentVersion, // null = never consented
  });

  /// Default preferences for first-time users
  /// Contracts v2: storytellingMode defaults to 'traditional'
  /// Voice consent fields are null (tri-state: null=not asked, true=enabled, false=disabled)
  factory UserPreferences.defaults() {
    return const UserPreferences(
      userName: '',
      bibleTranslation:
          'WEB', // World English Bible (public domain) - for Daily Bread
      languageStyle: 'WEB', // Modern diction (WEB) - for story presentation
      storytellingMode:
          'traditional', // DEFAULT is Traditional per Contracts v2
      contentFilteringEnabled: true,
      kidFriendlyOnly: false,
      showEverydayReflections: true, // Default ON per SPEC.md #34
      hasCompletedOnboarding: false,
      // Voice consent: null = not asked yet (tri-state model)
      // Onboarding sets these to true when user completes first launch
    );
  }

  /// Create from JSON
  factory UserPreferences.fromJson(Map<String, dynamic> json) {
    // RUNTIME GUARD: Validate bibleTranslation against allowlist
    final rawTranslation = json['bibleTranslation'] as String? ?? 'WEB';
    final validatedTranslation =
        BibleTranslationRegistry.validateAndSanitize(rawTranslation);

    // RUNTIME GUARD: Validate languageStyle (only WEB or KJV)
    // Backwards compat: check both 'languageStyle' and legacy 'storyLanguage'
    final rawLanguageStyle =
        json['languageStyle'] as String? ?? json['storyLanguage'] as String?;
    final validatedLanguageStyle = _validateLanguageStyle(rawLanguageStyle);

    // Contracts v2: Default storytellingMode is 'traditional'
    final storytellingMode =
        json['storytellingMode'] as String? ?? 'traditional';

    return UserPreferences(
      userName: json['userName'] as String? ?? '',
      bibleTranslation:
          validatedTranslation, // Guaranteed to be allowed translation
      languageStyle: validatedLanguageStyle, // Guaranteed to be WEB or KJV
      storytellingMode: storytellingMode,
      contentFilteringEnabled: json['contentFilteringEnabled'] as bool? ?? true,
      kidFriendlyOnly: json['kidFriendlyOnly'] as bool? ?? false,
      showEverydayReflections:
          json['showEverydayReflections'] as bool? ?? true, // Default ON
      hasCompletedOnboarding: json['hasCompletedOnboarding'] as bool? ?? false,
      storyNarrationEnabled: json['storyNarrationEnabled'] as bool?,
      palGreetingsEnabled: json['palGreetingsEnabled'] as bool?,
      voiceConsentVersion: json['voiceConsentVersion'] as int?,
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'userName': userName,
      'bibleTranslation': bibleTranslation,
      'languageStyle': languageStyle, // Contracts v2 field name
      'storytellingMode': storytellingMode,
      'contentFilteringEnabled': contentFilteringEnabled,
      'kidFriendlyOnly': kidFriendlyOnly,
      'showEverydayReflections': showEverydayReflections,
      'hasCompletedOnboarding': hasCompletedOnboarding,
      'storyNarrationEnabled': storyNarrationEnabled,
      'palGreetingsEnabled': palGreetingsEnabled,
      'voiceConsentVersion': voiceConsentVersion,
    };
  }

  /// Create a copy with modified fields
  ///
  /// For nullable voice consent fields, use the special sentinel value pattern:
  /// - Pass nothing to keep current value
  /// - Pass a value to set it
  /// To explicitly set to null, use clearVoiceConsent() instead.
  UserPreferences copyWith({
    String? userName,
    String? bibleTranslation,
    String? languageStyle,
    String? storytellingMode,
    bool? contentFilteringEnabled,
    bool? kidFriendlyOnly,
    bool? showEverydayReflections,
    bool? hasCompletedOnboarding,
    bool? storyNarrationEnabled,
    bool? palGreetingsEnabled,
    int? voiceConsentVersion,
  }) {
    // RUNTIME GUARD: Validate translation if provided
    final validatedTranslation = bibleTranslation != null
        ? BibleTranslationRegistry.validateAndSanitize(bibleTranslation)
        : this.bibleTranslation;

    // RUNTIME GUARD: Validate languageStyle if provided (only WEB or KJV)
    final validatedLanguageStyle = languageStyle != null
        ? _validateLanguageStyle(languageStyle)
        : this.languageStyle;

    return UserPreferences(
      userName: userName ?? this.userName,
      bibleTranslation: validatedTranslation,
      languageStyle: validatedLanguageStyle,
      storytellingMode: storytellingMode ?? this.storytellingMode,
      contentFilteringEnabled:
          contentFilteringEnabled ?? this.contentFilteringEnabled,
      kidFriendlyOnly: kidFriendlyOnly ?? this.kidFriendlyOnly,
      showEverydayReflections:
          showEverydayReflections ?? this.showEverydayReflections,
      hasCompletedOnboarding:
          hasCompletedOnboarding ?? this.hasCompletedOnboarding,
      storyNarrationEnabled:
          storyNarrationEnabled ?? this.storyNarrationEnabled,
      palGreetingsEnabled: palGreetingsEnabled ?? this.palGreetingsEnabled,
      voiceConsentVersion: voiceConsentVersion ?? this.voiceConsentVersion,
    );
  }

  /// Check if onboarding is complete (has required fields)
  bool get isOnboardingComplete =>
      hasCompletedOnboarding && bibleTranslation.isNotEmpty;

  // === Voice Consent Helpers ===

  /// True if story narration consent has been asked (regardless of answer)
  bool get hasAskedStoryNarrationConsent => storyNarrationEnabled != null;

  /// True if PAL greetings consent has been asked (regardless of answer)
  bool get hasAskedPalGreetingsConsent => palGreetingsEnabled != null;

  /// True if story narration is explicitly enabled
  bool get isStoryNarrationEnabled => storyNarrationEnabled == true;

  /// True if PAL greetings are explicitly enabled
  bool get isPalGreetingsEnabled => palGreetingsEnabled == true;

  /// Check if we need to re-ask consent due to version upgrade
  bool get needsConsentVersionUpgrade =>
      voiceConsentVersion != null &&
      voiceConsentVersion! < currentVoiceConsentVersion;
}

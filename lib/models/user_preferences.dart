import '../core/bible_translation_registry.dart';
import '../core/pal_voice_registry.dart';

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

/// Allowed mood IDs for lastDetectedMood (SPEC Feature #21: Thematic Alignment).
/// Only these values are persisted; anything else is treated as null.
const Set<String> allowedMoodIds = {
  'joyful',
  'weary',
  'anxious',
  'hurting',
  'grateful',
  'brave_courage',
  'calm_peaceful',
  'encouraging',
};

/// Validates a mood ID, returning null if not in allowedMoodIds.
String? _validateMood(String? value) {
  if (value == null || !allowedMoodIds.contains(value)) return null;
  return value;
}

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
  // TODO(creative-retirement): Remove during Stage 2 retirement (planned 2026-05-13).
  //   See docs/archive/CREATIVE_RETIREMENT_2026_05_13.md
  //   Coerce-on-load migration: 'creative' values should map to 'traditional'.
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

  // PAL voice audio master switch (internal, no UI yet)
  final bool palVoiceEnabled; // When false, all PAL audio falls back to text-only

  // Legacy PAL audio flag (internal, no UI).
  // When false (default), old PROMPT_*/RESP_* audio is disabled;
  // the new opening + framing overlay system is the sole active flow.
  final bool useLegacyPal;

  // PAL voice selection
  final String palVoiceKey; // Selected PAL conversation voice

  // Thematic alignment (SPEC Feature #21)
  // Last detected mood for mood-biased Daily Bread verse selection.
  // null = no mood detected yet; only allowedMoodIds values are persisted.
  final String? lastDetectedMood;

  // Preferred story length bucket (remembered from last selection)
  // null = not yet chosen; user will be prompted. Once set, auto-selects.
  final String? preferredLengthBucket;

  // Bedtime mode: dims UI, fades audio after story, sleep timer
  final bool bedtimeModeEnabled;
  final int sleepTimerMinutes; // Minutes after story ends before app sleeps (0 = immediate)

  // Listening streak tracking
  final int currentStreak; // Consecutive days of listening
  final String? lastListenDate; // ISO date string (yyyy-MM-dd) of last listen

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
    this.palVoiceEnabled = true, // internal master switch, default ON
    this.useLegacyPal = false, // legacy PAL audio disabled by default
    this.palVoiceKey = PalVoiceRegistry.defaultVoiceKey,
    this.lastDetectedMood,
    this.preferredLengthBucket,
    this.bedtimeModeEnabled = false,
    this.sleepTimerMinutes = 5,
    this.currentStreak = 0,
    this.lastListenDate,
  });

  /// Default preferences for first-time users
  /// Contracts v2: storytellingMode defaults to 'traditional'
  /// Voice features default to ON; user must explicitly turn them OFF.
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
      storyNarrationEnabled: true, // ON by default
      palGreetingsEnabled: true, // ON by default
      voiceConsentVersion: currentVoiceConsentVersion,
      palVoiceEnabled: true, // ON by default (internal, no UI)
      useLegacyPal: false, // new PAL system active by default
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
      storyNarrationEnabled: json['storyNarrationEnabled'] as bool? ?? true,
      palGreetingsEnabled: json['palGreetingsEnabled'] as bool? ?? true,
      voiceConsentVersion: json['voiceConsentVersion'] as int?,
      palVoiceEnabled: json['palVoiceEnabled'] as bool? ?? true,
      useLegacyPal: json['useLegacyPal'] as bool? ?? false,
      palVoiceKey: PalVoiceRegistry.migrateVoiceKey(
          json['palVoiceKey'] as String? ?? PalVoiceRegistry.defaultVoiceKey),
      lastDetectedMood:
          _validateMood(json['lastDetectedMood'] as String?),
      preferredLengthBucket: json['preferredLengthBucket'] as String?,
      bedtimeModeEnabled: json['bedtimeModeEnabled'] as bool? ?? false,
      sleepTimerMinutes: json['sleepTimerMinutes'] as int? ?? 5,
      currentStreak: json['currentStreak'] as int? ?? 0,
      lastListenDate: json['lastListenDate'] as String?,
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
      'palVoiceEnabled': palVoiceEnabled,
      'useLegacyPal': useLegacyPal,
      'palVoiceKey': palVoiceKey,
      'lastDetectedMood': lastDetectedMood,
      'preferredLengthBucket': preferredLengthBucket,
      'bedtimeModeEnabled': bedtimeModeEnabled,
      'sleepTimerMinutes': sleepTimerMinutes,
      'currentStreak': currentStreak,
      'lastListenDate': lastListenDate,
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
    bool? palVoiceEnabled,
    bool? useLegacyPal,
    String? palVoiceKey,
    String? lastDetectedMood,
    String? preferredLengthBucket,
    bool? bedtimeModeEnabled,
    int? sleepTimerMinutes,
    int? currentStreak,
    String? lastListenDate,
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
      palVoiceEnabled: palVoiceEnabled ?? this.palVoiceEnabled,
      useLegacyPal: useLegacyPal ?? this.useLegacyPal,
      palVoiceKey: palVoiceKey ?? this.palVoiceKey,
      lastDetectedMood: lastDetectedMood ?? this.lastDetectedMood,
      preferredLengthBucket:
          preferredLengthBucket ?? this.preferredLengthBucket,
      bedtimeModeEnabled: bedtimeModeEnabled ?? this.bedtimeModeEnabled,
      sleepTimerMinutes: sleepTimerMinutes ?? this.sleepTimerMinutes,
      currentStreak: currentStreak ?? this.currentStreak,
      lastListenDate: lastListenDate ?? this.lastListenDate,
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

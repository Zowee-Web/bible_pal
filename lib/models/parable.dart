import '../core/story_length_bucket.dart';

/// Parable model - represents a single parable/story
/// Based on SPEC.md Feature #8: Parable Metadata System
/// Updated for Story Mode Contracts v2 (SPEC.md)
/// Updated for ADR-010: Traditional Mode = Real Bible Story System
class Parable {
  final String storyId;
  final String title; // AI-generated, can be edited by user
  final String mood; // e.g., 'joyful', 'anxious', 'weary', 'hurting', 'neutral'
  final List<String> emotionalTags;
  final int?
      length; // Nullable: null means bucket-first entry (use storyLength instead)
  final String?
      storyLength; // Primary: 'short', 'full', or 'long' (LOCKED SPEC)
  // TODO(creative-retirement): Remove during Stage 2 retirement (planned 2026-05-13).
  //   See docs/archive/CREATIVE_RETIREMENT_2026_05_13.md
  //   Keep field for backward parse of legacy manifest entries; Traditional-only going forward.
  final String storytellingMode; // 'creative' or 'traditional'
  final String
      translationId; // Bible translation for compliance (Daily Bread, quotes)
  final String
      languageStyle; // 'WEB' or 'KJV' - story presentation diction (Contracts v2)
  final String?
      bibleSourceRef; // Scripture reference - REQUIRED for Traditional, ABSENT for Creative
  final String?
      bibleStoryKey; // Canonical Bible story identifier - REQUIRED for Traditional (ADR-010)
  final bool kidFriendly; // Content appropriate for children
  final List<String> scriptureSources; // Array of verse references
  final String? audioFilePath; // Path to pre-generated audio file
  final String? textFilePath; // Path to story text file
  final String? scriptureTextFilePath; // Path to scripture passage text file
  final String? reflectionAudioPath; // Path to pre-generated reflection audio
  final String?
      narratorVoiceKey; // Symbolic voice key (e.g., 'VOICE_JAMES_HUSKY')
  final String?
      reflectionQuestion; // Optional gentle question (SPEC Feature 37, display-only)
  final DateTime? generatedAt;
  final String?
      timeOfDay; // 'morning', 'evening', or null (any time). Used for time-based story selection.
  final String?
      seasonTag; // 'advent', 'lent', 'easter', 'thanksgiving', or null. For seasonal story surfacing.

  // PALs Paths metadata (Feature 50, Traditional stories only). All nullable —
  // stories without these fields remain fully servable via mood flow, favorites,
  // history, and baseline search (title / bibleSourceRef / bibleStoryKey). They
  // are opt-in for structured path membership. See SPEC 50.9.
  final String? primaryCharacterId;
  final String? primaryCharacterDisplayName;
  final List<String>? characterIds;
  final List<String>? characterDisplayNames;
  final int? bibleOrderIndex;
  final String? timelineEra;
  final List<String>? themeTags;
  final int? characterPathOrder;

  /// Internal-only MICRO classification flag.
  /// True when this is a tightly-focused emotional scripture extract that runs
  /// 50-250 words (shorter than the standard Short bucket of 300-500). Stored
  /// under `lengths: ["short"]` so users still see it in the Short selection,
  /// but selection logic may bias toward MICRO stories first when the user's
  /// detected mood is high-intensity (anxious / hurting / weary). See SPEC
  /// "Micro serving bias" and `feedback_micro_stories.md` in agent memory.
  final bool shortScripture;

  const Parable({
    required this.storyId,
    required this.title,
    required this.mood,
    this.emotionalTags = const [],
    this.length,
    this.storyLength, // Optional for backwards compat; uses lengthBucket getter if missing
    required this.storytellingMode,
    this.translationId = 'WEB', // Default to WEB for backwards compatibility
    this.languageStyle =
        'WEB', // Default to WEB (modern) for story presentation
    this.bibleSourceRef, // REQUIRED for Traditional, ABSENT for Creative (Contracts v2)
    this.bibleStoryKey, // REQUIRED for Traditional, ABSENT for Creative (ADR-010)
    required this.kidFriendly,
    this.scriptureSources = const [],
    this.audioFilePath,
    this.textFilePath,
    this.scriptureTextFilePath,
    this.reflectionAudioPath,
    this.narratorVoiceKey,
    this.reflectionQuestion,
    this.generatedAt,
    this.timeOfDay,
    this.seasonTag,
    this.primaryCharacterId,
    this.primaryCharacterDisplayName,
    this.characterIds,
    this.characterDisplayNames,
    this.bibleOrderIndex,
    this.timelineEra,
    this.themeTags,
    this.characterPathOrder,
    this.shortScripture = false,
  });

  /// Create from JSON (for storage/retrieval)
  factory Parable.fromJson(Map<String, dynamic> json) {
    // languageStyle: use explicit field, or fall back to translationId for backwards compat
    final explicitLanguageStyle = json['languageStyle'] as String?;
    final fallbackFromTranslation = json['translationId'] as String?;
    final languageStyle =
        explicitLanguageStyle ?? fallbackFromTranslation ?? 'WEB';
    // Normalize languageStyle to only WEB or KJV
    final normalizedLanguageStyle = (languageStyle == 'KJV') ? 'KJV' : 'WEB';

    return Parable(
      storyId: json['storyId'] as String,
      title: json['title'] as String,
      mood: json['mood'] as String,
      emotionalTags: (json['emotionalTags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      length: json['length'] as int?,
      storyLength:
          json['storyLength'] as String?, // Primary field for filtering
      storytellingMode: json['storytellingMode'] as String,
      translationId: json['translationId'] as String? ?? 'WEB',
      languageStyle:
          normalizedLanguageStyle, // Contracts v2: presentation diction
      bibleSourceRef:
          json['bibleSourceRef'] as String?, // Contracts v2: scripture ref
      bibleStoryKey: json['bibleStoryKey']
          as String?, // ADR-010: canonical Bible story key
      kidFriendly: json['kidFriendly'] as bool? ?? false,
      scriptureSources: (json['scriptureSources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      audioFilePath: json['audioFilePath'] as String?,
      textFilePath: json['textFilePath'] as String?,
      scriptureTextFilePath: json['scriptureTextFilePath'] as String?,
      reflectionAudioPath: json['reflectionAudioPath'] as String?,
      narratorVoiceKey: json['narratorVoiceKey'] as String?,
      reflectionQuestion: json['reflectionQuestion'] as String?,
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : null,
      timeOfDay: json['timeOfDay'] as String?,
      seasonTag: json['seasonTag'] as String?,
      // PALs Paths metadata (Feature 50) — all optional, all nullable.
      primaryCharacterId: json['primaryCharacterId'] as String?,
      primaryCharacterDisplayName:
          json['primaryCharacterDisplayName'] as String?,
      characterIds: (json['characterIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      characterDisplayNames: (json['characterDisplayNames'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      bibleOrderIndex: json['bibleOrderIndex'] as int?,
      timelineEra: json['timelineEra'] as String?,
      themeTags: (json['themeTags'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      characterPathOrder: json['characterPathOrder'] as int?,
      shortScripture: json['shortScripture'] as bool? ?? false,
    );
  }

  /// Convert to JSON (for storage)
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'storyId': storyId,
      'title': title,
      'mood': mood,
      'emotionalTags': emotionalTags,
      if (length != null) 'length': length,
      'storyLength':
          storyLength ?? lengthBucket.name, // Always include storyLength
      'storytellingMode': storytellingMode,
      'translationId': translationId,
      'languageStyle': languageStyle, // Contracts v2: presentation diction
      'kidFriendly': kidFriendly,
      'scriptureSources': scriptureSources,
      'audioFilePath': audioFilePath,
      'textFilePath': textFilePath,
      'scriptureTextFilePath': scriptureTextFilePath,
      'reflectionAudioPath': reflectionAudioPath,
      'narratorVoiceKey': narratorVoiceKey,
      'reflectionQuestion': reflectionQuestion,
      'generatedAt': generatedAt?.toIso8601String(),
      if (timeOfDay != null) 'timeOfDay': timeOfDay,
      if (seasonTag != null) 'seasonTag': seasonTag,
    };
    // Contracts v2: Only include bibleSourceRef if present (required for Traditional)
    if (bibleSourceRef != null && bibleSourceRef!.isNotEmpty) {
      json['bibleSourceRef'] = bibleSourceRef;
    }
    // ADR-010: Only include bibleStoryKey if present (required for Traditional)
    if (bibleStoryKey != null && bibleStoryKey!.isNotEmpty) {
      json['bibleStoryKey'] = bibleStoryKey;
    }
    // PALs Paths metadata (Feature 50) — only serialize when present so
    // legacy manifests remain byte-identical and Creative stories never
    // acquire path fields on round-trip.
    if (primaryCharacterId != null) {
      json['primaryCharacterId'] = primaryCharacterId;
    }
    if (primaryCharacterDisplayName != null) {
      json['primaryCharacterDisplayName'] = primaryCharacterDisplayName;
    }
    if (characterIds != null) {
      json['characterIds'] = characterIds;
    }
    if (characterDisplayNames != null) {
      json['characterDisplayNames'] = characterDisplayNames;
    }
    if (bibleOrderIndex != null) {
      json['bibleOrderIndex'] = bibleOrderIndex;
    }
    if (timelineEra != null) {
      json['timelineEra'] = timelineEra;
    }
    if (themeTags != null) {
      json['themeTags'] = themeTags;
    }
    if (characterPathOrder != null) {
      json['characterPathOrder'] = characterPathOrder;
    }
    // MICRO flag — only emit when true so legacy entries stay byte-identical.
    if (shortScripture) {
      json['shortScripture'] = true;
    }
    return json;
  }

  /// Get length bucket for filtering
  /// Priority: storyLength field (LOCKED SPEC) > legacy minute-based fallback
  StoryLengthBucket get lengthBucket {
    // Use storyLength field if present (primary method)
    if (storyLength != null) {
      return StoryLengthBucket.fromJson(storyLength!);
    }
    // Fallback to legacy minute-based mapping
    return lengthMinutesToBucket(length ?? 0);
  }

  /// Create a copy with modified fields (for title editing, etc.)
  Parable copyWith({
    String? storyId,
    String? title,
    String? mood,
    List<String>? emotionalTags,
    int? length,
    String? storyLength,
    String? storytellingMode,
    String? translationId,
    String? languageStyle,
    String? bibleSourceRef,
    String? bibleStoryKey,
    bool? kidFriendly,
    List<String>? scriptureSources,
    String? audioFilePath,
    String? textFilePath,
    String? scriptureTextFilePath,
    String? reflectionAudioPath,
    String? narratorVoiceKey,
    String? reflectionQuestion,
    DateTime? generatedAt,
    String? timeOfDay,
    String? seasonTag,
    String? primaryCharacterId,
    String? primaryCharacterDisplayName,
    List<String>? characterIds,
    List<String>? characterDisplayNames,
    int? bibleOrderIndex,
    String? timelineEra,
    List<String>? themeTags,
    int? characterPathOrder,
    bool? shortScripture,
  }) {
    return Parable(
      storyId: storyId ?? this.storyId,
      title: title ?? this.title,
      mood: mood ?? this.mood,
      emotionalTags: emotionalTags ?? this.emotionalTags,
      length: length ?? this.length,
      storyLength: storyLength ?? this.storyLength,
      storytellingMode: storytellingMode ?? this.storytellingMode,
      translationId: translationId ?? this.translationId,
      languageStyle: languageStyle ?? this.languageStyle,
      bibleSourceRef: bibleSourceRef ?? this.bibleSourceRef,
      bibleStoryKey: bibleStoryKey ?? this.bibleStoryKey,
      kidFriendly: kidFriendly ?? this.kidFriendly,
      scriptureSources: scriptureSources ?? this.scriptureSources,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      textFilePath: textFilePath ?? this.textFilePath,
      scriptureTextFilePath:
          scriptureTextFilePath ?? this.scriptureTextFilePath,
      reflectionAudioPath: reflectionAudioPath ?? this.reflectionAudioPath,
      narratorVoiceKey: narratorVoiceKey ?? this.narratorVoiceKey,
      reflectionQuestion: reflectionQuestion ?? this.reflectionQuestion,
      generatedAt: generatedAt ?? this.generatedAt,
      timeOfDay: timeOfDay ?? this.timeOfDay,
      seasonTag: seasonTag ?? this.seasonTag,
      primaryCharacterId: primaryCharacterId ?? this.primaryCharacterId,
      primaryCharacterDisplayName:
          primaryCharacterDisplayName ?? this.primaryCharacterDisplayName,
      characterIds: characterIds ?? this.characterIds,
      characterDisplayNames:
          characterDisplayNames ?? this.characterDisplayNames,
      bibleOrderIndex: bibleOrderIndex ?? this.bibleOrderIndex,
      timelineEra: timelineEra ?? this.timelineEra,
      themeTags: themeTags ?? this.themeTags,
      characterPathOrder: characterPathOrder ?? this.characterPathOrder,
      shortScripture: shortScripture ?? this.shortScripture,
    );
  }

  /// Check if this story has a valid bibleSourceRef (for Traditional mode validation)
  bool get hasBibleSourceRef =>
      bibleSourceRef != null && bibleSourceRef!.isNotEmpty;

  /// Check if this story has a valid bibleStoryKey (for Traditional mode validation - ADR-010)
  bool get hasBibleStoryKey =>
      bibleStoryKey != null && bibleStoryKey!.isNotEmpty;
}

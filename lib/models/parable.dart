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
  final int
      length; // 5, 10, 15, or 20 minutes (legacy, for asset compatibility)
  final String?
      storyLength; // Primary: 'short', 'full', or 'long' (LOCKED SPEC)
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
  final String? reflectionAudioPath; // Path to pre-generated reflection audio
  final String?
      narratorVoiceKey; // Symbolic voice key (e.g., 'VOICE_JAMES_HUSKY')
  final DateTime? generatedAt;

  const Parable({
    required this.storyId,
    required this.title,
    required this.mood,
    this.emotionalTags = const [],
    required this.length,
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
    this.reflectionAudioPath,
    this.narratorVoiceKey,
    this.generatedAt,
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
      length: json['length'] as int,
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
      reflectionAudioPath: json['reflectionAudioPath'] as String?,
      narratorVoiceKey: json['narratorVoiceKey'] as String?,
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : null,
    );
  }

  /// Convert to JSON (for storage)
  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'storyId': storyId,
      'title': title,
      'mood': mood,
      'emotionalTags': emotionalTags,
      'length': length,
      'storyLength':
          storyLength ?? lengthBucket.name, // Always include storyLength
      'storytellingMode': storytellingMode,
      'translationId': translationId,
      'languageStyle': languageStyle, // Contracts v2: presentation diction
      'kidFriendly': kidFriendly,
      'scriptureSources': scriptureSources,
      'audioFilePath': audioFilePath,
      'textFilePath': textFilePath,
      'reflectionAudioPath': reflectionAudioPath,
      'narratorVoiceKey': narratorVoiceKey,
      'generatedAt': generatedAt?.toIso8601String(),
    };
    // Contracts v2: Only include bibleSourceRef if present (required for Traditional)
    if (bibleSourceRef != null && bibleSourceRef!.isNotEmpty) {
      json['bibleSourceRef'] = bibleSourceRef;
    }
    // ADR-010: Only include bibleStoryKey if present (required for Traditional)
    if (bibleStoryKey != null && bibleStoryKey!.isNotEmpty) {
      json['bibleStoryKey'] = bibleStoryKey;
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
    return lengthMinutesToBucket(length);
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
    String? reflectionAudioPath,
    String? narratorVoiceKey,
    DateTime? generatedAt,
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
      reflectionAudioPath: reflectionAudioPath ?? this.reflectionAudioPath,
      narratorVoiceKey: narratorVoiceKey ?? this.narratorVoiceKey,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }

  /// Check if this story has a valid bibleSourceRef (for Traditional mode validation)
  bool get hasBibleSourceRef =>
      bibleSourceRef != null && bibleSourceRef!.isNotEmpty;

  /// Check if this story has a valid bibleStoryKey (for Traditional mode validation - ADR-010)
  bool get hasBibleStoryKey =>
      bibleStoryKey != null && bibleStoryKey!.isNotEmpty;
}

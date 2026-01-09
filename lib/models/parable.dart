/// Parable model - represents a single parable/story
/// Based on SPEC.md Feature #7: Parable Metadata System
class Parable {
  final String storyId;
  final String title; // AI-generated, can be edited by user
  final String mood; // e.g., 'joyful', 'anxious', 'weary', 'hurting', 'neutral'
  final List<String> emotionalTags;
  final int length; // 5, 10, 15, or 20 minutes
  final String faithTradition;
  final String storytellingMode; // 'creative' or 'traditional'
  final String translationId; // 'WEB' or 'KJV' - Bible translation used in story
  final bool kidFriendly; // Content appropriate for children
  final List<String> scriptureSources; // Array of verse references
  final String? audioFilePath; // Path to pre-generated audio file
  final String? textFilePath; // Path to story text file
  final DateTime? generatedAt;

  const Parable({
    required this.storyId,
    required this.title,
    required this.mood,
    this.emotionalTags = const [],
    required this.length,
    required this.faithTradition,
    required this.storytellingMode,
    this.translationId = 'WEB', // Default to WEB for backwards compatibility
    required this.kidFriendly,
    this.scriptureSources = const [],
    this.audioFilePath,
    this.textFilePath,
    this.generatedAt,
  });

  /// Create from JSON (for storage/retrieval)
  factory Parable.fromJson(Map<String, dynamic> json) {
    return Parable(
      storyId: json['storyId'] as String,
      title: json['title'] as String,
      mood: json['mood'] as String,
      emotionalTags: (json['emotionalTags'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      length: json['length'] as int,
      faithTradition: json['faithTradition'] as String,
      storytellingMode: json['storytellingMode'] as String,
      translationId: json['translationId'] as String? ?? 'WEB',
      kidFriendly: json['kidFriendly'] as bool? ?? false,
      scriptureSources: (json['scriptureSources'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      audioFilePath: json['audioFilePath'] as String?,
      textFilePath: json['textFilePath'] as String?,
      generatedAt: json['generatedAt'] != null
          ? DateTime.parse(json['generatedAt'] as String)
          : null,
    );
  }

  /// Convert to JSON (for storage)
  Map<String, dynamic> toJson() {
    return {
      'storyId': storyId,
      'title': title,
      'mood': mood,
      'emotionalTags': emotionalTags,
      'length': length,
      'faithTradition': faithTradition,
      'storytellingMode': storytellingMode,
      'translationId': translationId,
      'kidFriendly': kidFriendly,
      'scriptureSources': scriptureSources,
      'audioFilePath': audioFilePath,
      'textFilePath': textFilePath,
      'generatedAt': generatedAt?.toIso8601String(),
    };
  }

  /// Create a copy with modified fields (for title editing, etc.)
  Parable copyWith({
    String? storyId,
    String? title,
    String? mood,
    List<String>? emotionalTags,
    int? length,
    String? faithTradition,
    String? storytellingMode,
    String? translationId,
    bool? kidFriendly,
    List<String>? scriptureSources,
    String? audioFilePath,
    String? textFilePath,
    DateTime? generatedAt,
  }) {
    return Parable(
      storyId: storyId ?? this.storyId,
      title: title ?? this.title,
      mood: mood ?? this.mood,
      emotionalTags: emotionalTags ?? this.emotionalTags,
      length: length ?? this.length,
      faithTradition: faithTradition ?? this.faithTradition,
      storytellingMode: storytellingMode ?? this.storytellingMode,
      translationId: translationId ?? this.translationId,
      kidFriendly: kidFriendly ?? this.kidFriendly,
      scriptureSources: scriptureSources ?? this.scriptureSources,
      audioFilePath: audioFilePath ?? this.audioFilePath,
      textFilePath: textFilePath ?? this.textFilePath,
      generatedAt: generatedAt ?? this.generatedAt,
    );
  }
}

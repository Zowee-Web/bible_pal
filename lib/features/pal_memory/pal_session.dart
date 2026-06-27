import 'package:flutter/foundation.dart' show immutable;

/// A persisted record of a single completed story playback.
///
/// Slice 1 of the PAL Memory Doctrine (see docs/PAL_MEMORY_DOCTRINE.md):
/// captures the snapshot of what the user heard and when, so future
/// memory-layer templates (Level 2 Facts and beyond) can read it without
/// needing to join back to the live parable manifest. Manifest data can
/// change later (re-rendered audio, retagged stories) — the session record
/// reflects what was true at the time of completion.
///
/// Written only on completion (≥90% story-body playback, aligned with
/// SPEC Feature 50.4 — LOCKED). Start events are NOT captured: the
/// doctrine remembers where the user went, not every doorway opened.
@immutable
class PalSession {
  final String storyId;
  final DateTime completedAt;

  /// User's last-detected mood at completion time. Nullable because some
  /// entry points (favorites, history, paths) bypass the mood picker.
  final String? mood;

  final List<String> themeTags;
  final List<String> emotionalTags;

  /// `bibleSourceRef` snapshot — e.g. "Daniel 3:1-30".
  final String? scriptureAnchor;

  /// `bibleStoryKey` snapshot — canonical Bible story identifier used by
  /// future "what came after" routing.
  final String? bibleStoryKey;

  /// Story length bucket name ('short' / 'full' / 'long').
  final String? storyLength;

  /// 'WEB' or 'KJV' at completion time.
  final String languageStyle;

  const PalSession({
    required this.storyId,
    required this.completedAt,
    this.mood,
    this.themeTags = const [],
    this.emotionalTags = const [],
    this.scriptureAnchor,
    this.bibleStoryKey,
    this.storyLength,
    required this.languageStyle,
  });

  Map<String, dynamic> toJson() => {
        'storyId': storyId,
        'completedAt': completedAt.toIso8601String(),
        if (mood != null) 'mood': mood,
        'themeTags': themeTags,
        'emotionalTags': emotionalTags,
        if (scriptureAnchor != null) 'scriptureAnchor': scriptureAnchor,
        if (bibleStoryKey != null) 'bibleStoryKey': bibleStoryKey,
        if (storyLength != null) 'storyLength': storyLength,
        'languageStyle': languageStyle,
      };

  factory PalSession.fromJson(Map<String, dynamic> json) => PalSession(
        storyId: json['storyId'] as String,
        completedAt: DateTime.parse(json['completedAt'] as String),
        mood: json['mood'] as String?,
        themeTags: ((json['themeTags'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
        emotionalTags: ((json['emotionalTags'] as List<dynamic>?) ?? const [])
            .map((e) => e as String)
            .toList(),
        scriptureAnchor: json['scriptureAnchor'] as String?,
        bibleStoryKey: json['bibleStoryKey'] as String?,
        storyLength: json['storyLength'] as String?,
        languageStyle: json['languageStyle'] as String? ?? 'WEB',
      );
}

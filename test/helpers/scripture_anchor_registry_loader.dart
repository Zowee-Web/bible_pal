import 'dart:convert';
import 'package:flutter/services.dart';

/// A single entry in the Scripture Anchor Registry (ADR-022).
///
/// Parsed from `assets/stories/scripture_anchor_registry.json`.
/// The [scriptureAnchorId] is the primary uniqueness key — it identifies
/// one canonical narrative unit and must never be reused across entries.
class ScriptureAnchorEntry {
  final String scriptureAnchorId;
  final String bibleStoryKey;
  final String bibleSourceRef;
  final List<String> moodTags;

  const ScriptureAnchorEntry({
    required this.scriptureAnchorId,
    required this.bibleStoryKey,
    required this.bibleSourceRef,
    required this.moodTags,
  });

  factory ScriptureAnchorEntry.fromJson(Map<String, dynamic> json) =>
      ScriptureAnchorEntry(
        scriptureAnchorId: json['scriptureAnchorId'] as String,
        bibleStoryKey: json['bibleStoryKey'] as String,
        bibleSourceRef: json['bibleSourceRef'] as String,
        moodTags: (json['moodTags'] as List).cast<String>(),
      );
}

/// Loads and provides access to the Scripture Anchor Registry.
///
/// This is a test-only helper. The app runtime has zero dependency on this.
/// The JSON file (`assets/stories/scripture_anchor_registry.json`) is the
/// canonical source of truth.
class ScriptureAnchorRegistry {
  final List<ScriptureAnchorEntry> anchors;

  ScriptureAnchorRegistry._(this.anchors);

  /// Load registry from asset bundle.
  static Future<ScriptureAnchorRegistry> load() async {
    final jsonContent = await rootBundle
        .loadString('assets/stories/scripture_anchor_registry.json');
    final data = jsonDecode(jsonContent) as Map<String, dynamic>;
    final anchorList = data['anchors'] as List<dynamic>;
    final entries = anchorList
        .map((e) =>
            ScriptureAnchorEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    return ScriptureAnchorRegistry._(entries);
  }

  /// All registered scriptureAnchorIds.
  Set<String> get allScriptureAnchorIds =>
      anchors.map((e) => e.scriptureAnchorId).toSet();

  /// All registered bibleStoryKeys.
  Set<String> get allBibleStoryKeys =>
      anchors.map((e) => e.bibleStoryKey).toSet();

  /// All moods that appear in any entry's moodTags.
  Set<String> get coveredMoods =>
      anchors.expand((e) => e.moodTags).toSet();

  /// Lookup: mood → list of entries whose moodTags contain that mood.
  Map<String, List<ScriptureAnchorEntry>> get entriesByMood {
    final map = <String, List<ScriptureAnchorEntry>>{};
    for (final entry in anchors) {
      for (final mood in entry.moodTags) {
        map.putIfAbsent(mood, () => []).add(entry);
      }
    }
    return map;
  }

  /// Lookup entry by bibleStoryKey. Returns null if not found.
  ScriptureAnchorEntry? getByStoryKey(String key) {
    for (final entry in anchors) {
      if (entry.bibleStoryKey == key) return entry;
    }
    return null;
  }
}

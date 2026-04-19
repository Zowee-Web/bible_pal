import 'dart:convert';

import 'package:flutter/services.dart';

import 'pal_line_ref.dart';

/// A single entry mapping a bibleStoryKey to its biblical figure(s) and
/// pre-authored framing lines. Used for Traditional stories only.
class BiblicalFigureEntry {
  final String bibleStoryKey;
  final String primaryFigure;
  final List<String> secondaryFigures;
  final List<PalLineRef> framingLineRefs;

  const BiblicalFigureEntry({
    required this.bibleStoryKey,
    required this.primaryFigure,
    required this.secondaryFigures,
    required this.framingLineRefs,
  });

  /// Text-only access for backward compatibility.
  List<String> get framingLines =>
      framingLineRefs.map((r) => r.text).toList();

  factory BiblicalFigureEntry.fromJson(Map<String, dynamic> json) {
    return BiblicalFigureEntry(
      bibleStoryKey: json['bibleStoryKey'] as String,
      primaryFigure: json['primaryFigure'] as String,
      secondaryFigures: (json['secondaryFigures'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      framingLineRefs: (json['framingLines'] as List<dynamic>).map((e) {
        final obj = e as Map<String, dynamic>;
        return PalLineRef(obj['id'] as String, obj['text'] as String);
      }).toList(),
    );
  }
}

/// Registry that maps bibleStoryKey → biblical figure(s) + framing lines.
///
/// Loaded lazily from the bundled JSON asset. Traditional stories only.
/// Returns null for Creative stories or keys without an entry.
class BiblicalFigureRegistry {
  BiblicalFigureRegistry._();

  static List<BiblicalFigureEntry>? _entries;
  static Map<String, BiblicalFigureEntry>? _byStoryKey;

  /// Load registry from bundled asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_entries != null) return;
    final jsonStr = await rootBundle
        .loadString('assets/stories/biblical_figure_registry.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final list = data['entries'] as List<dynamic>;
    _entries = list
        .map((e) =>
            BiblicalFigureEntry.fromJson(e as Map<String, dynamic>))
        .toList();
    _byStoryKey = {for (final e in _entries!) e.bibleStoryKey: e};
  }

  /// Get a framing line for the given [bibleStoryKey].
  ///
  /// Returns null if the key is null, unknown, or the registry is not loaded.
  /// Selection is deterministic: rotates by day-of-month so the same story
  /// shows the same line within a given day but varies across days.
  static String? getFramingLine(String? bibleStoryKey) {
    return getFramingLineRef(bibleStoryKey)?.text;
  }

  /// Get a framing line ref (id + text) for the given [bibleStoryKey].
  static PalLineRef? getFramingLineRef(String? bibleStoryKey) {
    if (bibleStoryKey == null || _byStoryKey == null) return null;
    final entry = _byStoryKey![bibleStoryKey];
    if (entry == null || entry.framingLineRefs.isEmpty) return null;
    final index = DateTime.now().day % entry.framingLineRefs.length;
    return entry.framingLineRefs[index];
  }

  /// Get the full entry for a [bibleStoryKey]. Returns null if not found.
  static BiblicalFigureEntry? getEntry(String? bibleStoryKey) {
    if (bibleStoryKey == null || _byStoryKey == null) return null;
    return _byStoryKey![bibleStoryKey];
  }

  /// All loaded entries. Returns empty list if not yet loaded.
  static List<BiblicalFigureEntry> get entries => _entries ?? const [];

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _entries = null;
    _byStoryKey = null;
  }
}

import 'dart:convert';

import 'package:flutter/services.dart';

/// Shared PAL closing lines for the typed-input framing overlay.
///
/// These are NOT story-specific — they provide a soft transition after
/// the story-specific framing line, leading the user into the story.
/// Loaded lazily from the bundled JSON asset.
class PalTransitionLines {
  PalTransitionLines._();

  static List<String>? _lines;

  /// Load transition lines from bundled asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_lines != null) return;
    final jsonStr =
        await rootBundle.loadString('assets/pal/pal_transition_lines.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    _lines =
        (data['lines'] as List<dynamic>).map((e) => e as String).toList();
  }

  /// Get a transition line using deterministic rotation.
  ///
  /// Combines [bibleStoryKey] hash with the current day so that:
  /// - Different stories get different transitions
  /// - The same story on a different day rotates to a new line
  /// - No storage needed
  static String? getLine(String? bibleStoryKey) {
    if (_lines == null || _lines!.isEmpty || bibleStoryKey == null) return null;
    final seed = bibleStoryKey.hashCode + DateTime.now().day;
    return _lines![seed.abs() % _lines!.length];
  }

  /// All loaded lines. Returns empty list if not yet loaded.
  static List<String> get lines => _lines ?? const [];

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _lines = null;
  }
}

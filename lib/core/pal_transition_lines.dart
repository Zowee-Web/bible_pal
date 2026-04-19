import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'pal_line_ref.dart';
import 'pal_line_rotator.dart';

/// Shared PAL closing lines for the typed-input framing overlay.
///
/// These are NOT story-specific — they provide a soft transition after
/// the story-specific framing line, leading the user into the story.
/// Loaded lazily from the bundled JSON asset.
/// Each line carries a unique ID for audio asset lookup (Feature 5.1a).
class PalTransitionLines {
  PalTransitionLines._();

  static List<PalLineRef>? _lines;
  static final PalLineRotator _rotator = PalLineRotator();

  /// Load transition lines from bundled asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_lines != null) return;
    final jsonStr =
        await rootBundle.loadString('assets/pal/pal_transition_lines.json');
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    _lines = (data['lines'] as List<dynamic>).map((e) {
      final obj = e as Map<String, dynamic>;
      return PalLineRef(obj['id'] as String, obj['text'] as String);
    }).toList();
    final prefs = await SharedPreferences.getInstance();
    _rotator.enablePersistence(prefs, 'transition');
  }

  /// Get a transition line text.
  ///
  /// [bibleStoryKey] is accepted for API compatibility but all stories
  /// share the same generic transition pool with a single rotation.
  static String? getLine(String? bibleStoryKey) {
    return getLineRef(bibleStoryKey)?.text;
  }

  /// Get a transition line ref (id + text).
  ///
  /// Uses persistent recency tracking with a shared `default` key —
  /// transition lines are generic, not story-specific.
  static PalLineRef? getLineRef(String? bibleStoryKey) {
    if (_lines == null || _lines!.isEmpty || bibleStoryKey == null) return null;
    return _lines![_rotator.pick('default', _lines!.length)];
  }

  /// All loaded lines (text only). Returns empty list if not yet loaded.
  static List<String> get lines =>
      _lines?.map((r) => r.text).toList() ?? const [];

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _lines = null;
    _rotator.clearPersistedHistory();
  }
}

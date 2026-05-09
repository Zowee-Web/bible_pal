// ignore_for_file: deprecated_member_use_from_same_package
//
// PalOpeningTone is intentionally @Deprecated as of PR #13 (commit ceb0d3a)
// when Feature 5.1 tone-biased reflection was retired. The enum is kept as a
// stub so this orphaned file still compiles. The deprecation warnings are
// expected and suppressed at file scope so CI's `flutter analyze` stays clean
// on Flutter 3.27.1 (CI version). Newer Flutter versions don't emit the warning.

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/pal/opening/pal_opening_lines.dart';
import 'pal_line_ref.dart';
import 'pal_line_rotator.dart';

/// Tone-biased first reflective sentence service (Feature 5.1).
///
/// Provides pre-written first-sentence variants keyed by (mood × openingTone).
/// Parallel to [PalReflectionLines] — used only when a session opening tone is
/// active. Falls back to null so the caller can fall through to the normal path.
///
/// Content lives in assets/pal/pal_tone_biased_reflection_lines.json.
/// No AI generation. No runtime string modification.
/// Each line carries a unique ID for audio asset lookup (Feature 5.1a).
class PalToneBiasedReflectionLines {
  PalToneBiasedReflectionLines._();

  // mood → tone-name → List<PalLineRef>
  static Map<String, Map<String, List<PalLineRef>>>? _data;
  static final PalLineRotator _rotator = PalLineRotator();

  /// Load asset. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_data != null) return;
    final jsonStr = await rootBundle
        .loadString('assets/pal/pal_tone_biased_reflection_lines.json');
    final root = jsonDecode(jsonStr) as Map<String, dynamic>;
    final moodsRaw = root['moods'] as Map<String, dynamic>;

    _data = moodsRaw.map((mood, toneMap) {
      final tones = (toneMap as Map<String, dynamic>).map((tone, variants) {
        return MapEntry(
          tone,
          (variants as List<dynamic>).map((e) {
            final obj = e as Map<String, dynamic>;
            return PalLineRef(obj['id'] as String, obj['text'] as String);
          }).toList(),
        );
      });
      return MapEntry(mood, tones);
    });
    final prefs = await SharedPreferences.getInstance();
    _rotator.enablePersistence(prefs, 'tone_biased');
  }

  /// Return a tone-biased first reflective sentence for the given [mood]
  /// and [tone], or `null` if the combination is not found.
  static String? getLine(String? mood, PalOpeningTone tone) {
    return getLineRef(mood, tone)?.text;
  }

  /// Return a line ref (id + text) for the given [mood] and [tone].
  ///
  /// Uses persistent recency tracking keyed by mood+tone so each
  /// combination cycles through all variants before repeating,
  /// even across app restarts.
  static PalLineRef? getLineRef(String? mood, PalOpeningTone tone) {
    if (mood == null || _data == null) return null;
    final toneMap = _data![mood];
    if (toneMap == null) return null;
    final toneName = tone.name; // enum name matches JSON key
    final variants = toneMap[toneName];
    if (variants == null || variants.isEmpty) return null;
    final key = '${mood}_$toneName';
    return variants[_rotator.pick(key, variants.length)];
  }

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _data = null;
    _rotator.clearPersistedHistory();
  }

  /// All loaded mood keys. Returns empty list if not yet loaded.
  static List<String> get moods => _data?.keys.toList() ?? const [];
}

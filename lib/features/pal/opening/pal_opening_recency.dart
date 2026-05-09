import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Persistent recency rotation for the PAL opening greeting library.
///
/// The cold-open opening line is picked from the time bucket's 3 lines,
/// avoiding the line picked most recently from that same bucket. State
/// persists across app launches via [SharedPreferences] keyed by
/// `pal_opening_recency.<bucketKey>`.
///
/// Used by `pickOpeningLineForHour` in `pal_opening_lines.dart`. Caller is
/// responsible for awaiting [ensureInitialized] before the first
/// [pickIndex] if persistence across app restarts is desired — without
/// it, [pickIndex] still works (returns a fresh random pick) but the
/// recency state from the previous session is ignored.
class PalOpeningRecency {
  PalOpeningRecency._();

  static const String _prefKeyPrefix = 'pal_opening_recency.';

  static SharedPreferences? _prefs;
  static final Random _random = Random();

  /// Load the persistent recency state. Idempotent — safe to call from
  /// multiple sites; only the first call hits SharedPreferences.
  static Future<void> ensureInitialized() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  /// Pick an index in `[0, lineCount)` for the given bucket, avoiding the
  /// most-recently-picked index when possible. Persists the choice for
  /// the next call.
  ///
  /// If `lineCount <= 1`, returns 0 (only one line — no rotation needed).
  /// If recency state isn't loaded yet (caller didn't await
  /// [ensureInitialized]), behaves as a plain random pick.
  static int pickIndex(String bucketKey, int lineCount) {
    if (lineCount <= 0) return 0;
    if (lineCount == 1) return 0;

    final lastPicked = _prefs?.getInt('$_prefKeyPrefix$bucketKey');

    int picked;
    if (lastPicked == null || lastPicked < 0 || lastPicked >= lineCount) {
      picked = _random.nextInt(lineCount);
    } else {
      // Pick from the (lineCount - 1) candidates that aren't lastPicked,
      // then map back to the original index space.
      final candidate = _random.nextInt(lineCount - 1);
      picked = candidate >= lastPicked ? candidate + 1 : candidate;
    }

    _prefs?.setInt('$_prefKeyPrefix$bucketKey', picked);
    return picked;
  }

  /// Test-only: force the in-memory cached SharedPreferences. Lets tests
  /// inject `SharedPreferences.setMockInitialValues` state without
  /// re-awaiting [ensureInitialized].
  static void debugSetPrefsForTesting(SharedPreferences prefs) {
    _prefs = prefs;
  }

  /// Test-only: clear the in-memory cached SharedPreferences so the next
  /// [ensureInitialized] reloads from scratch.
  static void debugResetForTesting() {
    _prefs = null;
  }
}

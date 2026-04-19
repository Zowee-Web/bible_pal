import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Recency tracker for PAL line pools with optional persistent history.
///
/// Prevents the same line from being selected twice until every line in the
/// pool has been used. Each key (mood, storyKey, mood+tone) maintains its
/// own independent history.
///
/// When persistence is enabled via [enablePersistence], history survives
/// app restarts. Persistence is failure-safe — read/write errors never
/// affect line selection.
class PalLineRotator {
  final Map<String, List<int>> _used = {};
  final Random _random;

  /// Keys that have already been restored from persistence this session.
  final Set<String> _restoredKeys = {};

  SharedPreferences? _prefs;
  String? _familyPrefix;

  PalLineRotator([Random? random]) : _random = random ?? Random();

  /// Enable persistent history backed by SharedPreferences.
  ///
  /// [familyPrefix] scopes storage keys (e.g. `'reflection'` produces
  /// keys like `pal_line_history_reflection_joyful`). Restoration is lazy
  /// — each context key is loaded from disk on first [pick] call.
  void enablePersistence(SharedPreferences prefs, String familyPrefix) {
    _prefs = prefs;
    _familyPrefix = familyPrefix;
  }

  /// SharedPreferences key for a given context key.
  String _storageKey(String contextKey) =>
      'pal_line_history_${_familyPrefix}_$contextKey';

  /// Lazily restore persisted history for [key] on first access.
  /// Filters out indices >= [poolSize] to handle pool-size changes.
  void _restoreKey(String key, int poolSize) {
    if (_prefs == null || _restoredKeys.contains(key)) return;
    _restoredKeys.add(key);
    try {
      final json = _prefs!.getString(_storageKey(key));
      if (json == null) return;
      final stored = (jsonDecode(json) as List).cast<int>();
      // Filter out indices that are no longer valid (pool shrank).
      _used[key] = stored.where((i) => i >= 0 && i < poolSize).toList();
    } catch (_) {
      // Corrupt or unreadable data — start fresh for this key.
    }
  }

  /// Persist the current history for [key]. Failure-safe.
  void _persistKey(String key) {
    if (_prefs == null) return;
    try {
      _prefs!
          .setString(_storageKey(key), jsonEncode(_used[key]))
          .catchError((_) => false);
    } catch (_) {
      // Guard against unexpected synchronous errors.
    }
  }

  /// Pick an index from `[0, poolSize)` that hasn't been used recently
  /// for [key]. Resets history for [key] when all indices have been used.
  int pick(String key, int poolSize) {
    assert(poolSize > 0);
    _restoreKey(key, poolSize);

    final used = _used[key];
    var candidates = <int>[];
    for (var i = 0; i < poolSize; i++) {
      if (used == null || !used.contains(i)) candidates.add(i);
    }
    if (candidates.isEmpty) {
      // Keep the last-used index to avoid back-to-back repeats across resets.
      final lastUsed = (used != null && used.isNotEmpty) ? used.last : -1;
      _used[key] = [];
      candidates = List.generate(poolSize, (i) => i);
      if (poolSize > 1) {
        candidates.remove(lastUsed);
      }
    }
    final chosen = candidates[_random.nextInt(candidates.length)];
    _used.putIfAbsent(key, () => []).add(chosen);
    _persistKey(key);
    return chosen;
  }

  /// Clear in-memory history only. Persisted history is untouched.
  void reset() {
    _used.clear();
    _restoredKeys.clear();
  }

  /// Clear both in-memory and persisted history for all tracked keys.
  ///
  /// Only removes SharedPreferences keys owned by this rotator's
  /// [_familyPrefix]. Use [reset] for memory-only cleanup.
  void clearPersistedHistory() {
    if (_prefs != null) {
      for (final key in _used.keys) {
        try {
          _prefs!.remove(_storageKey(key));
        } catch (_) {}
      }
    }
    _used.clear();
    _restoredKeys.clear();
  }
}

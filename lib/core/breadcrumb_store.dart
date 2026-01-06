/// Breadcrumb Persistence Store
///
/// Persists breadcrumbs to disk when DIAGNOSTICS_ENABLED=true.
/// Uses SharedPreferences with throttled writes to minimize I/O.
///
/// Features:
/// - Throttled writes (5 second debounce)
/// - Loads persisted breadcrumbs on startup
/// - Reuses AppLogger sanitization (already sanitized data)
/// - Safe-fail: never crashes, silently handles errors
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'diagnostics_config.dart';

/// Storage key for persisted breadcrumbs
const String _kBreadcrumbsKey = 'diagnostics.breadcrumbs';

/// Maximum breadcrumbs to persist (matches AppLogger ring buffer)
const int _kMaxPersistedBreadcrumbs = 50;

/// Throttle duration for writes
const Duration _kWriteThrottle = Duration(seconds: 5);

/// Persists breadcrumbs to disk with throttled writes.
///
/// Only active when [kDiagnosticsEnabled] is true.
/// All operations are safe-fail (never throw).
class BreadcrumbStore {
  BreadcrumbStore._();

  static final BreadcrumbStore _instance = BreadcrumbStore._();

  /// Singleton instance
  static BreadcrumbStore get instance => _instance;

  /// Pending breadcrumbs to write
  final List<Map<String, Object?>> _pendingWrites = [];

  /// Timer for throttled writes
  Timer? _writeTimer;

  /// Whether a write is currently in progress
  bool _writeInProgress = false;

  /// SharedPreferences instance (cached after first access)
  SharedPreferences? _prefs;

  /// Queue a breadcrumb for persistence.
  ///
  /// Writes are throttled to minimize disk I/O.
  /// Does nothing if diagnostics disabled.
  void queueBreadcrumb(Map<String, Object?> breadcrumb) {
    if (!kDiagnosticsEnabled) return;

    try {
      // Add to pending queue
      _pendingWrites.add(Map<String, Object?>.from(breadcrumb));

      // Trim if over limit
      while (_pendingWrites.length > _kMaxPersistedBreadcrumbs) {
        _pendingWrites.removeAt(0);
      }

      // Schedule throttled write
      _scheduleWrite();
    } catch (e) {
      // SAFE FAIL: Never crash
      _debugLog('Failed to queue breadcrumb: $e');
    }
  }

  /// Force an immediate write (e.g., on app backgrounding).
  ///
  /// Bypasses throttle. Safe to call multiple times.
  Future<void> flushNow() async {
    if (!kDiagnosticsEnabled) return;
    if (_pendingWrites.isEmpty) return;

    _writeTimer?.cancel();
    _writeTimer = null;

    await _writeToDisk();
  }

  /// Load persisted breadcrumbs from disk.
  ///
  /// Returns empty list if diagnostics disabled or no data.
  Future<List<Map<String, Object?>>> loadPersistedBreadcrumbs() async {
    if (!kDiagnosticsEnabled) return [];

    try {
      final prefs = await _getPrefs();
      final jsonString = prefs.getString(_kBreadcrumbsKey);

      if (jsonString == null || jsonString.isEmpty) {
        return [];
      }

      final decoded = jsonDecode(jsonString);
      if (decoded is! List) {
        return [];
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map((m) => Map<String, Object?>.from(m))
          .toList();
    } catch (e) {
      // SAFE FAIL: Return empty on any error
      _debugLog('Failed to load persisted breadcrumbs: $e');
      return [];
    }
  }

  /// Clear all persisted breadcrumbs.
  Future<void> clear() async {
    if (!kDiagnosticsEnabled) return;

    try {
      _pendingWrites.clear();
      _writeTimer?.cancel();
      _writeTimer = null;

      final prefs = await _getPrefs();
      await prefs.remove(_kBreadcrumbsKey);
    } catch (e) {
      // SAFE FAIL
      _debugLog('Failed to clear persisted breadcrumbs: $e');
    }
  }

  void _scheduleWrite() {
    // Already scheduled
    if (_writeTimer?.isActive ?? false) return;

    _writeTimer = Timer(_kWriteThrottle, () {
      _writeToDisk();
    });
  }

  Future<void> _writeToDisk() async {
    if (_writeInProgress) return;
    if (_pendingWrites.isEmpty) return;

    _writeInProgress = true;

    try {
      final prefs = await _getPrefs();

      // Load existing breadcrumbs
      final existing = await loadPersistedBreadcrumbs();

      // Merge: existing + pending, trimmed to max
      final merged = [...existing, ..._pendingWrites];
      while (merged.length > _kMaxPersistedBreadcrumbs) {
        merged.removeAt(0);
      }

      // Write to disk
      final jsonString = jsonEncode(merged);
      await prefs.setString(_kBreadcrumbsKey, jsonString);

      // Clear pending after successful write
      _pendingWrites.clear();

      _debugLog('Persisted ${merged.length} breadcrumbs');
    } catch (e) {
      // SAFE FAIL: Log but don't crash
      _debugLog('Failed to write breadcrumbs to disk: $e');
    } finally {
      _writeInProgress = false;
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[BreadcrumbStore] $message');
    }
  }

  /// Reset instance state (for testing)
  @visibleForTesting
  void reset() {
    _pendingWrites.clear();
    _writeTimer?.cancel();
    _writeTimer = null;
    _writeInProgress = false;
    _prefs = null;
  }

  /// Get pending writes count (for testing)
  @visibleForTesting
  int get pendingWriteCount => _pendingWrites.length;
}

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Queue a breadcrumb for disk persistence (convenience function)
void queueBreadcrumbForPersistence(Map<String, Object?> breadcrumb) {
  BreadcrumbStore.instance.queueBreadcrumb(breadcrumb);
}

/// Flush pending breadcrumbs to disk immediately (convenience function)
Future<void> flushBreadcrumbsNow() async {
  await BreadcrumbStore.instance.flushNow();
}

/// Load persisted breadcrumbs from disk (convenience function)
Future<List<Map<String, Object?>>> loadPersistedBreadcrumbs() async {
  return BreadcrumbStore.instance.loadPersistedBreadcrumbs();
}

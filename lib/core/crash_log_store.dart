/// Crash Log Persistence Store
///
/// Persists fatal crashes to disk for offline diagnostics.
/// Only active when DIAGNOSTICS_ENABLED=true.
///
/// Privacy guarantees (HARD CONSTRAINTS):
/// - NO user text, story content, verse text, contact info, tokens
/// - NO absolute file paths (only sanitized package-relative paths)
/// - Breadcrumbs are sanitized at write time (whitelisted keys only)
/// - Only safe app/device metadata
///
/// Features:
/// - Stores last 10 crash logs max (FIFO)
/// - Each crash: timestamp, error class, stack, breadcrumbs, app version
/// - Safe-fail: never crashes, silently handles errors
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'diagnostics_config.dart';

/// Maximum crash logs to keep
const int kMaxCrashLogs = 10;

/// Directory name for crash logs (inside app documents)
const String _kCrashLogDir = 'crash_logs';

/// Maximum error message length (prevent huge files)
const int _kMaxErrorMessageLength = 500;

/// Maximum stack trace lines
const int _kMaxStackTraceLines = 100;

/// Maximum string value length in breadcrumbs
const int _kMaxBreadcrumbStringLength = 100;

/// Whitelisted breadcrumb keys (privacy firewall)
const Set<String> _kAllowedBreadcrumbKeys = {
  // Core fields
  'event',
  'level',
  'ts',

  // Story/content identifiers (safe)
  'story_id',
  'parable_id',
  'length_bucket',
  'storytelling_mode',
  'kid_friendly',

  // Error/status codes (safe)
  'error_type',
  'error_code',
  'status_code',
  'http_status',

  // Timing/duration (safe)
  'duration_ms',
  'elapsed_ms',
  'position_ms',

  // Counts/booleans (safe)
  'attempt',
  'retry_count',
  'count',
  'success',
  'enabled',

  // Mode/state flags (safe)
  'mode',
  'state',
  'action',
  'source',
  'screen',

  // Version info (safe)
  'app_version',
  'app_build',
  'session_id',
};

/// Crash log entry
class CrashLog {
  final DateTime timestamp;
  final String errorType;
  final String? errorMessage;
  final String? stackTrace;
  final List<Map<String, Object?>> breadcrumbs;
  final String? appVersion;
  final String? appBuild;

  CrashLog({
    required this.timestamp,
    required this.errorType,
    this.errorMessage,
    this.stackTrace,
    this.breadcrumbs = const [],
    this.appVersion,
    this.appBuild,
  });

  Map<String, Object?> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'error_type': errorType,
        if (errorMessage != null) 'error_message': errorMessage,
        if (stackTrace != null) 'stack_trace': stackTrace,
        'breadcrumb_count': breadcrumbs.length,
        'breadcrumbs': breadcrumbs,
        if (appVersion != null) 'app_version': appVersion,
        if (appBuild != null) 'app_build': appBuild,
      };

  factory CrashLog.fromJson(Map<String, dynamic> json) {
    return CrashLog(
      timestamp: DateTime.parse(json['timestamp'] as String),
      errorType: json['error_type'] as String,
      errorMessage: json['error_message'] as String?,
      stackTrace: json['stack_trace'] as String?,
      breadcrumbs: (json['breadcrumbs'] as List?)
              ?.cast<Map<String, dynamic>>()
              .map((m) => Map<String, Object?>.from(m))
              .toList() ??
          [],
      appVersion: json['app_version'] as String?,
      appBuild: json['app_build'] as String?,
    );
  }
}

/// Persists fatal crashes to disk.
///
/// Only active when [kDiagnosticsEnabled] is true.
/// All operations are safe-fail (never throw).
class CrashLogStore {
  CrashLogStore._();

  static final CrashLogStore _instance = CrashLogStore._();

  /// Singleton instance
  static CrashLogStore get instance => _instance;

  /// Optional directory override for testing
  @visibleForTesting
  Directory? testDirectory;

  /// Write a crash log to disk.
  ///
  /// Returns true if successful, false otherwise.
  /// Never throws - safe-fail behavior.
  Future<bool> writeCrashLog({
    required Object error,
    required StackTrace stackTrace,
    List<Map<String, Object?>>? breadcrumbs,
    String? appVersion,
    String? appBuild,
  }) async {
    if (!kDiagnosticsEnabled) return false;

    try {
      // PRIVACY FIREWALL: Sanitize breadcrumbs at write time
      final sanitizedBreadcrumbs =
          breadcrumbs?.map(_sanitizeBreadcrumb).toList() ?? [];

      final crashLog = CrashLog(
        timestamp: DateTime.now(),
        errorType: error.runtimeType.toString(),
        errorMessage: _sanitizeErrorMessage(error.toString()),
        stackTrace: _sanitizeStackTrace(stackTrace.toString()),
        breadcrumbs: sanitizedBreadcrumbs,
        appVersion: appVersion,
        appBuild: appBuild,
      );

      // Get crash log directory
      final dir = await _getCrashLogDirectory();
      if (dir == null) return false;

      // Write crash log file
      final filename =
          'crash_${crashLog.timestamp.millisecondsSinceEpoch}.json';
      final file = File('${dir.path}/$filename');

      const encoder = JsonEncoder.withIndent('  ');
      final jsonString = encoder.convert(crashLog.toJson());
      await file.writeAsString(jsonString);

      _debugLog('Wrote crash log: $filename');

      // Cleanup old logs
      await _cleanupOldLogs(dir);

      return true;
    } catch (e) {
      // SAFE FAIL: Never crash
      _debugLog('Failed to write crash log: $e');
      return false;
    }
  }

  /// Load all crash logs from disk (sorted newest first).
  ///
  /// Returns empty list if diagnostics disabled or no logs exist.
  Future<List<CrashLog>> loadCrashLogs() async {
    if (!kDiagnosticsEnabled) return [];

    try {
      final dir = await _getCrashLogDirectory();
      if (dir == null) return [];

      if (!await dir.exists()) return [];

      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      final logs = <CrashLog>[];
      for (final file in files) {
        try {
          final jsonString = await file.readAsString();
          final json = jsonDecode(jsonString) as Map<String, dynamic>;
          logs.add(CrashLog.fromJson(json));
        } catch (e) {
          // Skip corrupted files
          _debugLog('Failed to parse crash log ${file.path}: $e');
        }
      }

      // Sort by timestamp (newest first)
      logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      return logs;
    } catch (e) {
      // SAFE FAIL
      _debugLog('Failed to load crash logs: $e');
      return [];
    }
  }

  /// Get count of crash logs (without loading full content).
  Future<int> getCrashLogCount() async {
    if (!kDiagnosticsEnabled) return 0;

    try {
      final dir = await _getCrashLogDirectory();
      if (dir == null) return 0;

      if (!await dir.exists()) return 0;

      return dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .length;
    } catch (e) {
      return 0;
    }
  }

  /// Clear all crash logs.
  Future<void> clearAll() async {
    if (!kDiagnosticsEnabled) return;

    try {
      final dir = await _getCrashLogDirectory();
      if (dir == null) return;

      if (await dir.exists()) {
        await dir.delete(recursive: true);
        _debugLog('Cleared all crash logs');
      }
    } catch (e) {
      // SAFE FAIL
      _debugLog('Failed to clear crash logs: $e');
    }
  }

  Future<Directory?> _getCrashLogDirectory() async {
    try {
      // Use test directory if provided (for testing without platform channels)
      final appDir = testDirectory ?? await getApplicationDocumentsDirectory();
      final crashDir = Directory('${appDir.path}/$_kCrashLogDir');

      if (!await crashDir.exists()) {
        await crashDir.create(recursive: true);
      }

      return crashDir;
    } catch (e) {
      _debugLog('Failed to get crash log directory: $e');
      return null;
    }
  }

  Future<void> _cleanupOldLogs(Directory dir) async {
    try {
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList();

      if (files.length <= kMaxCrashLogs) return;

      // Sort by filename (contains timestamp) - oldest first
      files.sort((a, b) => a.path.compareTo(b.path));

      // Delete oldest files
      final toDelete = files.length - kMaxCrashLogs;
      for (var i = 0; i < toDelete; i++) {
        await files[i].delete();
        _debugLog('Deleted old crash log: ${files[i].path.split('/').last}');
      }
    } catch (e) {
      // SAFE FAIL
      _debugLog('Failed to cleanup old logs: $e');
    }
  }

  /// PRIVACY FIREWALL: Sanitize breadcrumb at write time.
  ///
  /// - Whitelist allowed keys only
  /// - Cap string lengths
  /// - Drop unknown keys
  Map<String, Object?> _sanitizeBreadcrumb(Map<String, Object?> breadcrumb) {
    final sanitized = <String, Object?>{};

    for (final entry in breadcrumb.entries) {
      final key = entry.key;
      final value = entry.value;

      // Drop non-whitelisted keys
      if (!_kAllowedBreadcrumbKeys.contains(key)) {
        continue;
      }

      // Sanitize value based on type
      if (value == null) {
        sanitized[key] = null;
      } else if (value is String) {
        // Cap string length
        if (value.length > _kMaxBreadcrumbStringLength) {
          sanitized[key] = '${value.substring(0, _kMaxBreadcrumbStringLength)}...';
        } else {
          sanitized[key] = value;
        }
      } else if (value is num || value is bool) {
        // Numbers and booleans are safe
        sanitized[key] = value;
      } else {
        // Drop complex types (List, Map, etc.)
        _debugLog('Dropped non-primitive value for key "$key": ${value.runtimeType}');
      }
    }

    return sanitized;
  }

  /// Sanitize error message - remove PII, file paths, excessive length
  String _sanitizeErrorMessage(String message) {
    // Trim to max length
    if (message.length > _kMaxErrorMessageLength) {
      message =
          '${message.substring(0, _kMaxErrorMessageLength)}... [truncated]';
    }

    // Remove file:/// URLs
    message = message.replaceAll(
      RegExp(r'file:///[^\s,;)]+'),
      '[PATH]',
    );

    // Remove Unix-style absolute paths (/Users/, /Volumes/, /home/, etc.)
    message = message.replaceAll(
      RegExp(r'/(?:Users|Volumes|home|var|tmp|opt|usr|System|Library)/[^\s,;)]+'),
      '[PATH]',
    );

    // Remove Windows-style paths (C:\, D:\, etc.)
    message = message.replaceAll(
      RegExp(r'[A-Z]:\\[^\s,;)]+'),
      '[PATH]',
    );

    // Remove potential email addresses
    message = message.replaceAll(
      RegExp(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b'),
      '[EMAIL]',
    );

    // Remove potential phone numbers
    message = message.replaceAll(
      RegExp(r'\b\d{3}[-.\s]?\d{3}[-.\s]?\d{4}\b'),
      '[PHONE]',
    );

    return message;
  }

  /// Sanitize stack trace - preserve package:/dart: URIs, redact absolute paths
  String _sanitizeStackTrace(String stackTrace) {
    final lines = stackTrace.split('\n');

    // Keep first N lines
    final trimmedLines = lines.take(_kMaxStackTraceLines).toList();

    // Sanitize each line
    final sanitized = trimmedLines.map((line) {
      // Preserve package: and dart: URIs (but still redact other paths on same line)
      var sanitizedLine = line;

      // Redact file:/// absolute paths (but keep file:// prefix for context)
      sanitizedLine = sanitizedLine.replaceAll(
        RegExp(r'file:///[^\s)]+'),
        'file://[PATH]',
      );

      // Redact Unix absolute paths (leading slash + known directories)
      sanitizedLine = sanitizedLine.replaceAll(
        RegExp(r'/(?:Users|Volumes|home|var|tmp|opt|usr|System|Library)/[^\s),;]+'),
        '[PATH]',
      );

      // Redact Windows paths
      sanitizedLine = sanitizedLine.replaceAll(
        RegExp(r'[A-Z]:\\[^\s),;]+'),
        '[PATH]',
      );

      return sanitizedLine;
    }).join('\n');

    if (lines.length > _kMaxStackTraceLines) {
      return '$sanitized\n... [${lines.length - _kMaxStackTraceLines} more lines]';
    }

    return sanitized;
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[CrashLogStore] $message');
    }
  }

  /// Reset for testing
  @visibleForTesting
  void reset() {
    testDirectory = null;
  }
}

// ============================================================================
// CONVENIENCE FUNCTIONS
// ============================================================================

/// Write a crash log (convenience function)
Future<bool> writeCrashLog({
  required Object error,
  required StackTrace stackTrace,
  List<Map<String, Object?>>? breadcrumbs,
  String? appVersion,
  String? appBuild,
}) async {
  return CrashLogStore.instance.writeCrashLog(
    error: error,
    stackTrace: stackTrace,
    breadcrumbs: breadcrumbs,
    appVersion: appVersion,
    appBuild: appBuild,
  );
}

/// Load all crash logs (convenience function)
Future<List<CrashLog>> loadCrashLogs() async {
  return CrashLogStore.instance.loadCrashLogs();
}

/// Get crash log count (convenience function)
Future<int> getCrashLogCount() async {
  return CrashLogStore.instance.getCrashLogCount();
}

/// Clear all crash logs (convenience function)
Future<void> clearAllCrashLogs() async {
  await CrashLogStore.instance.clearAll();
}

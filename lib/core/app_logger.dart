/// Bible PAL Structured Logging Service
///
/// Privacy-safe, structured logging for diagnostics and crash breadcrumbs.
/// See docs/INVARIANTS.md for logging invariants.
///
/// HARD INVARIANTS:
/// 1. PRIVACY: Never log raw user-entered text, names, emails, phones, or PII
/// 2. STRUCTURED: All logs are key/value JSON (not free-form paragraphs)
/// 3. LOW NOISE: Only log decision points, lifecycle transitions, errors
/// 4. SAFE FAIL: Logging never crashes the app - failures are no-ops
/// 5. BUILD SAFE: Tests fail if disallowed fields are logged
library;

import 'dart:convert';
import 'dart:collection';
import 'dart:math';
import 'package:flutter/foundation.dart';

import 'breadcrumb_store.dart';
import 'crash_reporter.dart';

/// Log levels for structured events
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// Result of logging attempt
enum LogResult {
  success,
  blocked,
  truncated,
  error,
}

/// Breadcrumb entry for crash diagnostics
class Breadcrumb {
  final String event;
  final Map<String, Object?> data;
  final LogLevel level;
  final DateTime timestamp;

  const Breadcrumb({
    required this.event,
    required this.data,
    required this.level,
    required this.timestamp,
  });

  Map<String, Object?> toJson() => {
        'event': event,
        'level': level.name,
        'ts': timestamp.toUtc().toIso8601String(),
        ...data,
      };
}

/// Central structured logging service for Bible PAL
///
/// Features:
/// - Privacy-safe: blocks PII and raw user text
/// - Structured: JSON output only
/// - Breadcrumb ring buffer for crash diagnostics
/// - Safe-fail: never throws, logs errors internally
class AppLogger {
  AppLogger._();

  static final AppLogger _instance = AppLogger._();

  /// Singleton instance
  static AppLogger get instance => _instance;

  /// Breadcrumb ring buffer (last N events)
  static const int _maxBreadcrumbs = 50;
  final Queue<Breadcrumb> _breadcrumbs = Queue<Breadcrumb>();

  /// Maximum payload size in bytes (2KB)
  static const int _maxPayloadBytes = 2048;

  /// App version/build info (set once at startup)
  String? _appVersion;
  String? _appBuild;

  /// Session ID - random hex string generated once per app run
  /// Used for correlating events without PII
  late final String _sessionId = _generateSessionId();

  /// Last known filters snapshot (safe fields only)
  /// Updated when filters_applied event is logged
  Map<String, Object?> _lastFilters = {};

  static String _generateSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(8, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Keys that are BLOCKED from logging (contain user text/PII)
  /// All keys are lowercase for case-insensitive matching
  static const Set<String> _blockedKeys = {
    // User-entered text
    'usertext',
    'user_text',
    'message',
    'prompt',
    'transcript',
    'recognized_text',
    'speech_result',
    'voice_text',
    'input',
    'text',
    'content',
    'query',
    'response',
    'reply',
    'answer',
    // PII fields
    'email',
    'phone',
    'name',
    'firstname',
    'lastname',
    'first_name',
    'last_name',
    'address',
    'password',
    'token',
    'secret',
    'apikey',
    'api_key',
  };

  /// Regex patterns for detecting PII in values
  static final RegExp _emailPattern = RegExp(
    r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
    caseSensitive: false,
  );

  static final RegExp _phonePattern = RegExp(
    r'(?:\+?1[-.\s]?)?\(?[0-9]{3}\)?[-.\s]?[0-9]{3}[-.\s]?[0-9]{4}',
  );

  /// Set app version info (call once at startup)
  void setAppInfo({required String version, required String build}) {
    _appVersion = version;
    _appBuild = build;
  }

  /// Get session ID for this app run
  String get sessionId => _sessionId;

  /// Get app version
  String? get appVersion => _appVersion;

  /// Get app build
  String? get appBuild => _appBuild;

  /// Get last known filters snapshot (safe fields only)
  Map<String, Object?> get lastFilters => Map.unmodifiable(_lastFilters);

  /// Log a structured event
  ///
  /// Returns [LogResult] indicating outcome.
  /// Never throws - failures are silently handled.
  LogResult logEvent(
    String event,
    Map<String, Object?> data, {
    LogLevel level = LogLevel.info,
  }) {
    try {
      // Validate event name
      if (event.isEmpty) {
        return LogResult.blocked;
      }

      // Sanitize data
      final sanitizeResult = _sanitizeData(data);
      if (sanitizeResult.blocked) {
        // Log that we blocked something (without the blocked data)
        _emitLog(
          event: 'logging_blocked',
          level: LogLevel.warn,
          data: {
            'original_event': event,
            'reason': 'blocked_keys_detected',
            'blocked_keys': sanitizeResult.blockedKeys.toList(),
          },
        );
        return LogResult.blocked;
      }

      // Track filters_applied events for support bundle
      if (event == 'filters_applied') {
        _lastFilters = Map<String, Object?>.from(sanitizeResult.data);
      }

      // Build final payload
      final payload = _buildPayload(event, sanitizeResult.data, level);

      // Check payload size
      final jsonString = jsonEncode(payload);
      final truncated = jsonString.length > _maxPayloadBytes;

      if (truncated) {
        // Truncate by removing optional fields until under limit
        final truncatedPayload = _truncatePayload(payload);
        _emitLog(
          event: event,
          level: level,
          data: truncatedPayload,
          truncated: true,
        );
        _addBreadcrumb(event, truncatedPayload, level);
        return LogResult.truncated;
      }

      // Emit the log
      _emitLog(event: event, level: level, data: payload);
      _addBreadcrumb(event, sanitizeResult.data, level);

      return LogResult.success;
    } catch (e) {
      // SAFE FAIL: Never crash on logging errors
      try {
        debugPrint('[AppLogger] ERROR: Failed to log event "$event": $e');
      } catch (_) {
        // Even debugPrint failed - silently ignore
      }
      return LogResult.error;
    }
  }

  /// Log an error with breadcrumbs attached
  LogResult logError(
    String errorType,
    String location, {
    String? storyId,
    String? errorMessage,
    Map<String, Object?>? additionalData,
  }) {
    final sanitizedMessage =
        errorMessage != null ? _sanitizeErrorMessage(errorMessage) : null;
    final data = <String, Object?>{
      'error_type': errorType,
      'location': location,
      if (storyId != null) 'story_id': storyId,
      if (sanitizedMessage != null) 'error_msg': sanitizedMessage,
      'breadcrumbs_attached': true,
      'breadcrumb_count': _breadcrumbs.length,
      ...?additionalData,
    };

    // Report to crash reporter
    try {
      crashReporter.reportError(
        errorType: errorType,
        location: location,
        sanitizedMessage: sanitizedMessage,
        additionalData: additionalData,
      );
    } catch (_) {
      // SAFE FAIL
    }

    return logEvent('error_caught', data, level: LogLevel.error);
  }

  /// Get recent breadcrumbs for crash reporting
  List<Map<String, Object?>> getRecentBreadcrumbs() {
    try {
      return _breadcrumbs.map((b) => b.toJson()).toList();
    } catch (e) {
      return [];
    }
  }

  /// Clear all breadcrumbs
  void clearBreadcrumbs() {
    _breadcrumbs.clear();
  }

  /// Clear last filters snapshot (for testing)
  @visibleForTesting
  void clearLastFilters() {
    _lastFilters = {};
  }

  /// Sanitize data by removing blocked keys and PII values
  _SanitizeResult _sanitizeData(Map<String, Object?> data) {
    final sanitized = <String, Object?>{};
    final blockedKeys = <String>{};

    for (final entry in data.entries) {
      final key = entry.key.toLowerCase();
      final value = entry.value;

      // Check if key is blocked
      if (_blockedKeys.contains(key)) {
        blockedKeys.add(entry.key);
        continue;
      }

      // Check if value contains PII patterns
      if (value is String && _containsPII(value)) {
        blockedKeys.add(entry.key);
        continue;
      }

      // Recursively sanitize nested maps
      if (value is Map<String, Object?>) {
        final nested = _sanitizeData(value);
        if (nested.blocked) {
          blockedKeys.addAll(nested.blockedKeys);
        }
        sanitized[entry.key] = nested.data;
      } else if (value is List) {
        // Sanitize list items
        sanitized[entry.key] = _sanitizeList(value);
      } else {
        sanitized[entry.key] = value;
      }
    }

    return _SanitizeResult(
      data: sanitized,
      blocked: blockedKeys.isNotEmpty,
      blockedKeys: blockedKeys,
    );
  }

  List<Object?> _sanitizeList(List<Object?> list) {
    return list.map((item) {
      if (item is String && _containsPII(item)) {
        return '[REDACTED]';
      } else if (item is Map<String, Object?>) {
        return _sanitizeData(item).data;
      }
      return item;
    }).toList();
  }

  bool _containsPII(String value) {
    if (_emailPattern.hasMatch(value)) return true;
    if (_phonePattern.hasMatch(value)) return true;
    return false;
  }

  String _sanitizeErrorMessage(String message) {
    // Remove potential PII from error messages
    var sanitized = message;
    sanitized = sanitized.replaceAll(_emailPattern, '[EMAIL]');
    sanitized = sanitized.replaceAll(_phonePattern, '[PHONE]');
    // Truncate to reasonable length
    if (sanitized.length > 200) {
      sanitized = '${sanitized.substring(0, 200)}...';
    }
    return sanitized;
  }

  Map<String, Object?> _buildPayload(
    String event,
    Map<String, Object?> data,
    LogLevel level,
  ) {
    return {
      'event': event,
      'level': level.name,
      'ts': DateTime.now().toUtc().toIso8601String(),
      if (_appVersion != null) 'app_version': _appVersion,
      if (_appBuild != null) 'app_build': _appBuild,
      ...data,
    };
  }

  Map<String, Object?> _truncatePayload(Map<String, Object?> payload) {
    // Create a copy and remove less critical fields until under limit
    final result = Map<String, Object?>.from(payload);

    // Priority order of fields to keep (remove from end first)
    final optionalFields = ['tags', 'filters', 'counts', 'metadata'];

    for (final field in optionalFields.reversed) {
      if (result.containsKey(field)) {
        result.remove(field);
        final json = jsonEncode(result);
        if (json.length <= _maxPayloadBytes) {
          result['_truncated'] = true;
          return result;
        }
      }
    }

    result['_truncated'] = true;
    return result;
  }

  void _emitLog({
    required String event,
    required LogLevel level,
    required Map<String, Object?> data,
    bool truncated = false,
  }) {
    try {
      final payload = {
        'event': event,
        'level': level.name,
        'ts': DateTime.now().toUtc().toIso8601String(),
        if (_appVersion != null) 'app_version': _appVersion,
        if (_appBuild != null) 'app_build': _appBuild,
        if (truncated) '_truncated': true,
        ...data,
      };

      final jsonLine = jsonEncode(payload);

      // In debug mode, pretty print for readability
      if (kDebugMode) {
        final prefix = switch (level) {
          LogLevel.debug => '🔍',
          LogLevel.info => '📝',
          LogLevel.warn => '⚠️',
          LogLevel.error => '🚨',
        };
        debugPrint('$prefix $jsonLine');
      } else {
        // In release mode, emit compact JSON for log aggregation
        // ignore: avoid_print
        print(jsonLine);
      }
    } catch (e) {
      // SAFE FAIL: Never crash
      try {
        debugPrint('[AppLogger] Failed to emit log: $e');
      } catch (_) {}
    }
  }

  void _addBreadcrumb(String event, Map<String, Object?> data, LogLevel level) {
    try {
      final timestamp = DateTime.now();
      final breadcrumb = Breadcrumb(
        event: event,
        data: Map.unmodifiable(data),
        level: level,
        timestamp: timestamp,
      );

      _breadcrumbs.add(breadcrumb);

      // Trim to max size
      while (_breadcrumbs.length > _maxBreadcrumbs) {
        _breadcrumbs.removeFirst();
      }

      // Queue for disk persistence (if diagnostics enabled)
      queueBreadcrumbForPersistence(breadcrumb.toJson());

      // Send to crash reporter
      crashReporter.recordBreadcrumb(
        event: event,
        data: data,
        level: level.name,
        timestamp: timestamp,
      );
    } catch (e) {
      // SAFE FAIL: Never crash
    }
  }
}

/// Result of data sanitization
class _SanitizeResult {
  final Map<String, Object?> data;
  final bool blocked;
  final Set<String> blockedKeys;

  const _SanitizeResult({
    required this.data,
    required this.blocked,
    required this.blockedKeys,
  });
}

// ============================================================================
// CONVENIENCE FUNCTIONS (Top-level for easy import)
// ============================================================================

/// Log a structured event (convenience function)
LogResult logEvent(
  String event,
  Map<String, Object?> data, {
  LogLevel level = LogLevel.info,
}) {
  return AppLogger.instance.logEvent(event, data, level: level);
}

/// Log an error with breadcrumbs (convenience function)
LogResult logError(
  String errorType,
  String location, {
  String? storyId,
  String? errorMessage,
  Map<String, Object?>? additionalData,
}) {
  return AppLogger.instance.logError(
    errorType,
    location,
    storyId: storyId,
    errorMessage: errorMessage,
    additionalData: additionalData,
  );
}

/// Get recent breadcrumbs for debugging (convenience function)
List<Map<String, Object?>> getRecentBreadcrumbs() {
  return AppLogger.instance.getRecentBreadcrumbs();
}

/// Set app version info (call once at startup)
void setLoggerAppInfo({required String version, required String build}) {
  AppLogger.instance.setAppInfo(version: version, build: build);
}

/// Get session ID for this app run (convenience function)
String getSessionId() {
  return AppLogger.instance.sessionId;
}

/// Get last known filters snapshot (convenience function)
Map<String, Object?> getLastFilters() {
  return AppLogger.instance.lastFilters;
}

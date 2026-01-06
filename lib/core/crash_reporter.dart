/// Crash Reporter Interface
///
/// Abstract interface for future crash reporting integration.
/// Currently uses NoopCrashReporter (logs but doesn't send anywhere).
///
/// When a real crash reporter is added (e.g., Crashlytics, Sentry):
/// 1. Implement CrashReporter interface
/// 2. Swap NoopCrashReporter for real implementation
/// 3. Breadcrumbs/errors automatically flow to crash reporter
///
/// See ADR-005 in docs/DECISIONS.md for rationale.
library;

import 'package:flutter/foundation.dart';

/// Abstract interface for crash reporting services.
///
/// Implementations must be safe-fail (never throw).
abstract class CrashReporter {
  /// Record a breadcrumb for crash context.
  ///
  /// Called automatically by AppLogger for each logged event.
  /// Data is already sanitized (no PII).
  void recordBreadcrumb({
    required String event,
    required Map<String, Object?> data,
    required String level,
    required DateTime timestamp,
  });

  /// Report a non-fatal error.
  ///
  /// Called automatically by AppLogger.logError().
  /// Error details are already sanitized.
  void reportError({
    required String errorType,
    required String location,
    String? sanitizedMessage,
    Map<String, Object?>? additionalData,
  });

  /// Report a fatal crash.
  ///
  /// Called for unhandled exceptions.
  /// Stack trace and error info should be attached.
  void reportFatalCrash({
    required Object error,
    required StackTrace stackTrace,
    List<Map<String, Object?>>? breadcrumbs,
  });

  /// Set user identifier for crash reports.
  ///
  /// PRIVACY: Must be anonymous ID only, never PII.
  void setUserId(String anonymousId);

  /// Set custom key-value for crash context.
  ///
  /// PRIVACY: Values must be pre-sanitized.
  void setCustomKey(String key, Object value);
}

/// No-op crash reporter implementation.
///
/// Logs to debug console but doesn't send data anywhere.
/// Used until a real crash reporter SDK is integrated.
class NoopCrashReporter implements CrashReporter {
  NoopCrashReporter._();

  static final NoopCrashReporter _instance = NoopCrashReporter._();

  /// Singleton instance
  static NoopCrashReporter get instance => _instance;

  @override
  void recordBreadcrumb({
    required String event,
    required Map<String, Object?> data,
    required String level,
    required DateTime timestamp,
  }) {
    // No-op: Would send to crash reporter
    _debugLog('Breadcrumb: $event ($level)');
  }

  @override
  void reportError({
    required String errorType,
    required String location,
    String? sanitizedMessage,
    Map<String, Object?>? additionalData,
  }) {
    // No-op: Would send to crash reporter
    _debugLog('Error: $errorType at $location');
  }

  @override
  void reportFatalCrash({
    required Object error,
    required StackTrace stackTrace,
    List<Map<String, Object?>>? breadcrumbs,
  }) {
    // No-op: Would send to crash reporter
    _debugLog('FATAL: $error');
    _debugLog('Stack: $stackTrace');
    if (breadcrumbs != null) {
      _debugLog('Breadcrumbs: ${breadcrumbs.length} attached');
    }
  }

  @override
  void setUserId(String anonymousId) {
    // No-op: Would set user ID in crash reporter
    _debugLog('User ID set: $anonymousId');
  }

  @override
  void setCustomKey(String key, Object value) {
    // No-op: Would set custom key in crash reporter
    _debugLog('Custom key: $key = $value');
  }

  void _debugLog(String message) {
    if (kDebugMode) {
      debugPrint('[CrashReporter:Noop] $message');
    }
  }
}

// ============================================================================
// CRASH REPORTER SINGLETON
// ============================================================================

/// The active crash reporter instance.
///
/// Defaults to NoopCrashReporter. Replace with real implementation
/// when integrating Crashlytics/Sentry.
CrashReporter _crashReporter = NoopCrashReporter.instance;

/// Get the current crash reporter instance.
CrashReporter get crashReporter => _crashReporter;

/// Set a custom crash reporter implementation.
///
/// Call during app initialization to replace NoopCrashReporter.
void setCrashReporter(CrashReporter reporter) {
  _crashReporter = reporter;
}

/// Reset to noop reporter (for testing)
@visibleForTesting
void resetCrashReporter() {
  _crashReporter = NoopCrashReporter.instance;
}

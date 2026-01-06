/// Diagnostics Lifecycle Observer
///
/// Flushes pending breadcrumbs to disk when app backgrounds.
/// Only active when DIAGNOSTICS_ENABLED=true.
library;

import 'package:flutter/widgets.dart';

import 'breadcrumb_store.dart';
import 'diagnostics_config.dart';

/// Observer that flushes breadcrumbs on app lifecycle events.
///
/// Only performs work when [kDiagnosticsEnabled] is true.
/// Safe-fail: never throws, all operations wrapped in try/catch.
class DiagnosticsLifecycleObserver extends WidgetsBindingObserver {
  DiagnosticsLifecycleObserver._();

  static DiagnosticsLifecycleObserver? _instance;

  /// Whether the observer is currently registered
  static bool _isRegistered = false;

  /// Initialize and register the observer (if diagnostics enabled)
  ///
  /// Safe to call multiple times - only registers once.
  /// Does nothing if diagnostics disabled.
  static void initialize() {
    if (!kDiagnosticsEnabled) return;
    if (_isRegistered) return;

    try {
      _instance ??= DiagnosticsLifecycleObserver._();
      WidgetsBinding.instance.addObserver(_instance!);
      _isRegistered = true;
    } catch (e) {
      // SAFE FAIL: Never crash on initialization
    }
  }

  /// Unregister the observer (for testing)
  static void dispose() {
    if (!_isRegistered || _instance == null) return;

    try {
      WidgetsBinding.instance.removeObserver(_instance!);
      _isRegistered = false;
    } catch (e) {
      // SAFE FAIL
    }
  }

  /// Check if observer is registered (for testing)
  static bool get isRegistered => _isRegistered;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Flush on paused (backgrounding) or inactive
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _flushBreadcrumbs();
    }
  }

  void _flushBreadcrumbs() {
    try {
      // Fire and forget - don't await in lifecycle callback
      flushBreadcrumbsNow();
    } catch (e) {
      // SAFE FAIL: Never crash on flush
    }
  }
}

/// Initialize diagnostics lifecycle observer
///
/// Call once at app startup after WidgetsFlutterBinding.ensureInitialized().
/// Does nothing if diagnostics disabled.
void initializeDiagnosticsLifecycle() {
  DiagnosticsLifecycleObserver.initialize();
}

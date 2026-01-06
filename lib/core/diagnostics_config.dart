/// Diagnostics Configuration
///
/// Runtime toggle for optional diagnostic features.
/// Enable via: flutter run --dart-define=DIAGNOSTICS_ENABLED=true
///
/// When enabled:
/// - Breadcrumbs persist to disk (survive app restart)
/// - Hidden diagnostics screen accessible
/// - Export diagnostics to clipboard available
///
/// When disabled (default):
/// - Breadcrumbs are in-memory only
/// - Diagnostics screen not accessible
/// - No disk I/O for logging
library;

/// Whether diagnostics features are enabled.
///
/// Set at compile time via --dart-define=DIAGNOSTICS_ENABLED=true
/// Default: false (disabled)
const bool kDiagnosticsEnabled = bool.fromEnvironment(
  'DIAGNOSTICS_ENABLED',
  defaultValue: false,
);

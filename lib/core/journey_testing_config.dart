/// Journey Testing Configuration
///
/// Runtime toggle for beta-only Journey testing tools (cadence override,
/// clear-cooldown / seed-session, telemetry tagging). Mirrors the
/// DIAGNOSTICS_ENABLED pattern in `diagnostics_config.dart`.
///
/// Enable via: flutter run --dart-define=JOURNEY_TESTING_ENABLED=true
/// (typically alongside --dart-define=DIAGNOSTICS_ENABLED=true, since the
/// Journey Testing panel lives inside the diagnostics screen).
///
/// When enabled:
/// - The Journey Testing panel appears in the diagnostics screen.
/// - A beta cadence override may collapse the 3-day continuation cooldown
///   (adult lane only) so the cascade can be re-tested in minutes.
/// - Panel-driven journey events are tagged `synthetic_session: true` so
///   they are excluded from baseline continuation metrics.
///
/// When disabled (default, and in production): the flag is const false,
/// so every gated block is tree-shaken out of the build entirely. No
/// hidden runtime surface ships to end users.
library;

/// Whether beta Journey testing tools are enabled.
///
/// Set at compile time via --dart-define=JOURNEY_TESTING_ENABLED=true
/// Default: false (disabled — compiled out).
const bool kJourneyTestingEnabled = bool.fromEnvironment(
  'JOURNEY_TESTING_ENABLED',
  defaultValue: false,
);

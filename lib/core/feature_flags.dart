/// Feature Flags
///
/// Compile-time toggles for optional features.
/// These flags control v1 scope decisions documented in SPEC.md.
///
/// Usage: flutter run --dart-define=FLAG_NAME=true
library;

/// V1 Scope: Faith tradition selector is disabled.
///
/// When false (default, v1):
/// - Tradition selector skipped in onboarding
/// - Settings option hidden
/// - All users default to 'christian' tradition
/// - No content branching by denomination
///
/// When true (future v2+):
/// - Tradition selector shown in onboarding
/// - Settings option visible
/// - Content can branch by tradition
///
/// See SPEC.md: "V1 Scope: Christian (General)"
const bool kEnableDenominationSelector = bool.fromEnvironment(
  'ENABLE_DENOMINATION_SELECTOR',
  defaultValue: false,
);

/// Default faith tradition value for v1.
///
/// Applied automatically when denomination selector is disabled.
/// This value is internal-only; users don't see or choose it.
const String kDefaultFaithTradition = 'christian';

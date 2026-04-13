/// Bible PAL Analytics Events
///
/// Privacy-safe, typed analytics event emitters.
/// Uses [AppLogger] as the emission backend — no external vendors.
///
/// HARD INVARIANTS:
/// 1. ALLOWLISTED PAYLOAD ONLY: Only pre-approved fields are emitted.
/// 2. NO PII: No user text, names, emails, or identifiers.
/// 3. FIRE-AND-FORGET: Analytics never crashes the app or blocks UI.
/// 4. SINGLE EMISSION: Each user action emits exactly one event.
/// 5. NO MINUTE-BASED FIELDS: Use length_bucket (short/full/long) only.
library;

import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/models/parable.dart';

/// Allowlisted payload keys for analytics events.
///
/// Only these keys may appear in analytics event payloads.
/// Adding new keys requires updating this set AND the INVARIANTS.md doc.
const Set<String> analyticsAllowedKeys = {
  // Story core (v1)
  'story_id',
  'mood',
  'mode',
  'length_bucket',
  'kid_friendly',
  'translation_id',
  'language_style',
  'voice_key',
  // PALs Paths (Feature 50) — reserved for path-launched + completion
  // events. `source` indicates launch origin on `story_completed`.
  'path_type',
  'path_id',
  'completion_pct',
  'badge_id',
  'badge_category',
  'source',
};

/// Typed analytics event emitters for Bible PAL.
///
/// All methods are static, fire-and-forget, and safe-fail.
/// They build an allowlisted payload from model objects and delegate
/// to [AppLogger.logEvent] for emission.
class AnalyticsEvents {
  AnalyticsEvents._(); // No instantiation

  /// Log a `story_favorited` event when a user adds a parable to favorites.
  ///
  /// Extracts only allowlisted fields from [parable].
  /// Returns the [LogResult] for testability; callers may ignore it.
  static LogResult logStoryFavorited(Parable parable) {
    final payload = _buildPayload(parable);
    return logEvent('story_favorited', payload);
  }

  /// Log a `story_completed` event when story-body playback reaches
  /// ≥ 90% (SPEC Feature 50.4 — LOCKED: story body only, reflection
  /// ignored). Emits once per story per completion (the caller is
  /// responsible for idempotency via [CompletedStoriesStore]).
  ///
  /// [source] indicates launch origin: `mood`, `path`, `favorite`,
  /// `history`, or `search`. Fire-and-forget: result ignored by caller.
  static LogResult logStoryCompleted(
    Parable parable, {
    required String source,
  }) {
    final payload = _buildPayload(parable)..['source'] = source;
    return logEvent('story_completed', payload);
  }

  /// Log a `path_opened` event when the user opens a real path
  /// instance or a path detail screen (SPEC Feature 50.10). Per the
  /// Phase 2 "strict path_opened" rule, this MUST fire only when a
  /// meaningful path context opens — not on every pill tap.
  ///
  /// Payload contains only `path_type` and `path_id`. The raw search
  /// query (if any) is NEVER included — search privacy invariant.
  static LogResult logPathOpened({
    required String pathType,
    required String pathId,
  }) {
    return logEvent('path_opened', {
      'path_type': pathType,
      'path_id': pathId,
    });
  }

  /// Log a `character_path_selected` event when the user taps a
  /// character-path instance (SPEC Feature 50.10). `path_type` is
  /// always `"characters"` for this event; `path_id` is the
  /// `primaryCharacterId` (NEVER `"jesus"` — see SPEC 50.8).
  static LogResult logCharacterPathSelected({
    required String characterId,
    required String languageStyle,
  }) {
    return logEvent('character_path_selected', {
      'path_type': 'characters',
      'path_id': characterId,
      'language_style': languageStyle,
    });
  }

  /// Log a `path_completed` event when a path transitions from <1.0 to
  /// 1.0 completion (SPEC Feature 50.10, Phase 3). Fires at most once
  /// per transition — the player hook computes the
  /// `willCompletePath` predicate BEFORE marking the current story
  /// complete, so subsequent replays of an already-complete path do
  /// not re-fire the event.
  ///
  /// Strict scoping (Phase 3): fires only when the active launch
  /// context belongs to the path that just transitioned. Paths that
  /// happen to reach 100% via mood/favorite/history flows do NOT
  /// trigger this event — that's deferred to a later phase if you
  /// want cross-flow completion detection.
  static LogResult logPathCompleted({
    required String pathType,
    required String pathId,
    required double completionPct,
  }) {
    return logEvent('path_completed', {
      'path_type': pathType,
      'path_id': pathId,
      'completion_pct': completionPct,
    });
  }

  /// Build an allowlisted payload from a [Parable].
  ///
  /// Only keys in [analyticsAllowedKeys] are included.
  static Map<String, Object?> _buildPayload(Parable parable) {
    return {
      'story_id': parable.storyId,
      'mood': parable.mood,
      'mode': parable.storytellingMode,
      'length_bucket': parable.lengthBucket.name,
      'kid_friendly': parable.kidFriendly,
      'translation_id': parable.translationId,
      'language_style': parable.languageStyle,
      'voice_key': parable.narratorVoiceKey,
    };
  }
}

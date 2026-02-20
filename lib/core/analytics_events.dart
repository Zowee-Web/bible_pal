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
  'story_id',
  'mood',
  'mode',
  'length_bucket',
  'kid_friendly',
  'translation_id',
  'language_style',
  'voice_key',
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

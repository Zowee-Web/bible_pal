import 'package:shared_preferences/shared_preferences.dart';

import 'pal_line_ref.dart';
import 'pal_line_rotator.dart';

// Kid-specific PAL transition language (SPEC Feature 51.7).
//
// The bridge PAL speaks/shows AFTER acknowledging the feeling (the Presence
// reflection in kid_pal_reflection_lines.dart) and BEFORE the story begins.
// This is the "gently lead the child to hope through story" half of the locked
// Kids decision: PAL invites the child into the story rather than explaining
// the feeling.
//
// The adult transition pool (pal_transition_lines.dart) is abstract and
// "clever" ("There's something in Scripture that understands that") which a
// 4-7 year old does not parse and which can read as PAL explaining them.
// These kid lines are concrete invitations and wonder instead.
//
// Two mixed buckets (Adam, 2026-06-18), rotated together so the child never
// hears the same kind of line twice in a row:
//   - Gentle invitation: "Let's hear a story together."
//   - Wonder:            "Want to hear something wonderful?"
//
// Short, warm, ASCII. Each line carries an ID for future audio lookup
// (assets/pal/audio/{voiceKey}/KID_TRANS_*.mp3); audio is a separate approved
// step and playback no-ops gracefully until clips exist.

/// The locked kid transition library (invitation + wonder, mixed).
const List<PalLineRef> kidTransitionLines = [
  // Gentle invitation
  PalLineRef('KID_TRANS_01', "Let's hear a story together."),
  PalLineRef('KID_TRANS_02', "I have a story for you."),
  PalLineRef('KID_TRANS_03', "I have a gentle story for you."),
  PalLineRef('KID_TRANS_04', "Let's listen to something together."),
  // Wonder
  PalLineRef('KID_TRANS_05', "Want to hear something wonderful?"),
  PalLineRef('KID_TRANS_06', "Let's step into a story together."),
  PalLineRef('KID_TRANS_07', "I know someone brave."),
  PalLineRef('KID_TRANS_08', "Let's hear something beautiful together."),
  PalLineRef('KID_TRANS_09', "Let's see what happened."),
];

/// Kid-mode transition line selector (SPEC Feature 51.7).
///
/// Generic (not story-specific), mirroring the adult [PalTransitionLines]
/// shared pool. Keeps its own recency history (family `kid_transition`).
class KidPalTransitionLines {
  KidPalTransitionLines._();

  static final PalLineRotator _rotator = PalLineRotator();
  static bool _persistenceEnabled = false;

  /// Enable persistent recency history. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_persistenceEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    _rotator.enablePersistence(prefs, 'kid_transition');
    _persistenceEnabled = true;
  }

  /// Get a kid transition line ref (id + text). Never null — the pool is
  /// non-empty and not keyed by story.
  static PalLineRef getLineRef() =>
      kidTransitionLines[_rotator.pick('default', kidTransitionLines.length)];

  /// Get a kid transition line text.
  static String getLine() => getLineRef().text;

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _rotator.clearPersistedHistory();
    _persistenceEnabled = false;
  }
}

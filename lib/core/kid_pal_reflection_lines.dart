import 'package:shared_preferences/shared_preferences.dart';

import 'pal_line_ref.dart';
import 'pal_line_rotator.dart';

// Kid-specific PAL response language (SPEC Feature 51.7).
//
// These are the lines PAL speaks/shows as its FIRST response after a child
// shares a feeling through the peach orb (the hero voice interaction). They
// are the "acknowledge" half of the locked Kids decision:
//
//     Acknowledge the feeling first, then tell a fitting story.
//
// The story itself is the path to hope (selected by the unchanged engine and
// introduced by the transition + framing lines). These reflection lines do
// NOT explain, fix, or dismiss the feeling. They name it and stay with the
// child for one beat before the story begins.
//
// LOCKED rules (do not weaken; see SPEC 51.7):
//   1. Acknowledge the feeling first.
//   2. Stay WITH the child in the feeling. Every line carries a presence
//      signal ("with you", "here", "together", "beside you", "not alone",
//      "by yourself", "side by side") so a child is never left alone with a
//      scary feeling.
//   3. Lead to hope through the STORY, not through explanation. PAL is here
//      to stay with the child, not to explain everything.
//   4. NEVER say (enforced by kid_pal_reflection_lines_test.dart):
//        - "Everything will be okay" / any "okay"/"fine" reassurance
//        - "<person> will not die" / "won't die"
//        - "Do not be scared" / "Don't be scared"
//        - "God did this for a reason" / "for a reason"
//      No false promises, no commands to stop feeling, no theodicy.
//
// Short and literal, ages 4-7. Each line carries a unique ID for future audio
// asset lookup (assets/pal/audio/{voiceKey}/{lineId}.mp3); audio is generated
// in a separate approved step. Until then these surface as displayed text in
// Kids mode and the audio playback no-ops gracefully if a clip is missing.
//
// Selection is mood-scoped with persistent recency rotation, mirroring the
// adult [PalReflectionLines]. The voice path passes the raw detected mood, so
// all eight MoodService moods are covered (a missing mood would fall back to
// adult lines, which must never happen in Kids mode).

/// The locked kid reflection library (the Presence bucket). 3-4 lines per mood.
///
/// Diction note (Adam, 2026-06-18): lead with CONCRETE presence ("I'm right
/// here with you", "I'll stay close") over the abstract "you are not alone" —
/// a young child grasps someone being WITH them better than the idea of
/// not-aloneness. "not alone" / "by yourself" are kept but used sparingly
/// (<= ~25% of lines; the test enforces a cap). No permission ("it's okay to
/// be scared"), no naming-the-feeling-back as a lesson, no fixing.
const Map<String, List<PalLineRef>> kidReflectionLines = {
  'joyful': [
    PalLineRef('KID_REFL_JOYFUL_01',
        "I love hearing that. I'm so happy to be here with you."),
    PalLineRef('KID_REFL_JOYFUL_02',
        "That's so good. Let's enjoy this happy feeling together."),
    PalLineRef('KID_REFL_JOYFUL_03',
        "Yay! I'm right here to share this happy moment with you."),
    PalLineRef('KID_REFL_JOYFUL_04',
        "That makes me smile. I'm here with you."),
  ],
  'grateful': [
    PalLineRef('KID_REFL_GRATEFUL_01',
        "A thankful heart is so beautiful. I'm here with you."),
    PalLineRef('KID_REFL_GRATEFUL_02',
        "That's so kind and good. I'm right here with you."),
    PalLineRef('KID_REFL_GRATEFUL_03',
        "I love that you feel thankful. We can enjoy it together."),
    PalLineRef('KID_REFL_GRATEFUL_04',
        "Thank you for sharing that with me. I'm right here with you."),
  ],
  'weary': [
    PalLineRef('KID_REFL_WEARY_01',
        "I hear you. I'll stay right here with you."),
    PalLineRef('KID_REFL_WEARY_02',
        "Let's slow down and rest together."),
    PalLineRef('KID_REFL_WEARY_03',
        "I'm here. We can take this slow, side by side."),
    PalLineRef('KID_REFL_WEARY_04',
        "I'm here. We can rest for a minute."),
  ],
  'anxious': [
    PalLineRef('KID_REFL_ANXIOUS_01',
        "That does sound scary. I'm right here with you."),
    PalLineRef('KID_REFL_ANXIOUS_02',
        "I'm right here with you. I'll stay close."),
    PalLineRef('KID_REFL_ANXIOUS_03',
        "We can listen together. I'm right here."),
    PalLineRef('KID_REFL_ANXIOUS_04',
        "I'll stay right beside you. You're not alone right now."),
  ],
  'hurting': [
    PalLineRef('KID_REFL_HURTING_01',
        "That sounds like it really hurts. I'm right here with you."),
    PalLineRef('KID_REFL_HURTING_02',
        "I'm so glad you told me. We can sit here together."),
    PalLineRef('KID_REFL_HURTING_03',
        "I'm here with you. I'll stay close."),
    PalLineRef('KID_REFL_HURTING_04',
        "I'm right here. You're not by yourself."),
  ],
  'brave_courage': [
    PalLineRef('KID_REFL_BRAVE_COURAGE_01',
        "That took real bravery. I'm right here with you."),
    PalLineRef('KID_REFL_BRAVE_COURAGE_02',
        "That was brave. I'm right here beside you."),
    PalLineRef('KID_REFL_BRAVE_COURAGE_03',
        "We can keep going together. I'm right here."),
  ],
  'calm_peaceful': [
    PalLineRef('KID_REFL_CALM_PEACEFUL_01',
        "That sounds so peaceful. I'm glad to be here with you."),
    PalLineRef('KID_REFL_CALM_PEACEFUL_02',
        "What a calm feeling. Let's rest in it together."),
    PalLineRef('KID_REFL_CALM_PEACEFUL_03',
        "I love this quiet moment here with you."),
  ],
  'encouraging': [
    PalLineRef('KID_REFL_ENCOURAGING_01',
        "I see something good in you. I'm right here."),
    PalLineRef('KID_REFL_ENCOURAGING_02',
        "Let's keep going together. I'm right here."),
    PalLineRef('KID_REFL_ENCOURAGING_03',
        "You have a good heart. I'm right beside you."),
  ],
};

/// Kid-mode reflection line selector (SPEC Feature 51.7).
///
/// Mirrors [PalReflectionLines] but draws from the kid library above and
/// keeps its own recency history (persistence family `kid_reflection`) so kid
/// and adult rotation never interfere. Used by the Kids-mode voice flow only.
class KidPalReflectionLines {
  KidPalReflectionLines._();

  static final PalLineRotator _rotator = PalLineRotator();
  static bool _persistenceEnabled = false;

  /// Enable persistent recency history. Safe to call multiple times.
  static Future<void> ensureLoaded() async {
    if (_persistenceEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    _rotator.enablePersistence(prefs, 'kid_reflection');
    _persistenceEnabled = true;
  }

  /// Get a kid reflection line ref (id + text) for [mood].
  ///
  /// Returns null only if [mood] is null or has no kid lines. In Kids mode
  /// every detectable mood is covered, so callers can treat null as "use the
  /// adult fallback" without it ever firing in practice.
  static PalLineRef? getLineRef(String? mood) {
    if (mood == null) return null;
    final lines = kidReflectionLines[mood];
    if (lines == null || lines.isEmpty) return null;
    return lines[_rotator.pick(mood, lines.length)];
  }

  /// Get a kid reflection line text for [mood], or null if none.
  static String? getLine(String? mood) => getLineRef(mood)?.text;

  /// All covered mood keys.
  static List<String> get moods => kidReflectionLines.keys.toList();

  /// Reset internal state (for testing only).
  static void resetForTesting() {
    _rotator.clearPersistedHistory();
    _persistenceEnabled = false;
  }
}

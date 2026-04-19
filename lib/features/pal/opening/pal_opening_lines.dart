import 'dart:math';

/// Tone tag for a PAL opening line (Feature 2.0).
///
/// Used as a session-only soft modifier on the first reflective sentence
/// (Feature 5.1). Never persisted to storage.
enum PalOpeningTone {
  gentle,
  encouraging,
  calm,
  weary,
  warm,
}

/// A single entry in the 60-line PAL pre-greeting opening library.
class PalOpeningLine {
  final String id;
  final String text;
  final PalOpeningTone tone;

  const PalOpeningLine({
    required this.id,
    required this.text,
    required this.tone,
  });
}

/// The locked 60-line opening library (Feature 2.0).
///
/// 12 lines per tone bucket. Content is locked — wording changes require
/// a SPEC update. Selected uniformly at random; no time-awareness.
/// Each line carries a unique ID for audio asset lookup (Feature 2.0a).
const List<PalOpeningLine> palOpeningLines = [
  // ── gentle (1–12) ──────────────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_GENTLE_01',
    text: "I\u2019m here. What\u2019s today been like for you?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_02',
    text: "You don't have to filter anything… how's your day been?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_03',
    text: "What\u2019s been sitting with you today?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_04',
    text: "I've got time—what's been going on for you?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_05',
    text: "What's been on your heart lately… even a little?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_06',
    text: "How are you really doing right now?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_07',
    text: "What's been quietly on your mind today?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_08',
    text: "You can just say it as it is… how's today been?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_09',
    text: "What's been lingering with you today?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_10',
    text: "What kind of day has it been for you?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_11',
    text: "What's been with you today… start wherever you want.",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    id: 'OPENING_GENTLE_12',
    text: "How have things been feeling on your side today?",
    tone: PalOpeningTone.gentle,
  ),

  // ── encouraging (13–24) ────────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_01',
    text: "You don't have to carry it alone… what's been going on?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_02',
    text: "What\u2019s been a little heavy for you today?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_03',
    text: "If something's been weighing on you, you can say it here.",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_04',
    text: "What's been taking more out of you than you expected?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_05',
    text: "What\u2019s been hard to shake today?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_06',
    text: "If today's been a lot, I'm here—what's going on?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_07',
    text: "What's been asking a lot from you lately?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_08',
    text: "What\u2019s been sitting a little heavier than usual?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_09',
    text: "What's been pressing on you, even if it's small?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_10',
    text: "You can let it out here… what's been going on?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_11',
    text: "What's been harder than you thought it would be today?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    id: 'OPENING_ENCOURAGING_12',
    text: "What\u2019s been pulling at you today?",
    tone: PalOpeningTone.encouraging,
  ),

  // ── calm (25–36) ───────────────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_CALM_01',
    text: "Take a breath with me. What's been going on?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_02',
    text: "No rush at all… what's been on your heart?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_03',
    text: "We can just slow this down… how are you feeling?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_04',
    text: "You can take your time here. What's been today?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_05',
    text: "Let's just pause for a second… what's been going on?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_06',
    text: "You don't have to hurry through it… what's been on your mind?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_07',
    text: "We can sit here a moment. What's been with you?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_08',
    text: "Whenever you're ready… what's been on your heart?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_09',
    text: "Let's just take this one piece at a time… what's going on?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_10',
    text: "Just ease into it. What's been today for you?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_11',
    text: "We can keep this simple… how are you feeling right now?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    id: 'OPENING_CALM_12',
    text: "Take your time… what's been staying with you today?",
    tone: PalOpeningTone.calm,
  ),

  // ── weary (37–48) ──────────────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_WEARY_01',
    text: "You sound like you might be tired. What's been going on?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_02',
    text: "Has today been a long one for you?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_03',
    text: "What's been wearing on you today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_04',
    text: "You don\u2019t have to push through it here\u2026 what\u2019s been hard?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_05',
    text: "What's been taking more energy than you had today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_06',
    text: "What's been a little too much lately?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_07',
    text: "What's been draining you today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_08',
    text: "Has anything just felt… heavy today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_09',
    text: "What's been a lot for you today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_10',
    text: "What's been hard to carry today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_11',
    text: "How are you holding up through all of it?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    id: 'OPENING_WEARY_12',
    text: "What's been quietly exhausting for you today?",
    tone: PalOpeningTone.weary,
  ),

  // ── warm (49–60) ───────────────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_WARM_01',
    text: "Did anything feel a little good today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_02',
    text: "What's been a small bright spot for you?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_03',
    text: "Anything that made you pause in a good way today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_04',
    text: "What's something that felt even a little lighter today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_05',
    text: "Did anything bring you a bit of peace today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_06',
    text: "What's something you're glad happened today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_07',
    text: "What's been a moment worth holding onto today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_08',
    text: "Anything that made you smile, even briefly?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_09',
    text: "What felt steady or good today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_10',
    text: "Was there a moment today that just felt… right?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_11',
    text: "What's something that didn't feel so heavy today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    id: 'OPENING_WARM_12',
    text: "What's been a quiet good in your day?",
    tone: PalOpeningTone.warm,
  ),
];

/// Returns a uniformly random opening line from [palOpeningLines].
///
/// [random] is injectable for testing determinism.
PalOpeningLine pickOpeningLine([Random? random]) {
  final rng = random ?? Random();
  return palOpeningLines[rng.nextInt(palOpeningLines.length)];
}

/// Returns all 60 opening-line texts in shuffled order, for passive
/// rotation surfaces such as the mood screen TextField placeholder
/// (Feature 2.0, "Mood Screen Passive Placeholder Rotation").
///
/// Every call produces a fresh permutation of the full library, so a
/// caller that exhausts the returned list and then re-invokes this
/// function is guaranteed to visit every line exactly once per cycle.
///
/// [avoidFirst], when non-null, prevents the returned list from starting
/// with that text — useful across cycle boundaries to prevent the
/// previously-displayed line from appearing twice in a row. If the
/// shuffle happens to place [avoidFirst] at index 0, it is swapped with
/// the last element.
///
/// [random] is injectable for deterministic tests.
List<String> buildShuffledOpeningLineTexts({
  Random? random,
  String? avoidFirst,
}) {
  final rng = random ?? Random();
  final pool = [for (final l in palOpeningLines) l.text];
  pool.shuffle(rng);
  if (avoidFirst != null &&
      pool.isNotEmpty &&
      pool.first == avoidFirst &&
      pool.length > 1) {
    final tmp = pool[0];
    pool[0] = pool[pool.length - 1];
    pool[pool.length - 1] = tmp;
  }
  return pool;
}

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
  final String text;
  final PalOpeningTone tone;

  const PalOpeningLine({
    required this.text,
    required this.tone,
  });
}

/// The locked 60-line opening library (Feature 2.0).
///
/// 12 lines per tone bucket. Content is locked — wording changes require
/// a SPEC update. Selected uniformly at random; no time-awareness.
const List<PalOpeningLine> palOpeningLines = [
  // ── gentle (1–12) ──────────────────────────────────────────────────────────
  PalOpeningLine(
    text: "Hey… I'm here. What's today been like for you?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "You don't have to filter anything… how's your day been?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "Hey… what's been sitting with you today?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "I've got time—what's been going on for you?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "What's been on your heart lately… even a little?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "Hey… how are you really doing right now?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "What's been quietly on your mind today?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "You can just say it as it is… how's today been?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "What's been lingering with you today?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "Hey… what kind of day has it been for you?",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "What's been with you today… start wherever you want.",
    tone: PalOpeningTone.gentle,
  ),
  PalOpeningLine(
    text: "How have things been feeling on your side today?",
    tone: PalOpeningTone.gentle,
  ),

  // ── encouraging (13–24) ────────────────────────────────────────────────────
  PalOpeningLine(
    text: "You don't have to carry it alone… what's been going on?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "Hey… what's been a little heavy for you today?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "If something's been weighing on you, you can say it here.",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "What's been taking more out of you than you expected?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "Hey… what's been hard to shake today?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "If today's been a lot, I'm here—what's going on?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "What's been asking a lot from you lately?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "Hey… what's been sitting a little heavier than usual?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "What's been pressing on you, even if it's small?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "You can let it out here… what's been going on?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "What's been harder than you thought it would be today?",
    tone: PalOpeningTone.encouraging,
  ),
  PalOpeningLine(
    text: "Hey… what's been pulling at you today?",
    tone: PalOpeningTone.encouraging,
  ),

  // ── calm (25–36) ───────────────────────────────────────────────────────────
  PalOpeningLine(
    text: "Hey… take a breath with me. What's been going on?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "No rush at all… what's been on your heart?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "We can just slow this down… how are you feeling?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "Hey… you can take your time here. What's been today?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "Let's just pause for a second… what's been going on?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "You don't have to hurry through it… what's been on your mind?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "Hey… we can sit here a moment. What's been with you?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "Whenever you're ready… what's been on your heart?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "Let's just take this one piece at a time… what's going on?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "Hey… just ease into it. What's been today for you?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "We can keep this simple… how are you feeling right now?",
    tone: PalOpeningTone.calm,
  ),
  PalOpeningLine(
    text: "Take your time… what's been staying with you today?",
    tone: PalOpeningTone.calm,
  ),

  // ── weary (37–48) ──────────────────────────────────────────────────────────
  PalOpeningLine(
    text: "Hey… you sound like you might be tired. What's been going on?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "Has today been a long one for you?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "Hey… what's been wearing on you today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "You don't have to push through it here… what's been hard?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "What's been taking more energy than you had today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "Hey… what's been a little too much lately?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "What's been draining you today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "Has anything just felt… heavy today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "Hey… what's been a lot for you today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "What's been hard to carry today?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "Hey… how are you holding up through all of it?",
    tone: PalOpeningTone.weary,
  ),
  PalOpeningLine(
    text: "What's been quietly exhausting for you today?",
    tone: PalOpeningTone.weary,
  ),

  // ── warm (49–60) ───────────────────────────────────────────────────────────
  PalOpeningLine(
    text: "Hey… did anything feel a little good today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "What's been a small bright spot for you?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "Hey… anything that made you pause in a good way today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "What's something that felt even a little lighter today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "Did anything bring you a bit of peace today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "Hey… what's something you're glad happened today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "What's been a moment worth holding onto today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "Hey… anything that made you smile, even briefly?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "What felt steady or good today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "Was there a moment today that just felt… right?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
    text: "Hey… what's something that didn't feel so heavy today?",
    tone: PalOpeningTone.warm,
  ),
  PalOpeningLine(
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

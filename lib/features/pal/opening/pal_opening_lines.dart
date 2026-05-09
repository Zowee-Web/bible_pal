import 'dart:math';

import 'pal_opening_recency.dart';

/// **Deprecated** — retired Feature 5.1 tone-biased reflection enum.
///
/// The 60-line tone-bucketed opening library was replaced by the 12-line
/// time-bucketed library (Feature 2.0, SPEC §2.0 revision 2026-04-28),
/// and the `PalOpeningTone` signal is no longer set anywhere in the live
/// flow. This enum is preserved ONLY so the orphaned
/// `lib/core/pal_tone_biased_reflection_lines.dart` (also retired Feature
/// 5.1, kept on disk pending full cleanup) continues to compile. Do NOT
/// reference this enum in new code — it has no live producers and no
/// runtime effect. Selection for both opening lines and reflections is
/// time-bucketed and mood-blind respectively.
@Deprecated(
  'Retired with Feature 2.0 12-line time-bucketed opening library. '
  'Kept only so the unwired pal_tone_biased_reflection_lines.dart still '
  'compiles. Use OpeningTimeBucket for opening selection.',
)
enum PalOpeningTone {
  gentle,
  encouraging,
  calm,
  weary,
  warm,
}

/// Time-of-day bucket for a PAL opening greeting line (Feature 2.0).
enum OpeningTimeBucket { morning, afternoon, evening, night }

/// Whether a line already contains its own greeting word ("Hi…", "Good
/// morning…") or is bare. Only `bare` lines are eligible for name-prefix
/// attachment — `greeting` lines play solo to avoid stacking awkwardness
/// with [NameAudioService] prefixes like "Hi there, {name}!".
enum OpeningLineType { greeting, bare }

/// A single entry in the PAL opening greeting library.
class PalOpeningLine {
  final String id;
  final String text;
  final OpeningTimeBucket bucket;
  final OpeningLineType type;

  const PalOpeningLine({
    required this.id,
    required this.text,
    required this.bucket,
    required this.type,
  });
}

/// The locked 12-line opening greeting library (Feature 2.0).
///
/// 3 lines per time bucket. Content is locked — wording changes require a
/// SPEC update. Selection is mood-blind: time bucket is computed from the
/// current local hour, then a line is chosen from that bucket via
/// persistent recency rotation ([PalOpeningRecency]).
///
/// Each line carries a unique ID for audio asset lookup
/// (`assets/pal/audio/{voiceKey}/{lineId}.mp3`).
const List<PalOpeningLine> palOpeningLines = [
  // ── morning (5am–12pm) ────────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_MORN_01',
    text: "Good morning… how's your day going so far?",
    bucket: OpeningTimeBucket.morning,
    type: OpeningLineType.greeting,
  ),
  PalOpeningLine(
    id: 'OPENING_MORN_02',
    text: "Hi… how's your morning been?",
    bucket: OpeningTimeBucket.morning,
    type: OpeningLineType.greeting,
  ),
  PalOpeningLine(
    id: 'OPENING_MORN_03',
    text: "How are you doing today?",
    bucket: OpeningTimeBucket.morning,
    type: OpeningLineType.bare,
  ),

  // ── afternoon (12pm–5pm) ──────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_AFTN_01',
    text: "How's your day going?",
    bucket: OpeningTimeBucket.afternoon,
    type: OpeningLineType.bare,
  ),
  PalOpeningLine(
    id: 'OPENING_AFTN_02',
    text: "How's everything been today?",
    bucket: OpeningTimeBucket.afternoon,
    type: OpeningLineType.bare,
  ),
  PalOpeningLine(
    id: 'OPENING_AFTN_03',
    text: "What kind of day has it been?",
    bucket: OpeningTimeBucket.afternoon,
    type: OpeningLineType.bare,
  ),

  // ── evening (5pm–10pm) ────────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_EVEN_01',
    text: "How was your day?",
    bucket: OpeningTimeBucket.evening,
    type: OpeningLineType.bare,
  ),
  PalOpeningLine(
    id: 'OPENING_EVEN_02',
    text: "What's today been like for you?",
    bucket: OpeningTimeBucket.evening,
    type: OpeningLineType.bare,
  ),
  PalOpeningLine(
    id: 'OPENING_EVEN_03',
    text: "How's your day been?",
    bucket: OpeningTimeBucket.evening,
    type: OpeningLineType.bare,
  ),

  // ── night (10pm–5am) ──────────────────────────────────────────────────────
  PalOpeningLine(
    id: 'OPENING_NIGHT_01',
    text: "How's your night going?",
    bucket: OpeningTimeBucket.night,
    type: OpeningLineType.bare,
  ),
  PalOpeningLine(
    id: 'OPENING_NIGHT_02',
    text: "How are you tonight?",
    bucket: OpeningTimeBucket.night,
    type: OpeningLineType.bare,
  ),
  PalOpeningLine(
    id: 'OPENING_NIGHT_03',
    text: "What's your night been like?",
    bucket: OpeningTimeBucket.night,
    type: OpeningLineType.bare,
  ),
];

/// Map a 24-hour clock value to a [OpeningTimeBucket]. Boundaries:
/// morning = `[5, 12)`, afternoon = `[12, 17)`, evening = `[17, 22)`,
/// night = `[22, 24) ∪ [0, 5)`.
OpeningTimeBucket bucketForHour(int hour) {
  if (hour >= 22 || hour < 5) return OpeningTimeBucket.night;
  if (hour < 12) return OpeningTimeBucket.morning;
  if (hour < 17) return OpeningTimeBucket.afternoon;
  return OpeningTimeBucket.evening;
}

/// Stable storage key for a bucket's recency history.
String bucketKey(OpeningTimeBucket bucket) => bucket.name;

/// Returns the lines belonging to [bucket], in declaration order.
List<PalOpeningLine> linesForBucket(OpeningTimeBucket bucket) =>
    [for (final l in palOpeningLines) if (l.bucket == bucket) l];

/// Pick an opening line for the given local [hour] (0–23) using the
/// persistent recency rotation in [PalOpeningRecency].
///
/// Caller is responsible for awaiting [PalOpeningRecency.ensureInitialized]
/// before the first pick if persistence across app restarts is desired.
PalOpeningLine pickOpeningLineForHour(int hour) {
  final bucket = bucketForHour(hour);
  final lines = linesForBucket(bucket);
  // Library invariant: every bucket has at least one line.
  assert(lines.isNotEmpty, 'Empty bucket ${bucket.name}');
  final index = PalOpeningRecency.pickIndex(bucketKey(bucket), lines.length);
  return lines[index];
}

/// Returns all opening-line texts in shuffled order, for passive
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

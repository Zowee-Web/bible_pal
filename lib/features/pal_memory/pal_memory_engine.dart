import 'pal_memory_line.dart';
import 'pal_memory_templates.dart';
import 'pal_session.dart';

/// Decides whether PAL has anything to say about the user's recent
/// listening, and if so, which line.
///
/// PAL Memory Doctrine Slice 2a (see docs/PAL_MEMORY_DOCTRINE.md): pure
/// function over its inputs. No storage access, no IO, no resolution of
/// the `{storyName}` placeholder, no recording of "PAL spoke." The
/// engine's contract is "given X, here's what *would* be said." Whether
/// anything is actually said — and the corresponding cooldown advance —
/// is Slice 2b's responsibility.
///
/// Returns null whenever PAL should stay silent. Silence is an explicit
/// product choice, not a fallback. The doctrine prefers under-speaking
/// to over-speaking.
class PalMemoryEngine {
  const PalMemoryEngine();

  /// Minimum number of completed sessions before PAL may speak a memory
  /// line. One completion is too thin to feel like recognition; three
  /// establishes a pattern the user can recognize as theirs.
  static const int kMinCompletions = 3;

  /// How recently the source session must have been completed for PAL
  /// to speak about it. Tighter than the store's 14-day read window:
  /// memory lines must be honest about "yesterday" / "this week."
  static const Duration kRecencyWindow = Duration(days: 7);

  /// Minimum interval between two memory lines. Caller is responsible
  /// for tracking the last-spoken timestamp truthfully and feeding it
  /// into [nextLine]; the engine itself does not persist anything.
  static const Duration kCooldown = Duration(days: 3);

  /// Returns the line PAL would speak now, or null if PAL should stay
  /// silent. Pure: same inputs always produce the same output.
  ///
  /// - [sessions] is the full session log (any order; engine reorders).
  /// - [lastSpokenAt] is when PAL last delivered a memory line. Pass
  ///   null if PAL has never spoken one. The engine does NOT update
  ///   this — Slice 2a has no truthful producer of "spoken." Slice 2b
  ///   will own that side-effect.
  /// - [now] is the current time, injected so tests are deterministic.
  PalMemoryLine? nextLine({
    required List<PalSession> sessions,
    required DateTime? lastSpokenAt,
    required DateTime now,
  }) {
    // Gate 1 — minimum completions.
    if (sessions.length < kMinCompletions) return null;

    // Gate 2 — cooldown. Silent if PAL spoke recently enough.
    if (lastSpokenAt != null && now.difference(lastSpokenAt) < kCooldown) {
      return null;
    }

    // Gate 3 — recency. Source must be within the window AND must not
    // be from today (replaying a story the user just finished isn't
    // memory; it's an echo).
    final today = _dayStart(now);
    final source = _pickSource(sessions, now);
    if (source == null) return null;

    final completedDay = _dayStart(source.completedAt);
    final daysAgo = today.difference(completedDay).inDays;
    if (daysAgo < 1 || daysAgo > kRecencyWindow.inDays) return null;

    final band = _bandFor(daysAgo);

    // Deterministic variant pick per source session — same session
    // never produces two different lines across repeat queries.
    final variants = PalMemoryTemplates.variantsFor(band);
    if (variants.isEmpty) return null;
    final variant = variants[_stableHash(source) % variants.length];

    return PalMemoryLine(
      template: variant.fullTemplate,
      carrierClipId: variant.carrierClipId,
      carrierText: variant.carrierText,
      band: band,
      sourceStoryId: source.storyId,
      sourceBibleStoryKey: source.bibleStoryKey,
    );
  }

  /// The newest completed session in the list, or null if empty. The
  /// recency-window check happens later via calendar-day math in
  /// [nextLine] so there's a single source of truth for "within window"
  /// — otherwise a duration-based filter here can disagree with the
  /// calendar boundary at the 7-day edge.
  PalSession? _pickSource(List<PalSession> sessions, DateTime now) {
    PalSession? best;
    for (final s in sessions) {
      if (best == null || s.completedAt.isAfter(best.completedAt)) {
        best = s;
      }
    }
    return best;
  }

  RecencyBand _bandFor(int daysAgo) {
    if (daysAgo <= 1) return RecencyBand.yesterday;
    if (daysAgo <= 4) return RecencyBand.fewDaysAgo;
    return RecencyBand.earlierThisWeek;
  }

  /// Calendar day truncation. Memory lines must align to user-perceived
  /// "yesterday" / "today," not to 24-hour clock windows from completion.
  DateTime _dayStart(DateTime dt) => DateTime(dt.year, dt.month, dt.day);

  /// Stable polynomial hash over (storyId, completedAt). Stable across
  /// runs (unlike `Object.hashCode`), so the variant chosen for a given
  /// session is reproducible — important for tests and for the
  /// "same session never produces two different lines" guarantee.
  int _stableHash(PalSession s) {
    final src =
        '${s.storyId}|${s.completedAt.millisecondsSinceEpoch.toString()}';
    var h = 0;
    for (var i = 0; i < src.length; i++) {
      h = (h * 31 + src.codeUnitAt(i)) & 0x7fffffff;
    }
    return h;
  }
}

import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/pal_memory_engine.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_line.dart';
import 'package:bible_pal/features/pal_memory/pal_session.dart';

/// Tests for PAL Memory Doctrine Slice 2a — the rules engine.
/// See docs/PAL_MEMORY_DOCTRINE.md.
///
/// Slice 2a is a pure function. These tests pin down: the three gates
/// (min completions, recency window, cooldown), the calendar-day boundary
/// that decides recency bands, deterministic variant picking per source
/// session, and the "silent today" rule that keeps PAL from echoing a
/// story the user just finished.
void main() {
  // Fixed "now" so every test is deterministic. Mid-afternoon avoids
  // edge cases where DateTime.now() could land at midnight rollovers.
  final now = DateTime.utc(2026, 6, 18, 15, 0);

  PalSession session({
    String storyId = '1007',
    String? bibleStoryKey = 'jonah_storm',
    required DateTime completedAt,
  }) =>
      PalSession(
        storyId: storyId,
        completedAt: completedAt,
        bibleStoryKey: bibleStoryKey,
        languageStyle: 'WEB',
      );

  const engine = PalMemoryEngine();

  group('Gate 1 — minimum completions', () {
    test('returns null when fewer than 3 sessions exist', () {
      final sessions = [
        session(completedAt: now.subtract(const Duration(days: 1))),
        session(completedAt: now.subtract(const Duration(days: 2))),
      ];
      expect(
        engine.nextLine(sessions: sessions, lastSpokenAt: null, now: now),
        isNull,
      );
    });

    test('speaks when exactly 3 sessions exist (boundary)', () {
      final sessions = [
        session(
            storyId: 'a',
            completedAt: now.subtract(const Duration(days: 5))),
        session(
            storyId: 'b',
            completedAt: now.subtract(const Duration(days: 3))),
        session(
            storyId: 'c',
            completedAt: now.subtract(const Duration(days: 1))),
      ];
      expect(
        engine.nextLine(sessions: sessions, lastSpokenAt: null, now: now),
        isNotNull,
      );
    });
  });

  group('Gate 2 — cooldown', () {
    test('returns null when lastSpokenAt is within the 3-day window', () {
      final sessions = List.generate(
        4,
        (i) => session(
          storyId: 's_$i',
          completedAt: now.subtract(Duration(days: i + 1)),
        ),
      );
      // Spoken 2 days ago — still inside the 3-day cooldown.
      expect(
        engine.nextLine(
          sessions: sessions,
          lastSpokenAt: now.subtract(const Duration(days: 2)),
          now: now,
        ),
        isNull,
      );
    });

    test('speaks when lastSpokenAt is exactly cooldown ago (boundary)', () {
      final sessions = List.generate(
        4,
        (i) => session(
          storyId: 's_$i',
          completedAt: now.subtract(Duration(days: i + 1)),
        ),
      );
      // Boundary: difference == kCooldown, not "<" cooldown.
      expect(
        engine.nextLine(
          sessions: sessions,
          lastSpokenAt: now.subtract(PalMemoryEngine.kCooldown),
          now: now,
        ),
        isNotNull,
      );
    });

    test('speaks when lastSpokenAt is null (PAL has never spoken)', () {
      final sessions = List.generate(
        3,
        (i) => session(
          storyId: 's_$i',
          completedAt: now.subtract(Duration(days: i + 1)),
        ),
      );
      expect(
        engine.nextLine(sessions: sessions, lastSpokenAt: null, now: now),
        isNotNull,
      );
    });
  });

  group('Gate 3 — recency window + silent-today rule', () {
    test('returns null when newest session is > 7 days old', () {
      final sessions = List.generate(
        3,
        (i) => session(
          storyId: 's_$i',
          completedAt: now.subtract(Duration(days: 10 + i)),
        ),
      );
      expect(
        engine.nextLine(sessions: sessions, lastSpokenAt: null, now: now),
        isNull,
      );
    });

    test('returns null when newest session is today (silent-today rule)', () {
      // 3 completions, but the most recent was today — PAL stays silent
      // because "remembering" something the user just finished is an
      // echo, not memory.
      final sessions = [
        session(
            storyId: 's_0',
            completedAt: now.subtract(const Duration(days: 5))),
        session(
            storyId: 's_1',
            completedAt: now.subtract(const Duration(days: 3))),
        session(
            storyId: 's_2',
            completedAt: now.subtract(const Duration(hours: 2))),
      ];
      expect(
        engine.nextLine(sessions: sessions, lastSpokenAt: null, now: now),
        isNull,
      );
    });

    test('walks past today\'s session to find an older in-window one',
        () {
      // Even with a same-day completion present, the engine should
      // honor the silent-today rule for the newest pick — meaning the
      // newest in-window is the same-day one, so we go silent. (This is
      // the inverse of "find older fallback" — by design the engine
      // does NOT fall back to an older session when today blocks the
      // line.)
      final sessions = [
        session(
            storyId: 's_0',
            completedAt: now.subtract(const Duration(days: 5))),
        session(
            storyId: 's_1',
            completedAt: now.subtract(const Duration(days: 3))),
        session(
            storyId: 's_2',
            completedAt: now.subtract(const Duration(hours: 2))),
      ];
      // Confirms the choice: today blocks, no fallback. Matches the
      // doctrine — speak about the most recent or stay silent.
      expect(
        engine.nextLine(sessions: sessions, lastSpokenAt: null, now: now),
        isNull,
      );
    });

    test('speaks about the newest in-window session when no same-day exists',
        () {
      final sessions = [
        session(
            storyId: 'old',
            completedAt: now.subtract(const Duration(days: 6))),
        session(
            storyId: 'newer',
            completedAt: now.subtract(const Duration(days: 4))),
        session(
            storyId: 'newest',
            completedAt: now.subtract(const Duration(days: 1))),
      ];
      final line = engine.nextLine(
        sessions: sessions,
        lastSpokenAt: null,
        now: now,
      );
      expect(line, isNotNull);
      expect(line!.sourceStoryId, 'newest');
    });
  });

  group('Recency band selection', () {
    PalMemoryLine speakAbout(DateTime completedAt) {
      // Pad with two old completions so the min-completions gate is met
      // but the newest in-window session is the one under test.
      final sessions = [
        session(
            storyId: 'pad_a',
            completedAt: now.subtract(const Duration(days: 8))),
        session(
            storyId: 'pad_b',
            completedAt: now.subtract(const Duration(days: 9))),
        session(storyId: 'subject', completedAt: completedAt),
      ];
      return engine.nextLine(
        sessions: sessions,
        lastSpokenAt: null,
        now: now,
      )!;
    }

    test('1 calendar day ago → yesterday band', () {
      final line = speakAbout(now.subtract(const Duration(days: 1)));
      expect(line.band, RecencyBand.yesterday);
      expect(line.template.toLowerCase(), contains('yesterday'));
    });

    test('2 calendar days ago → fewDaysAgo band', () {
      final line = speakAbout(now.subtract(const Duration(days: 2)));
      expect(line.band, RecencyBand.fewDaysAgo);
      expect(line.template.toLowerCase(), contains('few days ago'));
    });

    test('4 calendar days ago → fewDaysAgo band (boundary)', () {
      final line = speakAbout(now.subtract(const Duration(days: 4)));
      expect(line.band, RecencyBand.fewDaysAgo);
    });

    test('5 calendar days ago → earlierThisWeek band (boundary)', () {
      final line = speakAbout(now.subtract(const Duration(days: 5)));
      expect(line.band, RecencyBand.earlierThisWeek);
      expect(line.template.toLowerCase(), contains('earlier this week'));
    });

    test('7 calendar days ago → earlierThisWeek band (window edge)', () {
      final line = speakAbout(now.subtract(const Duration(days: 7)));
      expect(line.band, RecencyBand.earlierThisWeek);
    });
  });

  group('Variant picking — deterministic per source session', () {
    test('same session produces the same template on repeat queries', () {
      final sessions = [
        session(
            storyId: 'a',
            completedAt: now.subtract(const Duration(days: 5))),
        session(
            storyId: 'b',
            completedAt: now.subtract(const Duration(days: 4))),
        session(
            storyId: 'subject',
            completedAt: now.subtract(const Duration(days: 1))),
      ];
      final a = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now);
      final b = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now);
      expect(a!.template, b!.template);
      expect(a.sourceStoryId, b.sourceStoryId);
    });

    test('different sessions produce varied templates (smoke check)', () {
      // Vary completedAt + storyId across many candidates and confirm
      // we see more than one wording variant in the output set. This
      // is a smoke check on the hash distribution, not a strict guarantee.
      final templates = <String>{};
      for (var i = 0; i < 30; i++) {
        final sessions = [
          session(
              storyId: 'pad',
              completedAt: now.subtract(const Duration(days: 8))),
          session(
              storyId: 'pad2',
              completedAt: now.subtract(const Duration(days: 9))),
          session(
            storyId: 'subj_$i',
            completedAt:
                now.subtract(Duration(days: 1, minutes: i * 7)),
          ),
        ];
        final line = engine.nextLine(
            sessions: sessions, lastSpokenAt: null, now: now);
        if (line != null) templates.add(line.template);
      }
      expect(templates.length, greaterThan(1));
    });
  });

  group('Output shape', () {
    test('memory line carries the source session ids forward', () {
      final sessions = [
        session(
            storyId: 'a',
            completedAt: now.subtract(const Duration(days: 5))),
        session(
            storyId: 'b',
            completedAt: now.subtract(const Duration(days: 4))),
        session(
          storyId: '1007',
          bibleStoryKey: 'jonah_storm',
          completedAt: now.subtract(const Duration(days: 1)),
        ),
      ];
      final line = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now);
      expect(line!.sourceStoryId, '1007');
      expect(line.sourceBibleStoryKey, 'jonah_storm');
    });

    test('template always contains the {storyName} placeholder', () {
      final sessions = [
        session(
            storyId: 'a',
            completedAt: now.subtract(const Duration(days: 5))),
        session(
            storyId: 'b',
            completedAt: now.subtract(const Duration(days: 4))),
        session(
            storyId: 'c',
            completedAt: now.subtract(const Duration(days: 1))),
      ];
      final line = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now);
      expect(line!.template, contains('{storyName}'));
    });

    test('memory line carries a non-empty carrierClipId (Slice 2c.2)', () {
      // The carrierClipId is the audio-layer identifier the resolver
      // uses to locate the pre-rendered fragment. The engine must
      // populate it on every returned line; nothing downstream can
      // recover from a missing or malformed id.
      final sessions = [
        session(
            storyId: 'a',
            completedAt: now.subtract(const Duration(days: 5))),
        session(
            storyId: 'b',
            completedAt: now.subtract(const Duration(days: 4))),
        session(
            storyId: 'c',
            completedAt: now.subtract(const Duration(days: 1))),
      ];
      final line = engine.nextLine(
          sessions: sessions, lastSpokenAt: null, now: now);
      expect(line!.carrierClipId, isNotEmpty);
      expect(line.carrierClipId.startsWith('carrier_'), isTrue);
    });
  });

  group('Empty input', () {
    test('returns null on empty sessions', () {
      expect(
        engine.nextLine(sessions: const [], lastSpokenAt: null, now: now),
        isNull,
      );
    });
  });
}

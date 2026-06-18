// Verifies the kid-specific PAL response language (SPEC Feature 51.7).
//
// The locked Kids decision is: acknowledge the feeling first, then tell a
// fitting story. These tests guard the "acknowledge" half so the response
// language can never regress into the banned reassurance/explanation phrasing,
// and so PAL always stays WITH the child (never leaves a child alone with a
// scary feeling).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bible_pal/core/kid_pal_reflection_lines.dart';
import 'package:bible_pal/core/kid_pal_transition_lines.dart';

/// The locked set of moods MoodService can emit (mirrors the adult
/// micro-response / reflection mood keys). Kid coverage must match exactly so
/// the voice path never falls back to adult lines in Kids mode.
const _canonicalMoods = <String>{
  'joyful',
  'grateful',
  'weary',
  'anxious',
  'hurting',
  'brave_courage',
  'calm_peaceful',
  'encouraging',
};

/// Phrases PAL must NEVER say to a child (case-insensitive substring match).
const _bannedSubstrings = <String>[
  'everything will be okay',
  'everything will be ok',
  'everything will be fine',
  'will not die',
  "won't die",
  'wont die',
  'do not be scared',
  "don't be scared",
  'dont be scared',
  'do not be afraid',
  "don't be afraid",
  'for a reason',
  'god did this',
  'everything happens',
  // "Your feeling is wrong" phrasings — adults hear comfort, kids hear
  // "your feeling is wrong" (Adam, 2026-06-18).
  'nothing to be afraid of',
  'nothing to be scared of',
  "there's nothing to",
  'there is nothing to',
  "you don't need to worry",
  'you do not need to worry',
  "you don't have to worry",
  'you do not have to worry',
  "it's okay to",
  'it is okay to',
  'nothing bad will happen',
  "don't worry",
  'do not worry',
  'cheer up',
];

/// Reassurance / command words that signal false promises or "stop feeling".
/// Matched as whole words (case-insensitive).
const _bannedWords = <String>[
  'okay',
  'ok',
  'fine',
  'promise',
];

/// Presence signals — at least one must appear in every line so PAL stays
/// WITH the child in the feeling.
const _presenceSignals = <String>[
  'with you',
  'here',
  'together',
  'beside you',
  'stay close',
  'lean on me',
  'not alone',
  'by yourself',
  'side by side',
];

bool _containsWord(String haystackLower, String word) {
  final re = RegExp('\\b${RegExp.escape(word)}\\b');
  return re.hasMatch(haystackLower);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final allLines = [
    for (final entry in kidReflectionLines.entries)
      ...entry.value.map((r) => MapEntry(entry.key, r)),
  ];

  group('51.7 mood coverage', () {
    test('covers every MoodService mood (no fallback to adult lines)', () {
      // Every mood the voice path can produce must have kid lines so
      // getLineRef never returns null in Kids mode.
      final kidMoods = kidReflectionLines.keys.toSet();
      expect(kidMoods, equals(_canonicalMoods),
          reason: 'kid reflection moods must match the canonical mood set');
    });

    test('each mood has at least 3 lines', () {
      for (final entry in kidReflectionLines.entries) {
        expect(entry.value.length, greaterThanOrEqualTo(3),
            reason: '${entry.key} needs >= 3 lines for rotation variety');
      }
    });
  });

  group('51.7 line IDs', () {
    test('all ids are unique and non-empty', () {
      final ids = allLines.map((e) => e.value.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate line id');
      for (final id in ids) {
        expect(id.trim(), isNotEmpty);
        expect(id.startsWith('KID_REFL_'), isTrue,
            reason: 'id $id should start with KID_REFL_');
      }
    });
  });

  group('51.7 LOCKED safety rules', () {
    test('no banned reassurance / explanation phrases', () {
      for (final entry in allLines) {
        final lower = entry.value.text.toLowerCase();
        for (final banned in _bannedSubstrings) {
          expect(lower.contains(banned), isFalse,
              reason: '"${entry.value.text}" contains banned phrase "$banned"');
        }
      }
    });

    test('no false-promise / stop-feeling words', () {
      for (final entry in allLines) {
        final lower = entry.value.text.toLowerCase();
        for (final word in _bannedWords) {
          expect(_containsWord(lower, word), isFalse,
              reason: '"${entry.value.text}" uses banned word "$word"');
        }
      }
    });

    test('every line stays WITH the child (presence signal present)', () {
      for (final entry in allLines) {
        final lower = entry.value.text.toLowerCase();
        final hasPresence = _presenceSignals.any(lower.contains);
        expect(hasPresence, isTrue,
            reason: '"${entry.value.text}" has no presence signal '
                '(one of $_presenceSignals)');
      }
    });

    test('abstract "alone" framing is used sparingly (<= 25% of lines)', () {
      // Concrete presence ("I'm right here with you") beats the abstract
      // "you are not alone" for ages 4-7 (Adam, 2026-06-18). Keep it, but
      // rare — a young child grasps someone being WITH them, not the idea
      // of not-aloneness.
      final abstract = allLines.where((e) {
        final lower = e.value.text.toLowerCase();
        return _containsWord(lower, 'alone') || lower.contains('by yourself');
      }).length;
      expect(abstract / allLines.length, lessThanOrEqualTo(0.25),
          reason: '$abstract/${allLines.length} lines lean on abstract '
              '"alone"/"by yourself" framing; prefer concrete presence');
    });
  });

  group('51.7 kid diction', () {
    test('lines are short (<= 20 words) and literal', () {
      for (final entry in allLines) {
        final words = entry.value.text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
        expect(words, lessThanOrEqualTo(20),
            reason: '"${entry.value.text}" is too long for ages 4-7');
        expect(words, greaterThanOrEqualTo(4),
            reason: '"${entry.value.text}" is too terse to acknowledge');
      }
    });

    test('ASCII only (no smart quotes / em dash / unicode)', () {
      for (final entry in allLines) {
        for (final code in entry.value.text.runes) {
          expect(code, lessThan(128),
              reason: '"${entry.value.text}" contains non-ASCII char $code');
        }
      }
    });
  });

  group('51.7 selection', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      KidPalReflectionLines.resetForTesting();
    });

    test('getLineRef returns a kid line for every mood', () async {
      await KidPalReflectionLines.ensureLoaded();
      for (final mood in kidReflectionLines.keys) {
        final ref = KidPalReflectionLines.getLineRef(mood);
        expect(ref, isNotNull, reason: 'no line for $mood');
        expect(ref!.id.startsWith('KID_REFL_'), isTrue);
      }
    });

    test('getLineRef returns null for unknown / null mood', () async {
      await KidPalReflectionLines.ensureLoaded();
      expect(KidPalReflectionLines.getLineRef(null), isNull);
      expect(KidPalReflectionLines.getLineRef('not_a_mood'), isNull);
    });

    test('rotation cycles through all lines before repeating', () async {
      await KidPalReflectionLines.ensureLoaded();
      const mood = 'anxious';
      final pool = kidReflectionLines[mood]!;
      final seen = <String>{};
      for (var i = 0; i < pool.length; i++) {
        seen.add(KidPalReflectionLines.getLineRef(mood)!.id);
      }
      expect(seen.length, pool.length,
          reason: 'rotation should visit every line once per cycle');
    });
  });

  group('51.7 transition (invitation + wonder)', () {
    test('ids unique, non-empty, KID_TRANS_ prefixed', () {
      final ids = kidTransitionLines.map((r) => r.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'duplicate transition id');
      for (final r in kidTransitionLines) {
        expect(r.id.startsWith('KID_TRANS_'), isTrue, reason: r.id);
        expect(r.text.trim(), isNotEmpty);
      }
    });

    test('no banned phrases / words', () {
      for (final r in kidTransitionLines) {
        final lower = r.text.toLowerCase();
        for (final banned in _bannedSubstrings) {
          expect(lower.contains(banned), isFalse,
              reason: '"${r.text}" contains banned phrase "$banned"');
        }
        for (final word in _bannedWords) {
          expect(_containsWord(lower, word), isFalse,
              reason: '"${r.text}" uses banned word "$word"');
        }
      }
    });

    test('concrete + short (no adult abstraction), ASCII only', () {
      // Kid transitions invite into the story; they must not borrow the adult
      // pool's abstract phrasing, which a 4-7 year old does not parse.
      const adultAbstractions = [
        'scripture',
        'carries',
        'carrying',
        'weight',
        'reflects',
        'connect',
      ];
      for (final r in kidTransitionLines) {
        final lower = r.text.toLowerCase();
        for (final word in adultAbstractions) {
          expect(lower.contains(word), isFalse,
              reason: '"${r.text}" uses adult-abstract word "$word"');
        }
        final words = r.text
            .split(RegExp(r'\s+'))
            .where((w) => w.isNotEmpty)
            .length;
        expect(words, lessThanOrEqualTo(8),
            reason: '"${r.text}" is too long for a kid invitation');
        for (final code in r.text.runes) {
          expect(code, lessThan(128),
              reason: '"${r.text}" contains non-ASCII char $code');
        }
      }
    });

    group('selection', () {
      setUp(() {
        SharedPreferences.setMockInitialValues({});
        KidPalTransitionLines.resetForTesting();
      });

      test('getLineRef returns a kid transition every time', () async {
        await KidPalTransitionLines.ensureLoaded();
        final ref = KidPalTransitionLines.getLineRef();
        expect(ref.id.startsWith('KID_TRANS_'), isTrue);
      });

      test('rotation cycles through all lines before repeating', () async {
        await KidPalTransitionLines.ensureLoaded();
        final seen = <String>{};
        for (var i = 0; i < kidTransitionLines.length; i++) {
          seen.add(KidPalTransitionLines.getLineRef().id);
        }
        expect(seen.length, kidTransitionLines.length);
      });
    });
  });
}

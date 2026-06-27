import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/memory_line_resolver.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_display_name_registry.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_line.dart';

/// Tests for [MemoryLineResolver] — Slice 2c.2 of the PAL Memory
/// Doctrine (docs/PAL_MEMORY_DOCTRINE.md).
///
/// Pure-function tests; no asset bundle, no audio. The resolver's only
/// job is to combine a PalMemoryLine + active voice + display-name
/// registry into a ResolvedMemoryLine, or return null for the opt-out
/// cases the doctrine's silence floor depends on.
void main() {
  // A tiny inline registry — small enough to make every test obvious,
  // doesn't depend on the bundled JSON file's exact contents.
  PalMemoryDisplayNameRegistry buildRegistry() {
    return PalMemoryDisplayNameRegistry.fromJson('''
{
  "version": 1,
  "entries": [
    {"bibleStoryKey": "daniel_in_the_lions_den", "displayName": "Daniel", "clipId": "name_daniel"},
    {"bibleStoryKey": "good_samaritan",           "displayName": "the Good Samaritan", "clipId": "name_the_good_samaritan"}
  ]
}
''');
  }

  PalMemoryLine buildLine({
    String? sourceBibleStoryKey = 'daniel_in_the_lions_den',
    String sourceStoryId = '1100',
    RecencyBand band = RecencyBand.yesterday,
    String carrierClipId = 'carrier_yesterday_sat_with',
    String carrierText = 'Yesterday you sat with',
  }) {
    return PalMemoryLine(
      template: '$carrierText {storyName}.',
      carrierClipId: carrierClipId,
      carrierText: carrierText,
      band: band,
      sourceStoryId: sourceStoryId,
      sourceBibleStoryKey: sourceBibleStoryKey,
    );
  }

  group('resolve — happy path', () {
    test('produces a ResolvedMemoryLine when the registry has the key', () {
      final resolver = MemoryLineResolver(buildRegistry());
      final resolved = resolver.resolve(
        line: buildLine(),
        activeVoiceKey: 'VOICE_HOPE',
      );
      expect(resolved, isNotNull);
      expect(resolved!.voiceKey, 'VOICE_HOPE');
      expect(resolved.displayName, 'Daniel');
      expect(resolved.displayNameClipId, 'name_daniel');
      expect(resolved.carrierClipId, 'carrier_yesterday_sat_with');
      expect(resolved.carrierText, 'Yesterday you sat with');
      expect(resolved.band, RecencyBand.yesterday);
      expect(resolved.sourceStoryId, '1100');
    });

    test('fullText reads as a complete spoken sentence', () {
      final resolver = MemoryLineResolver(buildRegistry());
      final resolved = resolver.resolve(
        line: buildLine(),
        activeVoiceKey: 'VOICE_HOPE',
      )!;
      expect(resolved.fullText, 'Yesterday you sat with Daniel.');
    });

    test('preserves definite articles in display names', () {
      final resolver = MemoryLineResolver(buildRegistry());
      final resolved = resolver.resolve(
        line: buildLine(sourceBibleStoryKey: 'good_samaritan'),
        activeVoiceKey: 'VOICE_HOPE',
      )!;
      expect(resolved.displayName, 'the Good Samaritan');
      expect(resolved.fullText, 'Yesterday you sat with the Good Samaritan.');
    });
  });

  group('resolve — voice passthrough (Slice 2c voice multiplicity = 1)', () {
    test('the active voice flows into the resolved line unchanged', () {
      final resolver = MemoryLineResolver(buildRegistry());
      for (final voice in const [
        'VOICE_HOPE',
        'VOICE_SHEPHERD',
        'VOICE_STILLWATER',
      ]) {
        final resolved = resolver.resolve(
          line: buildLine(),
          activeVoiceKey: voice,
        );
        expect(resolved!.voiceKey, voice);
      }
    });
  });

  group('resolve — opt-out paths (silence floor)', () {
    test('returns null when sourceBibleStoryKey is null', () {
      final resolver = MemoryLineResolver(buildRegistry());
      final resolved = resolver.resolve(
        line: buildLine(sourceBibleStoryKey: null),
        activeVoiceKey: 'VOICE_HOPE',
      );
      expect(resolved, isNull);
    });

    test('returns null when the registry has no entry for the key', () {
      final resolver = MemoryLineResolver(buildRegistry());
      final resolved = resolver.resolve(
        line: buildLine(sourceBibleStoryKey: 'never_registered_story_key'),
        activeVoiceKey: 'VOICE_HOPE',
      );
      // Doctrine: missing display name → silence, not a fabricated phrase.
      expect(resolved, isNull);
    });
  });

  group('resolve — passthrough integrity', () {
    test('does not mutate the source line\'s template/clipId', () {
      final resolver = MemoryLineResolver(buildRegistry());
      final line = buildLine(
        carrierClipId: 'carrier_few_days_ago_listened_to',
        carrierText: 'A few days ago you listened to',
        band: RecencyBand.fewDaysAgo,
      );
      final resolved = resolver.resolve(
        line: line,
        activeVoiceKey: 'VOICE_HOPE',
      );
      expect(resolved!.carrierClipId, 'carrier_few_days_ago_listened_to');
      expect(resolved.carrierText, 'A few days ago you listened to');
      expect(resolved.band, RecencyBand.fewDaysAgo);
      // The original line is unchanged (its template still has the placeholder).
      expect(line.template, contains('{storyName}'));
    });
  });
}

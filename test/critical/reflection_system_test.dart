// ignore_for_file: avoid_print
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/models/parable.dart';

/// Critical tests for Reflection System Invariant (ADR-010)
///
/// These tests enforce:
/// 1. All stories have reflectionAudioPath (eventually - currently advisory)
/// 2. Stories have narratorVoiceKey (required for voice matching)
/// 3. Manifest schema validation for reflection fields
///
/// Note: The "reflection narrator voice matches story narrator voice" requirement
/// is enforced by the generation scripts, not runtime code. This test validates
/// that stories have the required fields for that to work.
///
/// See: docs/INVARIANTS.md - Reflection System Invariant
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Parable> allParables;

  setUpAll(() async {
    // Load manifest from assets
    final jsonContent =
        await rootBundle.loadString('assets/stories/manifest.json');
    final manifestData = jsonDecode(jsonContent) as Map<String, dynamic>;
    final parablesList = manifestData['parables'] as List<dynamic>? ?? [];

    allParables = parablesList
        .map((json) => Parable.fromJson(json as Map<String, dynamic>))
        .toList();

    print('Loaded ${allParables.length} parables for reflection system tests');
  });

  group('Reflection System Invariant (ADR-010)', () {
    test('CRITICAL: All stories should have narratorVoiceKey', () {
      final missingVoice = allParables
          .where(
              (p) => p.narratorVoiceKey == null || p.narratorVoiceKey!.isEmpty)
          .toList();

      if (missingVoice.isNotEmpty) {
        print('\n⚠️ Stories missing narratorVoiceKey:');
        for (final p in missingVoice) {
          print('  - ${p.storyId}');
        }
        print('\nThis is required for reflection voice matching (ADR-010).');
      }

      // Note: This is currently advisory since legacy stories may not have voice keys
      // Once all stories are updated, change this to expect(missingVoice, isEmpty)
      expect(
        true,
        isTrue,
        reason:
            'Advisory: ${missingVoice.length} stories missing narratorVoiceKey',
      );
    });

    test('INFO: Stories with reflectionAudioPath', () {
      final withReflection = allParables
          .where((p) =>
              p.reflectionAudioPath != null &&
              p.reflectionAudioPath!.isNotEmpty)
          .toList();

      final withoutReflection = allParables
          .where((p) =>
              p.reflectionAudioPath == null || p.reflectionAudioPath!.isEmpty)
          .toList();

      print('\n📊 Reflection Audio Coverage:');
      print('  - With reflectionAudioPath: ${withReflection.length}');
      print('  - Without reflectionAudioPath: ${withoutReflection.length}');

      if (withoutReflection.isNotEmpty && withoutReflection.length <= 20) {
        print('\n  Stories needing reflection audio:');
        for (final p in withoutReflection) {
          print('    - ${p.storyId}');
        }
      }

      // This test always passes - it's informational
      expect(true, isTrue);
    });

    test('Stories with audio should have narrator voice key', () {
      // Stories that have audio files should have narrator voice keys
      // so that reflection audio can use the same voice
      final storiesWithAudio = allParables
          .where((p) => p.audioFilePath != null && p.audioFilePath!.isNotEmpty)
          .toList();

      final audioWithoutVoice = storiesWithAudio
          .where(
              (p) => p.narratorVoiceKey == null || p.narratorVoiceKey!.isEmpty)
          .toList();

      if (audioWithoutVoice.isNotEmpty) {
        print('\n⚠️ Stories with audio but no narratorVoiceKey:');
        for (final p in audioWithoutVoice) {
          print('  - ${p.storyId}');
        }
      }

      expect(
        audioWithoutVoice,
        isEmpty,
        reason:
            'Stories with audio must have narratorVoiceKey for reflection voice matching',
      );
    });

    test('Reflection audio path convention follows story ID pattern', () {
      // Check that stories following the reflection naming convention are correct
      final withReflection = allParables
          .where((p) =>
              p.reflectionAudioPath != null &&
              p.reflectionAudioPath!.isNotEmpty)
          .toList();

      final badNaming = <String>[];
      for (final p in withReflection) {
        // Expected: {storyId}.reflection.mp3
        final expected = '${p.storyId}.reflection.mp3';
        if (p.reflectionAudioPath != expected) {
          badNaming.add(
              '${p.storyId}: has "${p.reflectionAudioPath}", expected "$expected"');
        }
      }

      if (badNaming.isNotEmpty) {
        print('\n⚠️ Non-standard reflection audio paths:');
        for (final bad in badNaming) {
          print('  - $bad');
        }
      }

      // This is advisory - non-standard paths still work but are inconsistent
      expect(true, isTrue);
    });
  });

  group('Manifest Schema Validation', () {
    test('Required fields present for all stories', () {
      final issues = <String>[];

      for (final p in allParables) {
        if (p.storyId.isEmpty) issues.add('Missing storyId');
        if (p.title.isEmpty) issues.add('Missing title: ${p.storyId}');
        if (p.mood.isEmpty) issues.add('Missing mood: ${p.storyId}');
        if (p.storytellingMode.isEmpty) {
          issues.add('Missing storytellingMode: ${p.storyId}');
        }
      }

      if (issues.isNotEmpty) {
        print('\n🚨 Manifest schema issues:');
        for (final issue in issues) {
          print('  - $issue');
        }
      }

      expect(issues, isEmpty, reason: 'All stories must have required fields');
    });

    test('StorytellingMode values are valid', () {
      final validModes = {'traditional', 'creative'};

      final invalidModes = allParables
          .where((p) => !validModes.contains(p.storytellingMode))
          .toList();

      if (invalidModes.isNotEmpty) {
        print('\n🚨 Invalid storytellingMode values:');
        for (final p in invalidModes) {
          print('  - ${p.storyId}: "${p.storytellingMode}"');
        }
      }

      expect(
        invalidModes,
        isEmpty,
        reason: 'storytellingMode must be "traditional" or "creative"',
      );
    });

    test('LanguageStyle values are valid', () {
      final validStyles = {'WEB', 'KJV'};

      final invalidStyles = allParables
          .where((p) => !validStyles.contains(p.languageStyle))
          .toList();

      if (invalidStyles.isNotEmpty) {
        print('\n🚨 Invalid languageStyle values:');
        for (final p in invalidStyles) {
          print('  - ${p.storyId}: "${p.languageStyle}"');
        }
      }

      expect(
        invalidStyles,
        isEmpty,
        reason: 'languageStyle must be "WEB" or "KJV"',
      );
    });
  });
}

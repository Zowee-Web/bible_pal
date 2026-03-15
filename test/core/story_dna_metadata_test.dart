import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Validates Creative Story DNA metadata in production meta.json files.
///
/// Tests:
/// 1. storyDna fields use valid pool values (match server/story_dna.sh pools)
/// 2. storyDna has all required sub-fields when present
/// 3. storyDna is only present on creative stories (never traditional)
/// 4. No 3+ consecutive creative stories share the same opening_type or structure_type
///
/// See ADR-020: Creative Story DNA Diversity System
void main() {
  // Valid pool values — must match server/story_dna.sh
  const validOpeningTypes = {
    'dialogue',
    'action',
    'question',
    'emotional_reflection',
    'memory',
    'object_focus',
    'conflict',
    'setting',
  };
  const validStructureTypes = {
    'conversation',
    'journey',
    'witness',
    'flashback',
    'unexpected_encounter',
    'problem_solution',
    'parallel_lives',
    'object_lesson',
  };
  const validSettingEmphasis = {'low', 'medium', 'high'};
  const validArchetypes = {
    'traveling merchant',
    'shepherd',
    'fisherman',
    'widow',
    'child',
    'craftsman',
    'teacher',
    'farmer',
    'healer',
    'stranger',
  };
  const validTones = {
    'hopeful',
    'reflective',
    'warm',
    'bittersweet',
    'wonder',
    'gentle',
    'solemn',
    'tender',
  };
  const validNarratorVoices = {
    'fireside',
    'literary',
    'folk_tale',
    'spare',
  };

  const requiredDnaFields = [
    'opening_type',
    'structure_type',
    'setting_emphasis',
    'character_archetype',
    'tone',
  ];

  group('Creative Story DNA Metadata (ADR-020)', () {
    test('storyDna fields use valid pool values when present', () {
      final creativeDir = Directory('assets/stories/creative');
      if (!creativeDir.existsSync()) return; // No stories yet

      final violations = <String>[];

      for (final storyDir in creativeDir.listSync().whereType<Directory>()) {
        final storyId = storyDir.path.split('/').last;
        final metaFile = File('${storyDir.path}/meta_$storyId.json');
        if (!metaFile.existsSync()) continue;

        final meta =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        final dna = meta['storyDna'] as Map<String, dynamic>?;
        if (dna == null) continue; // storyDna is optional (pre-DNA stories)

        final opening = dna['opening_type'] as String?;
        final structure = dna['structure_type'] as String?;
        final setting = dna['setting_emphasis'] as String?;
        final archetype = dna['character_archetype'] as String?;
        final tone = dna['tone'] as String?;
        final narratorVoice = dna['narrator_voice'] as String?;

        if (opening != null && !validOpeningTypes.contains(opening)) {
          violations.add('$storyId: invalid opening_type "$opening"');
        }
        if (structure != null && !validStructureTypes.contains(structure)) {
          violations.add('$storyId: invalid structure_type "$structure"');
        }
        if (setting != null && !validSettingEmphasis.contains(setting)) {
          violations.add('$storyId: invalid setting_emphasis "$setting"');
        }
        if (archetype != null && !validArchetypes.contains(archetype)) {
          violations.add('$storyId: invalid character_archetype "$archetype"');
        }
        if (tone != null && !validTones.contains(tone)) {
          violations.add('$storyId: invalid tone "$tone"');
        }
        if (narratorVoice != null &&
            !validNarratorVoices.contains(narratorVoice)) {
          violations
              .add('$storyId: invalid narrator_voice "$narratorVoice"');
        }
      }

      if (violations.isNotEmpty) {
        // ignore: avoid_print
        print('\nSTORY DNA POOL VIOLATIONS:');
        for (final v in violations) {
          // ignore: avoid_print
          print('  - $v');
        }
      }

      expect(violations, isEmpty,
          reason: 'All storyDna fields must use valid pool values');
    });

    test('storyDna has all required sub-fields when present', () {
      final creativeDir = Directory('assets/stories/creative');
      if (!creativeDir.existsSync()) return;

      final violations = <String>[];

      for (final storyDir in creativeDir.listSync().whereType<Directory>()) {
        final storyId = storyDir.path.split('/').last;
        final metaFile = File('${storyDir.path}/meta_$storyId.json');
        if (!metaFile.existsSync()) continue;

        final meta =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        final dna = meta['storyDna'] as Map<String, dynamic>?;
        if (dna == null) continue;

        for (final field in requiredDnaFields) {
          if (!dna.containsKey(field) || dna[field] == null) {
            violations.add('$storyId: missing storyDna.$field');
          }
        }
      }

      if (violations.isNotEmpty) {
        // ignore: avoid_print
        print('\nSTORY DNA MISSING FIELDS:');
        for (final v in violations) {
          // ignore: avoid_print
          print('  - $v');
        }
      }

      expect(violations, isEmpty,
          reason: 'storyDna must have all required sub-fields when present');
    });

    test('storyDna is only present on creative stories', () {
      final traditionalDir = Directory('assets/stories/traditional');
      if (!traditionalDir.existsSync()) return;

      final violations = <String>[];

      for (final storyDir
          in traditionalDir.listSync().whereType<Directory>()) {
        final storyId = storyDir.path.split('/').last;
        final metaFile = File('${storyDir.path}/meta_$storyId.json');
        if (!metaFile.existsSync()) continue;

        final meta =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        if (meta.containsKey('storyDna')) {
          violations.add(
              '$storyId: traditional story has storyDna (should be creative only)');
        }
      }

      expect(violations, isEmpty,
          reason: 'Traditional stories must not have storyDna');
    });

    test('no 3+ consecutive creative stories share opening_type or structure_type',
        () {
      final creativeDir = Directory('assets/stories/creative');
      if (!creativeDir.existsSync()) return;

      // Collect all creative stories with storyDna, sorted by ID
      final storiesWithDna = <int, Map<String, dynamic>>{};

      for (final storyDir in creativeDir.listSync().whereType<Directory>()) {
        final storyId = storyDir.path.split('/').last;
        final metaFile = File('${storyDir.path}/meta_$storyId.json');
        if (!metaFile.existsSync()) continue;

        final meta =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        final dna = meta['storyDna'] as Map<String, dynamic>?;
        if (dna == null) continue;

        final id = int.tryParse(storyId);
        if (id != null) storiesWithDna[id] = dna;
      }

      if (storiesWithDna.length < 3) return; // Not enough data to check

      final sortedIds = storiesWithDna.keys.toList()..sort();
      final violations = <String>[];

      for (int i = 2; i < sortedIds.length; i++) {
        final dna0 = storiesWithDna[sortedIds[i - 2]]!;
        final dna1 = storiesWithDna[sortedIds[i - 1]]!;
        final dna2 = storiesWithDna[sortedIds[i]]!;

        final o0 = dna0['opening_type'];
        final o1 = dna1['opening_type'];
        final o2 = dna2['opening_type'];
        if (o0 == o1 && o1 == o2) {
          violations.add(
              'Stories ${sortedIds[i - 2]},${sortedIds[i - 1]},${sortedIds[i]}: '
              '3 consecutive opening_type="$o0"');
        }

        final s0 = dna0['structure_type'];
        final s1 = dna1['structure_type'];
        final s2 = dna2['structure_type'];
        if (s0 == s1 && s1 == s2) {
          violations.add(
              'Stories ${sortedIds[i - 2]},${sortedIds[i - 1]},${sortedIds[i]}: '
              '3 consecutive structure_type="$s0"');
        }
      }

      if (violations.isNotEmpty) {
        // ignore: avoid_print
        print('\nADJACENT REPETITION VIOLATIONS:');
        for (final v in violations) {
          // ignore: avoid_print
          print('  - $v');
        }
      }

      expect(violations, isEmpty,
          reason:
              'No 3+ consecutive creative stories should share opening_type or structure_type');
    });
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// CRITICAL: Validates all production meta.json files have correct
/// createdByModel per STORY_FACTORY.md dual-engine architecture (Section 0).
///
/// Only checks stories that appear in the production manifest (manifest.json).
/// Quarantined or orphaned stories on disk are ignored.
///
/// Engine policy (LOCKED per STORY_FACTORY.md Section 0):
///   Legacy Traditional (801-834)  → "gpt-4.1"
///   Legacy Creative (500s)        → mistral-nemo / llama3.1:8b / qwen2.5:7b / gemma:7b
///   Opus 4.6 batch (1000-1120)    → "claude-opus-4-6"
///   Opus 4.7 batch (1121+)        → "claude-opus-4-7"
void main() {
  group('CRITICAL: Story Engine Compliance (STORY_FACTORY.md)', () {
    test('all production meta.json files have correct createdByModel', () {
      final storiesDir = Directory('assets/stories');
      final violations = <String>[];

      // Build set of production story directories from manifest
      final manifestFile = File('assets/stories/manifest.json');
      expect(manifestFile.existsSync(), isTrue,
          reason: 'manifest.json must exist');
      final manifest =
          jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
      final parables = manifest['parables'] as List;

      // Extract unique base story directories from manifest
      final productionStories = <String>{};
      for (final p in parables) {
        final textPath = p['textFilePath'] as String?;
        if (textPath == null) continue;
        final parts = textPath.split('/');
        if (parts.length >= 2) {
          productionStories.add('${parts[0]}/${parts[1]}');
        }
      }

      for (final modeDir in ['creative', 'traditional']) {
        final dir = Directory('${storiesDir.path}/$modeDir');
        if (!dir.existsSync()) continue;

        for (final storyDir in dir.listSync().whereType<Directory>()) {
          final storyId = storyDir.path.split('/').last;
          final relPath = '$modeDir/$storyId';

          // Skip stories not in the production manifest
          if (!productionStories.contains(relPath)) continue;

          final metaFile = File('${storyDir.path}/meta_$storyId.json');
          if (!metaFile.existsSync()) continue;

          final meta =
              jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
          final mode = meta['mode'] as String? ?? modeDir;
          final model = meta['createdByModel'] as String? ?? 'MISSING';

          // STORY_FACTORY.md: dual-engine architecture
          //   Legacy Traditional (801-834): gpt-4.1
          //   Legacy Creative (500s): mistral-nemo / llama3.1:8b / qwen2.5:7b / gemma:7b
          //   Opus 4.6 batch (1000-1120): claude-opus-4-6
          //   Opus 4.7 batch (1121+): claude-opus-4-7 (added 2026-05; 1M-context model now in active use)
          const traditionalAllowedModels = {
            'gpt-4.1',           // legacy traditional engine
            'claude-opus-4-6',   // Opus 4.6 batch system
            'claude-opus-4-7',   // Opus 4.7 batch system (1M context, active model)
          };
          const creativeAllowedModels = {
            'mistral-nemo',      // primary (via Ollama)
            'llama3.1:8b',       // fallback 1
            'qwen2.5:7b',        // fallback 2
            'gemma:7b',          // legacy fallback
            'claude-opus-4-6',   // Opus 4.6 batch system
            'claude-opus-4-7',   // Opus 4.7 batch system (1M context, active model)
          };

          if (mode == 'traditional') {
            if (!traditionalAllowedModels.contains(model)) {
              violations.add(
                '$mode/$storyId: createdByModel="$model" '
                '(expected one of: ${traditionalAllowedModels.join(", ")})',
              );
            }
          } else {
            if (!creativeAllowedModels.contains(model)) {
              violations.add(
                '$mode/$storyId: createdByModel="$model" '
                '(expected one of: ${creativeAllowedModels.join(", ")})',
              );
            }
          }
        }
      }

      if (violations.isNotEmpty) {
        // ignore: avoid_print
        print('\nENGINE COMPLIANCE VIOLATIONS (STORY_FACTORY.md Section 0):');
        for (final v in violations) {
          // ignore: avoid_print
          print('  - $v');
        }
      }

      expect(violations, isEmpty,
          reason:
              'All production meta.json files must have correct createdByModel '
              'per STORY_FACTORY.md dual-engine architecture');
    });
  });
}

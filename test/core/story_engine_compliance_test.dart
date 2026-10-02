import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _campaignAuthorModels = {
  'gpt-5.6-sol', // ADR-036
  'gpt-5', // ADR-037
  'openai-codex-gpt-5', // ADR-037
};

bool _isSanctionedCampaignAuthor(String modeDir, int? storyId, String model) {
  // ADR-036/ADR-037: Traditional campaign IDs only; independent review remains
  // required.
  return modeDir == 'traditional' &&
      _campaignAuthorModels.contains(model) &&
      storyId != null &&
      storyId >= 3000 &&
      storyId <= 3258;
}

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
          //   Opus 4.8 batch (1543, 1552-1561): claude-opus-4-8 (added 2026-06)
          //   Fable 5 batch (1571-1610): claude-fable-5 (added 2026-07; TEXT-FIRST STORY FACTORY 2.0 pilot)
          //   Opus 5 batch (1611+): claude-opus-5 (added 2026-08-01; current active model)
          const traditionalAllowedModels = {
            'gpt-4.1',           // legacy traditional engine
            'claude-opus-4-6',   // Opus 4.6 batch system
            'claude-opus-4-7',   // Opus 4.7 batch system (1M context)
            'claude-opus-4-8',   // Opus 4.8 batch system (2026-06)
            'claude-fable-5',    // Fable 5 batch system (2026-07; TFSF 2.0 pilot, stories 1571-1610)
            'claude-opus-5',     // Opus 5 (1M context) — current active model, sanctioned by
                                 // Adam 2026-08-01 for the text-first batch beginning at 1611
            'openai_chatgpt',    // cross-author experiment (Batch 17, story 1470 only;
                                 // commit 7c64b38 — first cross-author batch in corpus)
          };
          const creativeAllowedModels = {
            'mistral-nemo',      // primary (via Ollama)
            'llama3.1:8b',       // fallback 1
            'qwen2.5:7b',        // fallback 2
            'gemma:7b',          // legacy fallback
            'claude-opus-4-6',   // Opus 4.6 batch system
            'claude-opus-4-7',   // Opus 4.7 batch system (1M context)
            'claude-opus-4-8',   // Opus 4.8 batch system (current active model, 2026-06)
          };

          if (mode == 'traditional') {
            if (!traditionalAllowedModels.contains(model) &&
                !_isSanctionedCampaignAuthor(
                    modeDir, int.tryParse(storyId), model)) {
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

    test(
        'Packet 009 Traditional author metadata uses sanctioned campaign model',
        () {
      for (var storyId = 3035; storyId <= 3039; storyId++) {
        final metaFile =
            File('assets/stories/traditional/$storyId/meta_$storyId.json');
        expect(metaFile.existsSync(), isTrue);
        final meta =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        expect(meta['mode'], 'traditional', reason: 'story $storyId');
        expect(meta['createdByModel'], 'gpt-5.6-sol', reason: 'story $storyId');
        expect(
            _isSanctionedCampaignAuthor(
                'traditional', storyId, meta['createdByModel'] as String),
            isTrue,
            reason: 'story $storyId');
      }
    });

    test('campaign author exception stays within Traditional IDs 3000-3258',
        () {
      expect(_isSanctionedCampaignAuthor('traditional', 3000, 'gpt-5.6-sol'),
          isTrue);
      expect(_isSanctionedCampaignAuthor('traditional', 3258, 'gpt-5.6-sol'),
          isTrue);
      expect(_isSanctionedCampaignAuthor('traditional', 2999, 'gpt-5.6-sol'),
          isFalse);
      expect(_isSanctionedCampaignAuthor('traditional', 3259, 'gpt-5.6-sol'),
          isFalse);
      expect(_isSanctionedCampaignAuthor('creative', 3035, 'gpt-5.6-sol'),
          isFalse);
    });

    test(
        'Packet 012 Traditional author metadata uses sanctioned campaign model',
        () {
      for (var storyId = 3050; storyId <= 3054; storyId++) {
        final metaFile =
            File('assets/stories/traditional/$storyId/meta_$storyId.json');
        expect(metaFile.existsSync(), isTrue);
        final meta =
            jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
        expect(meta['mode'], 'traditional', reason: 'story $storyId');
        expect(meta['createdByModel'], 'gpt-5', reason: 'story $storyId');
        expect(
            _isSanctionedCampaignAuthor(
                'traditional', storyId, meta['createdByModel'] as String),
            isTrue,
            reason: 'story $storyId');
      }
    });

    test(
        'ADR-037 campaign author models stay within Traditional IDs 3000-3258',
        () {
      for (final model in ['gpt-5', 'openai-codex-gpt-5']) {
        expect(_isSanctionedCampaignAuthor('traditional', 3000, model), isTrue,
            reason: model);
        expect(_isSanctionedCampaignAuthor('traditional', 3258, model), isTrue,
            reason: model);
        expect(_isSanctionedCampaignAuthor('traditional', 2999, model), isFalse,
            reason: model);
        expect(_isSanctionedCampaignAuthor('traditional', 3259, model), isFalse,
            reason: model);
        expect(_isSanctionedCampaignAuthor('creative', 3050, model), isFalse,
            reason: model);
        // Non-numeric story directory: int.tryParse yields null.
        expect(
            _isSanctionedCampaignAuthor(
                'traditional', int.tryParse('3050_draft'), model),
            isFalse,
            reason: model);
      }
    });
  });
}

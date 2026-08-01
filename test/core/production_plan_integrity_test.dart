import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Recurrence guard for the two authoritative production-planning files:
///   - assets/stories/canon_production_gate.json   (near-term story production)
///   - assets/stories/journey_gap_backlog.json     (Journey Beat continuity)
///
/// Both files are self-described "what to produce next" inputs. On 2026-07-31 a
/// readiness audit found every one of the gate's 22 approved candidates still
/// marked `not_started` and backlog items G1-G10 still marked `planned`, months
/// after all of them had been authored and registered. Consuming either file
/// as-is would have instructed ~33 duplicate stories.
///
/// This test makes that class of drift fail the build. It is deliberately
/// EXACT: every assertion reads an explicit status or story-ID field. There is
/// no Scripture parsing, no verse-range arithmetic and no similarity
/// heuristic — it is not a duplicate detector, it only checks that a plan's
/// recorded completion state agrees with manifest.json.
void main() {
  group('Production plan integrity', () {
    late Map<String, dynamic> gate;
    late Map<String, dynamic> backlog;

    /// numbered story id -> the manifest entries that belong to it
    late Map<int, List<Map<String, dynamic>>> manifestByStoryId;

    /// Gate statuses that mean "this story has NOT been written yet", so an
    /// item carrying one of them must not also claim a produced story.
    const notYetProducedGateStatuses = <String>{
      'not_started',
      'drafting',
    };

    /// Backlog statuses that mean the same thing.
    const notYetProducedBacklogStatuses = <String>{
      'missing',
      'planned',
      'intentionally_deferred',
    };

    /// Backlog statuses that mean the story exists.
    const producedBacklogStatuses = <String>{
      'authored',
      'integrated',
    };

    Map<String, dynamic> readJson(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path must exist');
      return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    }

    setUpAll(() {
      gate = readJson('assets/stories/canon_production_gate.json');
      backlog = readJson('assets/stories/journey_gap_backlog.json');

      final manifest = readJson('assets/stories/manifest.json');
      final parables = (manifest['parables'] as List).cast<Map<String, dynamic>>();
      manifestByStoryId = <int, List<Map<String, dynamic>>>{};
      final idPattern = RegExp(r'^story_(\d+)_');
      for (final entry in parables) {
        final match = idPattern.firstMatch(entry['storyId'] as String? ?? '');
        if (match == null) continue;
        manifestByStoryId
            .putIfAbsent(int.parse(match.group(1)!), () => <Map<String, dynamic>>[])
            .add(entry);
      }
      expect(manifestByStoryId, isNotEmpty,
          reason: 'manifest.json must contain numbered story entries');
    });

    /// Asserts that [productionId] names a real numbered story in
    /// manifest.json whose recorded anchor and bibleStoryKey are exactly the
    /// ones the plan claims.
    List<String> verifyProducedStory({
      required String label,
      required Object? productionId,
      required Object? productionAnchor,
      required Object? productionBibleStoryKey,
    }) {
      final violations = <String>[];

      if (productionId is! int) {
        violations.add('$label: productionId must be an int, got $productionId');
        return violations;
      }
      if (productionAnchor is! String || productionAnchor.trim().isEmpty) {
        violations.add('$label: productionAnchor missing/empty');
      }
      if (productionBibleStoryKey is! String ||
          productionBibleStoryKey.trim().isEmpty) {
        violations.add('$label: productionBibleStoryKey missing/empty');
      }
      if (violations.isNotEmpty) return violations;

      final entries = manifestByStoryId[productionId];
      if (entries == null || entries.isEmpty) {
        violations.add(
            '$label: productionId $productionId has no entry in manifest.json');
        return violations;
      }

      for (final entry in entries) {
        final id = entry['storyId'];
        final ref = entry['bibleSourceRef'];
        final key = entry['bibleStoryKey'];
        if (ref != productionAnchor) {
          violations.add('$label: productionAnchor "$productionAnchor" != '
              'manifest bibleSourceRef "$ref" ($id)');
        }
        if (key != productionBibleStoryKey) {
          violations.add(
              '$label: productionBibleStoryKey "$productionBibleStoryKey" != '
              'manifest bibleStoryKey "$key" ($id)');
        }
      }
      return violations;
    }

    // ── canon_production_gate.json ──────────────────────────────────────────

    test('gate: every productionStatus is in the declared vocabulary', () {
      final vocabulary =
          (gate['_meta']['productionStatusVocabulary'] as List).cast<String>();
      final violations = <String>[];
      for (final raw in gate['approvedCandidates'] as List) {
        final candidate = raw as Map<String, dynamic>;
        final status = candidate['productionStatus'];
        if (!vocabulary.contains(status)) {
          violations.add('${candidate['id']}: productionStatus "$status" is not '
              'in productionStatusVocabulary $vocabulary');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('gate: every candidate carrying a productionId resolves to its real story',
        () {
      final violations = <String>[];
      for (final raw in gate['approvedCandidates'] as List) {
        final candidate = raw as Map<String, dynamic>;
        // Skip only the statuses that mean "not written yet" — those are
        // covered by the unstarted-candidate test below. Every other status
        // (awaiting_approval, approved_for_audio, rendered, integrated) means
        // a story exists, so its recorded ID/anchor/key must agree with
        // manifest.json. Checking only `integrated` let a mid-pipeline
        // candidate drift unverified — the exact failure this guard exists
        // to prevent.
        if (notYetProducedGateStatuses.contains(candidate['productionStatus'])) {
          continue;
        }
        violations.addAll(verifyProducedStory(
          label: 'gate ${candidate['id']}',
          productionId: candidate['productionId'],
          productionAnchor: candidate['productionAnchor'],
          productionBibleStoryKey: candidate['productionBibleStoryKey'],
        ));
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('gate: an unstarted candidate carries no produced story', () {
      final violations = <String>[];
      for (final raw in gate['approvedCandidates'] as List) {
        final candidate = raw as Map<String, dynamic>;
        if (!notYetProducedGateStatuses.contains(candidate['productionStatus'])) {
          continue;
        }
        for (final field in const [
          'productionId',
          'productionAnchor',
          'productionBibleStoryKey',
        ]) {
          if (candidate[field] != null) {
            violations.add('${candidate['id']}: productionStatus is '
                '"${candidate['productionStatus']}" but $field is set to '
                '"${candidate[field]}" — refresh the status or drop the field');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('gate: summary counts match the entries', () {
      final candidates = (gate['approvedCandidates'] as List)
          .cast<Map<String, dynamic>>();
      final counts = gate['_meta']['counts'] as Map<String, dynamic>;
      final integrated = candidates
          .where((c) => c['productionStatus'] == 'integrated')
          .length;

      expect(counts['approvedCandidates'], candidates.length,
          reason: '_meta.counts.approvedCandidates must equal the number of '
              'approvedCandidates entries');
      expect(counts['integratedCandidates'], integrated,
          reason: '_meta.counts.integratedCandidates must equal the number of '
              'candidates with productionStatus=integrated');
      expect(counts['overturnedFindings'], (gate['overturnedFindings'] as List).length,
          reason: '_meta.counts.overturnedFindings must match the entries');
      expect(counts['deferredNotable'], (gate['deferredNotable'] as List).length,
          reason: '_meta.counts.deferredNotable must match the entries');
    });

    // ── journey_gap_backlog.json ────────────────────────────────────────────

    test('backlog: every status is in the declared vocabulary', () {
      final vocabulary =
          (backlog['_meta']['statusVocabulary'] as Map<String, dynamic>).keys.toSet();
      final violations = <String>[];
      for (final raw in backlog['backlog'] as List) {
        final item = raw as Map<String, dynamic>;
        final status = item['status'];
        if (!vocabulary.contains(status)) {
          violations.add('${item['id']}: status "$status" is not in '
              'statusVocabulary $vocabulary');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('backlog: every authored/integrated item resolves to its real story', () {
      final violations = <String>[];
      for (final raw in backlog['backlog'] as List) {
        final item = raw as Map<String, dynamic>;
        if (!producedBacklogStatuses.contains(item['status'])) continue;
        violations.addAll(verifyProducedStory(
          label: 'backlog ${item['id']}',
          productionId: item['productionId'],
          productionAnchor: item['productionAnchor'],
          productionBibleStoryKey: item['productionBibleStoryKey'],
        ));
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('backlog: an unfilled gap carries no produced story', () {
      final violations = <String>[];
      for (final raw in backlog['backlog'] as List) {
        final item = raw as Map<String, dynamic>;
        if (!notYetProducedBacklogStatuses.contains(item['status'])) continue;
        for (final field in const [
          'productionId',
          'productionAnchor',
          'productionBibleStoryKey',
        ]) {
          if (item[field] != null) {
            violations.add('${item['id']}: status is "${item['status']}" but '
                '$field is set to "${item[field]}" — refresh the status or drop '
                'the field');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('backlog: no already-produced gap is still queued for production', () {
      final produced = <String>{
        for (final raw in backlog['backlog'] as List)
          if ((raw as Map<String, dynamic>)['productionId'] != null)
            raw['id'] as String,
      };
      final fillPriority = backlog['_meta']['fillPriority'] as Map<String, dynamic>;
      final violations = <String>[];
      for (final listName in const [
        'fillNow',
        'stronglyConsider',
        'deferUntilArcApproached',
      ]) {
        for (final id in (fillPriority[listName] as List).cast<String>()) {
          if (produced.contains(id)) {
            violations.add('$id has a productionId but is still listed in '
                '_meta.fillPriority.$listName — producing it again would '
                'duplicate an existing story');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    // ── cross-file ──────────────────────────────────────────────────────────

    test('gate mirrors the backlog fill order', () {
      final mirror =
          gate['_meta']['journeyBacklogReference'] as Map<String, dynamic>;
      final source = backlog['_meta']['fillPriority'] as Map<String, dynamic>;
      for (final listName in const [
        'fillNow',
        'stronglyConsider',
        'deferUntilArcApproached',
      ]) {
        expect((mirror[listName] as List).cast<String>(),
            (source[listName] as List).cast<String>(),
            reason: 'canon_production_gate.json _meta.journeyBacklogReference.'
                '$listName must mirror journey_gap_backlog.json '
                '_meta.fillPriority.$listName');
      }
    });
  });
}

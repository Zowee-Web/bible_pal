import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/pal_memory_line.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_templates.dart';

/// Observation-only audit for the PAL memory template registry.
/// See docs/PAL_MEMORY_DOCTRINE.md.
///
/// Templates are allowed to describe what the user *did* (sat with,
/// spent time with, listened to). They are NOT allowed to claim what
/// the user *felt* or *understood* (carrying, struggling, found
/// comfort, wrestled, lately, ...). The doctrine's observation-vs-
/// inference boundary is the load-bearing rule that keeps memory
/// trustworthy; this audit makes future template additions defend
/// themselves against it.
///
/// Slice 2c.2 update: templates are now typed [PalMemoryTemplateVariant]
/// objects with a [carrierClipId] that maps to a pre-rendered audio
/// fragment. End-placeholder structure only, so audio delivery is a
/// clean carrier-then-name stitch. New verbs require explicit editorial
/// review — extend the blocklist rather than weakening it.
void main() {
  // Verbs / phrases that claim the user's interior state. Adding a new
  // template that contains any of these MUST trip this audit so it
  // can't ship without a human deliberately deciding to widen the rule.
  const blockedInferenceFragments = <String>[
    'carrying',
    'carried',
    'struggling',
    'struggled',
    'wrestled',
    'wrestling',
    'feeling',
    'felt',
    'lately',
    'in a season',
    'found comfort',
    'spoke to you',
    'sense',
    'know how you',
    'must have',
    'must be',
    'going through',
  ];

  group('observation-only audit', () {
    test('every variant\'s fullTemplate contains the {storyName} placeholder',
        () {
      for (final v in PalMemoryTemplates.all()) {
        expect(v.fullTemplate,
            contains(PalMemoryTemplates.storyNamePlaceholder),
            reason:
                'Variant "${v.carrierClipId}" fullTemplate is missing the '
                'placeholder. Memory lines must be grounded in a specific session.');
      }
    });

    test('no variant\'s carrierText contains a blocked inference word', () {
      for (final v in PalMemoryTemplates.all()) {
        final lower = v.carrierText.toLowerCase();
        for (final fragment in blockedInferenceFragments) {
          expect(
            lower.contains(fragment),
            isFalse,
            reason:
                'Variant "${v.carrierClipId}" carrierText "${v.carrierText}" '
                'contains inference fragment "$fragment". Slice 2a templates '
                'must stay observational — see docs/PAL_MEMORY_DOCTRINE.md, '
                'Observation vs Inference.',
          );
        }
      }
    });

    test('every recency band has at least 2 wording variants', () {
      // Variance protects against the line calcifying into a tic. The
      // doctrine's Slice 2 craft brief calls for 3–4 variants per band;
      // floor here is 2 so future template churn still gets caught.
      for (final band in RecencyBand.values) {
        final variants = PalMemoryTemplates.variantsFor(band);
        expect(variants.length, greaterThanOrEqualTo(2),
            reason:
                'Band $band has only ${variants.length} variant(s). '
                'At least 2 are required to avoid a single calcified line.');
      }
    });

    test('templates align with their band (sanity check on wording)', () {
      for (final v in PalMemoryTemplates.variantsFor(RecencyBand.yesterday)) {
        expect(v.carrierText.toLowerCase(), contains('yesterday'),
            reason:
                '"yesterday" band variant carrierText missing the word: '
                '"${v.carrierText}" (clipId ${v.carrierClipId})');
      }
      for (final v
          in PalMemoryTemplates.variantsFor(RecencyBand.fewDaysAgo)) {
        expect(v.carrierText.toLowerCase(), contains('few days ago'),
            reason:
                '"fewDaysAgo" band variant carrierText missing the phrase: '
                '"${v.carrierText}" (clipId ${v.carrierClipId})');
      }
      for (final v in PalMemoryTemplates
          .variantsFor(RecencyBand.earlierThisWeek)) {
        expect(v.carrierText.toLowerCase(), contains('earlier this week'),
            reason:
                '"earlierThisWeek" band variant carrierText missing the '
                'phrase: "${v.carrierText}" (clipId ${v.carrierClipId})');
      }
    });
  });

  group('carrierClipId integrity', () {
    test('every carrierClipId is filesystem-safe', () {
      final safe = RegExp(r'^[a-z0-9_]+$');
      for (final v in PalMemoryTemplates.all()) {
        expect(safe.hasMatch(v.carrierClipId), isTrue,
            reason:
                'carrierClipId "${v.carrierClipId}" must be lowercase '
                'alphanumeric + underscores only — it maps to an MP3 filename.');
      }
    });

    test('all carrierClipIds are unique across the registry', () {
      final ids = PalMemoryTemplates.all().map((v) => v.carrierClipId).toList();
      expect(ids.length, ids.toSet().length,
          reason:
              'Duplicate carrierClipIds would let two variants share the same '
              'audio file, hiding either a real wording difference or a '
              'copy-paste mistake.');
    });

    test('every carrierClipId starts with "carrier_"', () {
      for (final v in PalMemoryTemplates.all()) {
        expect(v.carrierClipId.startsWith('carrier_'), isTrue,
            reason:
                'carrierClipId "${v.carrierClipId}" should start with '
                '"carrier_" so the audio inventory validator can pattern-match '
                'memory carrier clips vs other PAL audio.');
      }
    });
  });
}

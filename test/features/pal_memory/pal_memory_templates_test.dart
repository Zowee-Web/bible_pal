import 'package:flutter_test/flutter_test.dart';

import 'package:bible_pal/features/pal_memory/pal_memory_line.dart';
import 'package:bible_pal/features/pal_memory/pal_memory_templates.dart';

/// Observation-only audit for the PAL memory template registry.
/// See docs/PAL_MEMORY_DOCTRINE.md.
///
/// Templates are allowed to describe what the user *did* (sat with,
/// spent time with, "I remember"). They are NOT allowed to claim what
/// the user *felt* or *understood* (carrying, struggling, found
/// comfort, wrestled, lately, ...). The doctrine's observation-vs-
/// inference boundary is the load-bearing rule that keeps memory
/// trustworthy; this audit makes future template additions defend
/// themselves against it.
///
/// New verbs require explicit editorial review — extend the blocklist
/// here rather than weakening it.
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
    test('every template contains the {storyName} placeholder', () {
      for (final t in PalMemoryTemplates.all()) {
        expect(t, contains('{storyName}'),
            reason: 'Template "$t" is missing the {storyName} placeholder. '
                'Memory lines must be grounded in a specific session.');
      }
    });

    test('no template contains a blocked inference word or phrase', () {
      for (final t in PalMemoryTemplates.all()) {
        final lower = t.toLowerCase();
        for (final fragment in blockedInferenceFragments) {
          expect(
            lower.contains(fragment),
            isFalse,
            reason:
                'Template "$t" contains inference fragment "$fragment". '
                'Slice 2a templates must stay observational — see '
                'docs/PAL_MEMORY_DOCTRINE.md, Observation vs Inference.',
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
      for (final t in PalMemoryTemplates.variantsFor(RecencyBand.yesterday)) {
        expect(t.toLowerCase(), contains('yesterday'),
            reason: '"yesterday" band template missing the word: "$t"');
      }
      for (final t
          in PalMemoryTemplates.variantsFor(RecencyBand.fewDaysAgo)) {
        expect(t.toLowerCase(), contains('few days ago'),
            reason: '"fewDaysAgo" band template missing the phrase: "$t"');
      }
      for (final t
          in PalMemoryTemplates.variantsFor(RecencyBand.earlierThisWeek)) {
        expect(t.toLowerCase(), contains('earlier this week'),
            reason:
                '"earlierThisWeek" band template missing the phrase: "$t"');
      }
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/service_providers.dart';

/// Beta-only Journey testing controls (JOURNEY_TESTING_ENABLED).
///
/// Lives inside the diagnostics screen and is only inserted when the
/// compile flag is set (`kJourneyTestingEnabled`), so it never ships to
/// end users. Lets a tester:
///  - collapse the 3-day continuation cooldown to seconds (cadence),
///  - reset the cooldown so the next PAL tap is eligible,
///  - seed a Daniel-arc source session so the cascade has something to
///    offer on a fresh device.
///
/// Journey telemetry (pal_journey_offer_fired / _accepted / _declined /
/// _skipped) appears in the breadcrumb list below this panel. While a
/// cadence override is active, those events carry `synthetic_session:
/// true` so panel-driven runs are excluded from baseline metrics.
class JourneyTestingPanel extends ConsumerStatefulWidget {
  const JourneyTestingPanel({super.key});

  @override
  ConsumerState<JourneyTestingPanel> createState() =>
      _JourneyTestingPanelState();
}

class _JourneyTestingPanelState extends ConsumerState<JourneyTestingPanel> {
  // (label, cadence): null = production 3-day gate; Duration.zero =
  // disabled (always eligible). Every value is <= 3d, the range the
  // storage-shift override is correct for.
  static const List<(String, Duration?)> _options = [
    ('Prod 3d', null),
    ('24h', Duration(hours: 24)),
    ('1h', Duration(hours: 1)),
    ('5m', Duration(minutes: 5)),
    ('Off', Duration.zero),
  ];

  // (label, story-0 sid, isKid). Seeding arms the arc so the next PAL tap
  // offers its beat. Adult sids match story_<N>_...; kid sids match
  // kidstory_kid_<anchor>_<length>. Kid arcs only fire in kid mode.
  static const List<(String, String, bool)> _journeys = [
    ('Daniel', 'story_1486_brave_courage_full_traditional', false),
    ('Joseph', 'story_1037_brave_courage_full_traditional', false),
    ('Ruth', 'story_828_brave_courage_full_traditional', false),
    ('Elijah', 'story_1039_brave_courage_full_traditional', false),
    // Scale-Horizon per-story continuation arcs (outgoing_beats.json).
    // Seeding story-0 arms the offer to the next-in-arc story:
    //   David 1022 → 1112 · Moses 1033 → 1019 · Moses 1135 → 1561.
    ('David (1022→1112)', 'story_1022_joyful_short_traditional', false),
    ('Moses·Deliverance (1033→1019)',
        'story_1033_brave_courage_short_traditional', false),
    // Mid-arc seed: source = 1019 (arc index 1), so the offer targets
    // 1527 — the bare-accept repro case before the framing clips landed.
    ('Moses·Bush→Sea (1019→1527)',
        'story_1019_encouraging_short_traditional', false),
    ('Moses·Mountain (1135→1561)',
        'story_1135_encouraging_short_traditional', false),
    ('Kid Moses', 'kidstory_kid_baby_moses_short', true),
    ('Kid Joseph', 'kidstory_kid_joseph_coat_short', true),
  ];

  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _loadCadence();
  }

  Future<void> _loadCadence() async {
    final store = await ref.read(palSessionStoreProvider.future);
    final current = await store.getJourneyCadenceOverride();
    if (!mounted) return;
    var idx = _options.indexWhere((o) => o.$2 == current);
    if (idx < 0) idx = 0;
    setState(() => _selected = idx);
  }

  Future<void> _setCadence(int i) async {
    final store = await ref.read(palSessionStoreProvider.future);
    await store.setJourneyCadenceOverride(_options[i].$2);
    if (!mounted) return;
    setState(() => _selected = i);
    _snack('Cadence: ${_options[i].$1}');
  }

  Future<void> _clearCooldown() async {
    final store = await ref.read(palSessionStoreProvider.future);
    await store.clearJourneyCooldownOnly();
    if (!mounted) return;
    _snack('Cooldown cleared — next tap eligible');
  }

  Future<void> _seedJourney(String label, String storyId, bool isKid) async {
    final store = await ref.read(palSessionStoreProvider.future);
    await store.seedJourneySourceSession(storyId);
    await store.clearJourneyCooldownOnly();
    if (!mounted) return;
    _snack(isKid
        ? 'Seeded $label — switch to kid mode, then tap the orb'
        : 'Seeded $label — tap the orb to hear its beat');
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      color: Colors.purple.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Journey Testing',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.purple,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Continuation cooldown',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 0; i < _options.length; i++)
                ChoiceChip(
                  label: Text(_options[i].$1),
                  selected: _selected == i,
                  onSelected: (_) => _setCadence(i),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _clearCooldown,
              icon: const Icon(Icons.timer_off, size: 16),
              label: const Text('Clear cooldown (keeps sessions)'),
              style: OutlinedButton.styleFrom(foregroundColor: Colors.purple),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Seed a journey (arms the arc + clears cooldown)',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final j in _journeys)
                ActionChip(
                  label: Text(j.$1),
                  avatar: const Icon(Icons.add, size: 14),
                  onPressed: () => _seedJourney(j.$1, j.$2, j.$3),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Then tap the PAL orb. Events show in the breadcrumbs below. '
            'Kid arcs need kid mode.',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

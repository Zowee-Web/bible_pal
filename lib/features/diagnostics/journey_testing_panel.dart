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

  Future<void> _seedDaniel() async {
    final store = await ref.read(palSessionStoreProvider.future);
    await store.seedDanielArcSession();
    if (!mounted) return;
    _snack('Seeded Daniel 1 — orb will offer Daniel 3');
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
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
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _clearCooldown,
                  icon: const Icon(Icons.timer_off, size: 16),
                  label: const Text('Clear cooldown'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _seedDaniel,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Seed Daniel'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Journey events appear in the breadcrumbs below.',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

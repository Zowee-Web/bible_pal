import 'package:flutter/services.dart' show AssetManifest, rootBundle;

import 'journey.dart';

/// One hit when looking up a session's journey membership. Carries
/// the journey itself plus the story's 0-based index in that
/// journey's [Journey.stories] list — the engine needs the index to
/// pick the next-in-journey story.
class JourneyMembership {
  final Journey journey;
  final int storyIndex;
  const JourneyMembership(this.journey, this.storyIndex);
}

/// Holds every loaded journey + lookup indices into them.
///
/// Journey Doctrine, Slice 2 (docs/JOURNEY_DOCTRINE.md): only
/// [JourneyStatus.ready] journeys are exposed to the engine. [held]
/// and [draft] journeys are loaded for editorial visibility but
/// filtered out at the public API surface so a held journey can never
/// fire by accident.
class JourneyRegistry {
  /// Every loaded journey, in load order. Curator-facing — includes
  /// held/draft. The engine should use [readyJourneys] / [lookupBy*]
  /// instead.
  final List<Journey> allJourneys;

  final Map<String, Journey> _byJourneyId;
  final Map<int, JourneyMembership> _adultByStoryNumber;
  final Map<String, JourneyMembership> _kidByAnchorId;

  JourneyRegistry._({
    required this.allJourneys,
    required Map<String, Journey> byJourneyId,
    required Map<int, JourneyMembership> adultByStoryNumber,
    required Map<String, JourneyMembership> kidByAnchorId,
  })  : _byJourneyId = byJourneyId,
        _adultByStoryNumber = adultByStoryNumber,
        _kidByAnchorId = kidByAnchorId;

  /// Asset directory prefix used by [load] when scanning
  /// AssetManifest.
  static const String _assetPrefix = 'assets/stories/journeys/';

  /// Production loader — scans the asset bundle for every
  /// `assets/stories/journeys/*.json` and constructs a registry.
  /// Call once at app launch; hold the result for the session.
  static Future<JourneyRegistry> load() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest
        .listAssets()
        .where((p) => p.startsWith(_assetPrefix) && p.endsWith('.json'))
        .toList()
      ..sort(); // deterministic load order
    final raw = <String>[];
    for (final p in paths) {
      raw.add(await rootBundle.loadString(p));
    }
    return JourneyRegistry.fromJsonStrings(raw);
  }

  /// Pure factory — used by tests + any caller that wants to inject
  /// fixture JSON instead of reading from the asset bundle.
  factory JourneyRegistry.fromJsonStrings(List<String> jsonStrings) {
    final journeys = jsonStrings.map(Journey.fromJsonString).toList();
    return JourneyRegistry.fromJourneys(journeys);
  }

  /// Lowest-level factory — builds indices over a pre-parsed list of
  /// journeys. Validates journeyId uniqueness; ready-journey story
  /// references are NOT cross-checked against the manifest here
  /// (that's the schema validator test's job at CI time).
  factory JourneyRegistry.fromJourneys(List<Journey> journeys) {
    final byJourneyId = <String, Journey>{};
    final adultByStoryNumber = <int, JourneyMembership>{};
    final kidByAnchorId = <String, JourneyMembership>{};

    for (final j in journeys) {
      if (byJourneyId.containsKey(j.journeyId)) {
        throw StateError(
            'Duplicate journeyId "${j.journeyId}" — journeyId must be globally unique');
      }
      byJourneyId[j.journeyId] = j;

      // Only ready journeys are indexed for lookup. Held/draft are
      // visible via [allJourneys] but never surfaced to the engine.
      if (j.status != JourneyStatus.ready) continue;

      for (var i = 0; i < j.stories.length; i++) {
        final s = j.stories[i];
        if (j.lane == JourneyLane.adult) {
          final n = s.storyNumber;
          if (n == null) {
            throw StateError(
                'Adult journey "${j.journeyId}" story[$i] missing storyNumber');
          }
          if (adultByStoryNumber.containsKey(n)) {
            // Slice 2 sealed-lanes: each adult story belongs to at
            // most one ready journey. Slice 3 will introduce
            // multi-membership + primaryJourney arbitration.
            final existing = adultByStoryNumber[n]!.journey.journeyId;
            throw StateError(
                'Slice 2 sealed-lanes violation: storyNumber=$n is in BOTH '
                '"$existing" and "${j.journeyId}". Use primaryJourney field '
                'on the story manifest entry when Slice 3 lands; for now, '
                'each story can be in at most one ready journey.');
          }
          adultByStoryNumber[n] = JourneyMembership(j, i);
        } else {
          final a = s.anchorId;
          if (a == null) {
            throw StateError(
                'Kid journey "${j.journeyId}" story[$i] missing anchorId');
          }
          if (kidByAnchorId.containsKey(a)) {
            final existing = kidByAnchorId[a]!.journey.journeyId;
            throw StateError(
                'Slice 2 sealed-lanes violation: kid anchorId="$a" is in BOTH '
                '"$existing" and "${j.journeyId}"');
          }
          kidByAnchorId[a] = JourneyMembership(j, i);
        }
      }
    }

    return JourneyRegistry._(
      allJourneys: List<Journey>.unmodifiable(journeys),
      byJourneyId: byJourneyId,
      adultByStoryNumber: adultByStoryNumber,
      kidByAnchorId: kidByAnchorId,
    );
  }

  /// Every journey with status==ready, in load order. Engine uses
  /// these.
  Iterable<Journey> get readyJourneys =>
      allJourneys.where((j) => j.status == JourneyStatus.ready);

  /// Journey by id, including held/draft. Returns null if no journey
  /// with that id exists.
  Journey? lookupJourney(String journeyId) => _byJourneyId[journeyId];

  /// Find which READY adult journey contains [storyNumber], plus the
  /// story's index in that journey. Returns null if no ready
  /// journey claims it.
  JourneyMembership? lookupAdultByStoryNumber(int storyNumber) =>
      _adultByStoryNumber[storyNumber];

  /// Find which READY kid journey contains [anchorId], plus the
  /// story's index. Returns null if no ready kid journey claims it.
  JourneyMembership? lookupKidByAnchorId(String anchorId) =>
      _kidByAnchorId[anchorId];

  int get readyJourneyCount =>
      allJourneys.where((j) => j.status == JourneyStatus.ready).length;

  int get totalJourneyCount => allJourneys.length;
}

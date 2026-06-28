import 'dart:convert';

import 'package:flutter/foundation.dart' show immutable;

/// Journey type, per the doctrine's 5-value enum.
///
/// Journey Doctrine (docs/JOURNEY_DOCTRINE.md): adult lane allows all
/// five; kid lane allows only [narrative], [character], [practice]
/// (NO [theme], NO [teaching]). The schema validator test
/// (test/features/journey/journey_registry_validator_test.dart)
/// enforces this at CI time.
enum JourneyType { narrative, character, theme, teaching, practice }

/// Lane, per the doctrine's Kid-Lane Appendix.
enum JourneyLane { adult, kid }

/// Editorial readiness. The runtime loader filters [ready]; [held]
/// and [draft] journeys are visible to curators but NEVER reach the
/// engine.
enum JourneyStatus { held, draft, ready }

/// One story slot in a journey's ordered sequence.
@immutable
class JourneyStory {
  /// Adult journeys use [storyNumber] (manifest's leading numeric
  /// ID, e.g. `1486`). Kid journeys use [productionId] (the
  /// 1801+ band identifier from `kid_anchor_registry.json`).
  /// Exactly one of these is non-null per entry.
  final int? storyNumber;
  final int? productionId;

  /// Adult journeys use [scriptureAnchorId] (matches the
  /// scripture_anchor_registry, e.g. `daniel_1_8-21`).
  /// Kid journeys use [anchorId] (matches `kid_anchor_registry`,
  /// e.g. `david_shepherd`).
  final String? scriptureAnchorId;
  final String? anchorId;

  /// Editorial label, curator-visible for journey review. NEVER
  /// shown to the user. Use the journey's display strings instead.
  final String label;

  /// Per-story curator note. Optional.
  final String? editorialNote;

  const JourneyStory({
    this.storyNumber,
    this.productionId,
    this.scriptureAnchorId,
    this.anchorId,
    required this.label,
    this.editorialNote,
  });

  factory JourneyStory.fromJson(Map<String, dynamic> json) {
    final storyNumber = json['storyNumber'] as int?;
    final productionId = json['productionId'] as int?;
    if ((storyNumber == null) == (productionId == null)) {
      throw StateError(
          'JourneyStory must have exactly one of storyNumber/productionId; '
          'got storyNumber=$storyNumber, productionId=$productionId, label=${json['label']}');
    }
    final scriptureAnchorId = json['scriptureAnchorId'] as String?;
    final anchorId = json['anchorId'] as String?;
    if (scriptureAnchorId == null && anchorId == null) {
      throw StateError(
          'JourneyStory must have scriptureAnchorId or anchorId; label=${json['label']}');
    }
    final label = json['label'] as String?;
    if (label == null || label.isEmpty) {
      throw StateError('JourneyStory.label is required and non-empty');
    }
    return JourneyStory(
      storyNumber: storyNumber,
      productionId: productionId,
      scriptureAnchorId: scriptureAnchorId,
      anchorId: anchorId,
      label: label,
      editorialNote: json['editorialNote'] as String?,
    );
  }
}

/// An editorial journey — hand-curated, ordered sequence of stories
/// PAL can offer to continue.
///
/// Journey Doctrine (docs/JOURNEY_DOCTRINE.md). A journey is NOT a
/// reading plan, a streak, or a completion goal. The user never sees
/// the journey type; PAL never names it. Journeys exist so PAL can
/// say "Yesterday we spent time with Daniel — want to continue?" and
/// have something honest to point at.
@immutable
class Journey {
  final String journeyId;
  final JourneyType journeyType;
  final JourneyLane lane;
  final JourneyStatus status;
  final List<JourneyStory> stories;

  /// For adult Narrative/Character journeys: key into
  /// `PalMemoryDisplayNameRegistry` so the compositional offer line
  /// can reuse the existing Slice 2d "name" clip. Null if this
  /// journey doesn't compose with a registry name (e.g. Theme
  /// journeys use [themeWord] instead).
  final String? nameRegistryKey;

  /// For Theme journeys: the editorial theme word PAL would name
  /// in the offer line ("waiting on God", "loving your neighbor").
  /// Drives a new clip family rendered per voice.
  final String? themeWord;

  /// For kid journeys: the editorial character name PAL would name
  /// in the offer line ("David", "Moses"). Drives a per-voice
  /// name-clip render in the kid-offer flavor.
  final String? characterName;

  /// Curator-only note. NEVER surfaced to the user.
  final String? editorialNote;

  const Journey({
    required this.journeyId,
    required this.journeyType,
    required this.lane,
    required this.status,
    required this.stories,
    this.nameRegistryKey,
    this.themeWord,
    this.characterName,
    this.editorialNote,
  });

  factory Journey.fromJson(Map<String, dynamic> json) {
    JourneyType parseType(String s) {
      switch (s) {
        case 'narrative':
          return JourneyType.narrative;
        case 'character':
          return JourneyType.character;
        case 'theme':
          return JourneyType.theme;
        case 'teaching':
          return JourneyType.teaching;
        case 'practice':
          return JourneyType.practice;
      }
      throw StateError('Unknown journeyType: "$s"');
    }

    JourneyLane parseLane(String s) {
      switch (s) {
        case 'adult':
          return JourneyLane.adult;
        case 'kid':
          return JourneyLane.kid;
      }
      throw StateError('Unknown lane: "$s"');
    }

    JourneyStatus parseStatus(String s) {
      switch (s) {
        case 'held':
          return JourneyStatus.held;
        case 'draft':
          return JourneyStatus.draft;
        case 'ready':
          return JourneyStatus.ready;
      }
      throw StateError('Unknown status: "$s"');
    }

    final journeyId = json['journeyId'] as String?;
    if (journeyId == null || journeyId.isEmpty) {
      throw StateError('Journey.journeyId is required and non-empty');
    }
    final rawStories = json['stories'] as List?;
    if (rawStories == null || rawStories.isEmpty) {
      throw StateError(
          'Journey "$journeyId" requires non-empty stories[]');
    }
    final stories = rawStories
        .cast<Map<String, dynamic>>()
        .map(JourneyStory.fromJson)
        .toList(growable: false);

    final lane = parseLane(json['lane'] as String);
    final type = parseType(json['journeyType'] as String);

    // Kid-lane invariants — mirror the schema validator test so the
    // model rejects malformed runtime input even if the validator was
    // somehow bypassed (e.g. malformed asset in a forked branch).
    if (lane == JourneyLane.kid) {
      if (type == JourneyType.theme || type == JourneyType.teaching) {
        throw StateError(
            'Kid journey "$journeyId" cannot have type=${type.name}; '
            'doctrine restricts kids to narrative/character/practice');
      }
      if (stories.length < 3 || stories.length > 5) {
        throw StateError(
            'Kid journey "$journeyId" has ${stories.length} stories; '
            'doctrine caps at 3-5');
      }
    }

    return Journey(
      journeyId: journeyId,
      journeyType: type,
      lane: lane,
      status: parseStatus(json['status'] as String),
      stories: stories,
      nameRegistryKey: json['nameRegistryKey'] as String?,
      themeWord: json['themeWord'] as String?,
      characterName: json['characterName'] as String?,
      editorialNote: json['editorialNote'] as String?,
    );
  }

  factory Journey.fromJsonString(String jsonStr) =>
      Journey.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>);
}

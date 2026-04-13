import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/paths/path_type.dart';
import 'package:bible_pal/features/paths/path_launch_context.dart';
import 'package:bible_pal/core/timeline_era.dart';

/// Tests for the Phase 1 value objects: PathType enum (SPEC 50.1),
/// TimelineEra enum (SPEC 50.2), and PathLaunchContext (SPEC 50.6).
/// Wire IDs are LOCKED and must match the SPEC exactly — any drift is a
/// telemetry-contract violation.
void main() {
  group('PathType wire ids (SPEC 50.1 — LOCKED)', () {
    test('all five path types have the exact spec wire ids', () {
      expect(PathType.jesusLife.wireId, 'jesus_life');
      expect(PathType.bibleOrder.wireId, 'bible_order');
      expect(PathType.timeline.wireId, 'timeline');
      expect(PathType.themes.wireId, 'themes');
      expect(PathType.characters.wireId, 'characters');
    });

    test('fromWire round-trips every path type', () {
      for (final pt in PathType.values) {
        expect(PathTypeParse.fromWire(pt.wireId), pt);
      }
    });

    test('fromWire throws on unknown wire id', () {
      expect(
        () => PathTypeParse.fromWire('made_up'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('isFeatured is true only for jesusLife', () {
      expect(PathType.jesusLife.isFeatured, isTrue);
      expect(PathType.bibleOrder.isFeatured, isFalse);
      expect(PathType.timeline.isFeatured, isFalse);
      expect(PathType.themes.isFeatured, isFalse);
      expect(PathType.characters.isFeatured, isFalse);
    });

    test('display labels match spec copy', () {
      expect(PathType.jesusLife.displayLabel, 'The Life of Jesus');
      expect(PathType.bibleOrder.displayLabel, 'Bible Order');
      expect(PathType.timeline.displayLabel, 'Timeline');
      expect(PathType.themes.displayLabel, 'Themes');
      expect(PathType.characters.displayLabel, 'Characters');
    });
  });

  group('TimelineEra wire ids (SPEC 50.2 — LOCKED)', () {
    test('all nine eras have the exact spec wire ids', () {
      expect(TimelineEra.creation.wireId, 'creation');
      expect(TimelineEra.patriarchs.wireId, 'patriarchs');
      expect(TimelineEra.exodus.wireId, 'exodus');
      expect(TimelineEra.judges.wireId, 'judges');
      expect(TimelineEra.kingdom.wireId, 'kingdom');
      expect(TimelineEra.exile.wireId, 'exile');
      expect(TimelineEra.returnFromExile.wireId, 'return');
      expect(TimelineEra.jesusMinistry.wireId, 'jesus_ministry');
      expect(TimelineEra.earlyChurch.wireId, 'early_church');
    });

    test('exactly nine eras exist', () {
      expect(TimelineEra.values.length, 9);
    });

    test('fromWire round-trips every era', () {
      for (final era in TimelineEra.values) {
        expect(TimelineEraParse.fromWire(era.wireId), era);
      }
    });

    test('fromWire returns null for unknown or null input', () {
      expect(TimelineEraParse.fromWire('made_up'), isNull);
      expect(TimelineEraParse.fromWire(null), isNull);
    });
  });

  group('PathLaunchContext', () {
    test('equality and hashCode are value-based', () {
      const a = PathLaunchContext(
        pathType: PathType.characters,
        pathId: 'david',
        positionInPath: 2,
      );
      const b = PathLaunchContext(
        pathType: PathType.characters,
        pathId: 'david',
        positionInPath: 2,
      );
      const c = PathLaunchContext(
        pathType: PathType.characters,
        pathId: 'david',
        positionInPath: 3,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });

    test('toString includes wire id, path id, and position', () {
      const ctx = PathLaunchContext(
        pathType: PathType.jesusLife,
        pathId: 'default',
        positionInPath: 0,
      );
      final s = ctx.toString();
      expect(s, contains('jesus_life'));
      expect(s, contains('default'));
      expect(s, contains('0'));
    });
  });
}

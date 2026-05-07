import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/pal/opening/pal_opening_lines.dart';

void main() {
  group('PAL Opening Line IDs', () {
    test('all 12 lines have non-empty IDs', () {
      expect(palOpeningLines.length, 12);
      for (final line in palOpeningLines) {
        expect(line.id.isNotEmpty, true,
            reason: 'Line with text "${line.text}" has empty ID');
      }
    });

    test('all IDs are unique', () {
      final ids = <String>{};
      for (final line in palOpeningLines) {
        expect(ids.add(line.id), true,
            reason: 'Duplicate ID: ${line.id}');
      }
    });

    test('IDs follow OPENING_{BUCKET}_{NN} convention', () {
      const bucketCode = {
        OpeningTimeBucket.morning: 'MORN',
        OpeningTimeBucket.afternoon: 'AFTN',
        OpeningTimeBucket.evening: 'EVEN',
        OpeningTimeBucket.night: 'NIGHT',
      };
      for (final line in palOpeningLines) {
        final code = bucketCode[line.bucket]!;
        expect(line.id, startsWith('OPENING_${code}_'),
            reason:
                'ID "${line.id}" does not match bucket "${line.bucket.name}"');
        final parts = line.id.split('_');
        final suffix = parts.last;
        expect(suffix.length, 2,
            reason: 'ID "${line.id}" suffix is not 2 digits');
        expect(int.tryParse(suffix), isNotNull,
            reason: 'ID "${line.id}" suffix is not numeric');
      }
    });

    test('each bucket has exactly 3 IDs', () {
      for (final bucket in OpeningTimeBucket.values) {
        final ids = palOpeningLines
            .where((l) => l.bucket == bucket)
            .map((l) => l.id)
            .toList();
        expect(ids.length, 3,
            reason: '${bucket.name} has ${ids.length} IDs (expected 3)');
      }
    });
  });
}

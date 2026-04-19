import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/features/pal/opening/pal_opening_lines.dart';

void main() {
  group('PAL Opening Line IDs', () {
    test('all 60 lines have non-empty IDs', () {
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

    test('IDs follow OPENING_{TONE}_{NN} convention', () {
      for (final line in palOpeningLines) {
        final toneUpper = line.tone.name.toUpperCase();
        expect(line.id, startsWith('OPENING_${toneUpper}_'),
            reason:
                'ID "${line.id}" does not match tone "${line.tone.name}"');
        // Extract the NN suffix
        final parts = line.id.split('_');
        final suffix = parts.last;
        expect(suffix.length, 2,
            reason: 'ID "${line.id}" suffix is not 2 digits');
        expect(int.tryParse(suffix), isNotNull,
            reason: 'ID "${line.id}" suffix is not numeric');
      }
    });

    test('each tone has 12 IDs', () {
      for (final tone in PalOpeningTone.values) {
        final toneUpper = tone.name.toUpperCase();
        final ids = palOpeningLines
            .where((l) => l.tone == tone)
            .map((l) => l.id)
            .toList();
        expect(ids.length, 12,
            reason: '$toneUpper has ${ids.length} IDs (expected 12)');
      }
    });

    test('pickOpeningLine returns line with valid ID', () {
      final line = pickOpeningLine();
      expect(line.id.isNotEmpty, true);
      expect(line.id, startsWith('OPENING_'));
    });
  });
}

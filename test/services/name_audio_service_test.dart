import 'package:flutter_test/flutter_test.dart';
import 'package:bible_pal/services/name_audio_service.dart';

void main() {
  group('NameAudioService.nameKey', () {
    test('produces consistent hash for same name', () {
      final key1 = NameAudioService.nameKey('Sarah');
      final key2 = NameAudioService.nameKey('Sarah');
      expect(key1, key2);
    });

    test('is case-insensitive', () {
      final lower = NameAudioService.nameKey('sarah');
      final upper = NameAudioService.nameKey('SARAH');
      final mixed = NameAudioService.nameKey('Sarah');
      expect(lower, upper);
      expect(lower, mixed);
    });

    test('trims whitespace', () {
      final trimmed = NameAudioService.nameKey('Sarah');
      final padded = NameAudioService.nameKey('  Sarah  ');
      expect(trimmed, padded);
    });

    test('returns 16-char hex string', () {
      final key = NameAudioService.nameKey('TestName');
      expect(key.length, 16);
      expect(RegExp(r'^[0-9a-f]{16}$').hasMatch(key), true,
          reason: 'nameKey should be 16 hex chars');
    });

    test('different names produce different keys', () {
      final key1 = NameAudioService.nameKey('Sarah');
      final key2 = NameAudioService.nameKey('James');
      expect(key1, isNot(key2));
    });
  });

  group('NameAudioService.phraseText', () {
    test('replaces {name} in all 4 templates', () {
      for (var i = 0; i < 4; i++) {
        final text = NameAudioService.phraseText('Sarah', i);
        expect(text, contains('Sarah'),
            reason: 'Template $i should contain the name');
        expect(text, isNot(contains('{name}')),
            reason: 'Template $i should not contain {name} placeholder');
      }
    });

    test('template 0 is "Hey, {name}!"', () {
      expect(NameAudioService.phraseText('Alex', 0), 'Hey, Alex!');
    });

    test('template 1 is "Hi there, {name}!"', () {
      expect(NameAudioService.phraseText('Alex', 1), 'Hi there, Alex!');
    });

    test('template 2 is "{name}, welcome back!"', () {
      expect(NameAudioService.phraseText('Alex', 2), 'Alex, welcome back!');
    });

    test('template 3 is "Good to see you, {name}!"', () {
      expect(
          NameAudioService.phraseText('Alex', 3), 'Good to see you, Alex!');
    });

    test('index wraps around with modulo', () {
      final text4 = NameAudioService.phraseText('Alex', 4);
      final text0 = NameAudioService.phraseText('Alex', 0);
      expect(text4, text0, reason: 'Index 4 should wrap to template 0');
    });
  });
}

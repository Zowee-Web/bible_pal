import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bible_pal/core/ambient_sound_type.dart';
import 'package:bible_pal/services/ambient_audio_service.dart';

void main() {
  group('AmbientSoundType', () {
    test('has exactly 4 values', () {
      expect(AmbientSoundType.values.length, 4);
    });

    test('assetPath produces correct paths', () {
      expect(AmbientSoundType.rain.assetPath,
          'assets/audio/ambient/rain.mp3');
      expect(AmbientSoundType.wind.assetPath,
          'assets/audio/ambient/wind.mp3');
      expect(AmbientSoundType.night.assetPath,
          'assets/audio/ambient/night.mp3');
      expect(AmbientSoundType.pads.assetPath,
          'assets/audio/ambient/pads.mp3');
    });

    test('fromString returns correct type for valid input', () {
      expect(AmbientSoundType.fromString('rain'), AmbientSoundType.rain);
      expect(AmbientSoundType.fromString('wind'), AmbientSoundType.wind);
      expect(AmbientSoundType.fromString('night'), AmbientSoundType.night);
      expect(AmbientSoundType.fromString('pads'), AmbientSoundType.pads);
    });

    test('fromString returns rain for null', () {
      expect(AmbientSoundType.fromString(null), AmbientSoundType.rain);
    });

    test('invalid sound type falls back to rain', () {
      expect(
          AmbientSoundType.fromString('invalid_garbage'), AmbientSoundType.rain);
      expect(AmbientSoundType.fromString(''), AmbientSoundType.rain);
      expect(AmbientSoundType.fromString('thunder'), AmbientSoundType.rain);
    });

    test('defaultType is rain', () {
      expect(AmbientSoundType.defaultType, AmbientSoundType.rain);
    });
  });

  group('AmbientAudioService', () {
    late AmbientAudioService service;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      service = AmbientAudioService();
    });

    tearDown(() async {
      await service.dispose();
    });

    test('ambient does not play when disabled', () async {
      SharedPreferences.setMockInitialValues({
        'settings.backgroundSoundOn': false,
      });
      await service.startIfEnabled();
      expect(service.isPlaying, false);
    });

    test('ambient does not play when setting is missing', () async {
      SharedPreferences.setMockInitialValues({});
      await service.startIfEnabled();
      expect(service.isPlaying, false);
    });

    test('isPlaying is false after stop when not started', () async {
      await service.stop();
      expect(service.isPlaying, false);
    });
  });

  group('Sound selection persistence', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test('sound selection persists to SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      await sp.setString('settings.ambientSoundType', 'night');

      final loaded = sp.getString('settings.ambientSoundType');
      expect(AmbientSoundType.fromString(loaded), AmbientSoundType.night);
    });

    test('missing sound type defaults to rain', () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();

      final loaded = sp.getString('settings.ambientSoundType');
      expect(AmbientSoundType.fromString(loaded), AmbientSoundType.rain);
    });
  });
}

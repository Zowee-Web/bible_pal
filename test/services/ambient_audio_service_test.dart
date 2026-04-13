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

  // ---------------------------------------------------------------------------
  // Player screen session-reset contract (SPEC Feature 49)
  // ---------------------------------------------------------------------------
  // These tests verify the two operations _loadAmbientState performs on every
  // player screen entry so ambient never auto-resumes from a prior visit.

  group('Player screen ambient session-reset contract', () {
    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    test(
        'startIfEnabled does not start ambient after backgroundSoundOn is removed',
        () async {
      // Simulate: user left with ambient ON (persisted pref = true).
      SharedPreferences.setMockInitialValues({
        'settings.backgroundSoundOn': true,
      });
      final sp = await SharedPreferences.getInstance();

      // _loadAmbientState clears the key on every screen entry.
      await sp.remove('settings.backgroundSoundOn');

      // Narration starts → startIfEnabled() must NOT auto-resume ambient.
      final service = AmbientAudioService();
      await service.startIfEnabled();
      expect(service.isPlaying, false,
          reason: 'ambient must not auto-resume after backgroundSoundOn removed');
      await service.dispose();
    });

    test('forceStop ensures isPlaying is false on screen entry', () async {
      // Simulate: ambient was somehow left playing from a previous visit.
      SharedPreferences.setMockInitialValues({});
      final service = AmbientAudioService();

      // _loadAmbientState calls forceStop() unconditionally.
      await service.forceStop();
      expect(service.isPlaying, false,
          reason: 'forceStop must guarantee isPlaying = false on entry');
      await service.dispose();
    });

    test('backgroundSoundOn is absent after screen entry reset', () async {
      SharedPreferences.setMockInitialValues({
        'settings.backgroundSoundOn': true,
      });
      final sp = await SharedPreferences.getInstance();
      await sp.remove('settings.backgroundSoundOn');

      expect(sp.getBool('settings.backgroundSoundOn'), isNull,
          reason: 'key must be absent so startIfEnabled defaults to disabled');
    });

    test('ambientSoundType and volume are still readable after reset', () async {
      // Chip selection and volume persist across visits; only the toggle does not.
      SharedPreferences.setMockInitialValues({
        'settings.backgroundSoundOn': true,
        'settings.ambientSoundType': 'pads',
        'settings.ambientVolume': 0.18,
      });
      final sp = await SharedPreferences.getInstance();
      await sp.remove('settings.backgroundSoundOn');

      expect(AmbientSoundType.fromString(sp.getString('settings.ambientSoundType')),
          AmbientSoundType.pads,
          reason: 'chip selection survives the toggle reset');
      expect(sp.getDouble('settings.ambientVolume'), closeTo(0.18, 0.001),
          reason: 'volume survives the toggle reset');
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

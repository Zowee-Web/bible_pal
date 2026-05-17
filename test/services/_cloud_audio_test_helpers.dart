// Shared helpers for Cloud Foundation v1 audio delivery tests.
// SPEC Feature 27 — platform-specific audio delivery.

import 'dart:async';
import 'dart:io';

import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/services/parable_service.dart';
import 'package:bible_pal/services/storage_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sets up SharedPreferences, path_provider mocks, and dotenv for a test.
/// Returns a fresh ParableService and the test root directory.
Future<({ParableService service, Directory root})> setupCloudAudioTest({
  String? audioBaseUrl,
}) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The widget-test binding installs HttpOverrides that force all real
  // requests to return 400. We run a real HTTP server in these tests, so
  // restore the default (no overrides) for the duration of the test.
  HttpOverrides.global = null;
  SharedPreferences.setMockInitialValues({});

  final root = await Directory.systemTemp.createTemp('bible_pal_cloud_test_');
  final docs = Directory('${root.path}/documents')..createSync(recursive: true);
  final temp = Directory('${root.path}/temp')..createSync(recursive: true);

  // Mock path_provider via the platform channel.
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(channel, (call) async {
    switch (call.method) {
      case 'getApplicationDocumentsDirectory':
        return docs.path;
      case 'getTemporaryDirectory':
        return temp.path;
      case 'getApplicationSupportDirectory':
        return docs.path;
      default:
        return null;
    }
  });

  // Reset and load dotenv with the desired AUDIO_BASE_URL (or empty).
  dotenv.testLoad(
    fileInput: audioBaseUrl == null ? '' : 'AUDIO_BASE_URL=$audioBaseUrl',
  );

  final storage = await StorageService.create();
  // testMode=true bypasses on-disk validation in _loadManifest().
  final service = ParableService(storage, null, true);
  return (service: service, root: root);
}

Parable testParable({
  String storyId = 'story_test_001',
  // Deliberately points at a path that is NOT bundled in pubspec.yaml so the
  // asset-tier resolver misses and tests can exercise the R2 fallback path.
  String audioFilePath = 'traditional/9999/audio_9999_story_short.mp3',
  String mood = 'joyful',
}) {
  return Parable(
    storyId: storyId,
    title: 'Test Story',
    mood: mood,
    storytellingMode: 'traditional',
    kidFriendly: false,
    audioFilePath: audioFilePath,
    storyLength: 'short',
  );
}

/// Spins up an in-process HTTP server that serves the given byte body for any
/// request. The server URL is returned for use as AUDIO_BASE_URL.
Future<({HttpServer server, String baseUrl})> startFakeAudioServer({
  required List<int> body,
  int statusCode = 200,
  bool truncate = false,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  unawaited(server.forEach((HttpRequest req) async {
    req.response.statusCode = statusCode;
    if (statusCode != 200) {
      await req.response.close();
      return;
    }
    req.response.headers.contentType = ContentType('audio', 'mpeg');
    req.response.contentLength = body.length;
    if (truncate) {
      req.response.add(body.sublist(0, body.length ~/ 2));
      await req.response.flush();
      // Force-close mid-stream to simulate interruption.
      try {
        final socket =
            await req.response.detachSocket(writeHeaders: false);
        socket.destroy();
      } catch (_) {/* ignore */}
      return;
    }
    req.response.add(body);
    await req.response.close();
  }));
  return (
    server: server,
    baseUrl: 'http://${server.address.host}:${server.port}'
  );
}

const sampleAudioBytes = <int>[
  0xFF, 0xFB, 0x90, 0x00, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10
];

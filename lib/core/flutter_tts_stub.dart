/// No-op stub for flutter_tts while native plugin is disabled.
/// Remove this file and restore the real import once the plugin is fixed.
class FlutterTts {
  Future<dynamic> awaitSpeakCompletion(bool await_) async => 1;
  Future<dynamic> stop() async => 1;
  Future<dynamic> speak(String text) async => 1;
  Future<dynamic> setSpeechRate(double rate) async => 1;
  Future<dynamic> setPitch(double pitch) async => 1;
  Future<dynamic> setVoice(Map<String, String> voice) async => 1;
  Future<dynamic> get getVoices async => <dynamic>[];
}

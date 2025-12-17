// lib/features/whisper/whisper_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter_tts/flutter_tts.dart';

class WhisperScreen extends StatefulWidget {
  const WhisperScreen({super.key});

  @override
  State<WhisperScreen> createState() => _WhisperScreenState();
}

class _WhisperScreenState extends State<WhisperScreen> {
  // Speech & TTS
  final SpeechToText _speech = SpeechToText();
  final FlutterTts _tts = FlutterTts();

  // UI state
  bool _isListening = false;
  bool _speechAvail = false;
  String _prompt = '';
  String _lastError = '';
  String _lastStatus = '';

  @override
  void initState() {
    super.initState();
    // Ensure TTS waits for completion so we can speak the question,
    // then open the mic after it finishes.
    unawaited(_tts.awaitSpeakCompletion(true));
  }

  /// Ask for *both* permissions we need on iOS.
  Future<bool> _ensurePermissions() async {
    final mic = await Permission.microphone.request();
    final speechPerm = await Permission.speech.request();

    if (mic.isGranted && speechPerm.isGranted) return true;

    // If either was permanently denied, point the user to Settings.
    if (mic.isPermanentlyDenied || speechPerm.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Please enable Microphone & Speech Recognition in Settings.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
      await openAppSettings();
      return false;
    }

    // Otherwise a simple nudge.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone & Speech permissions are required.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    return false;
  }

  /// Initialize the speech engine (will reflect current permission state).
  Future<void> _initSpeech() async {
    try {
      final avail = await _speech.initialize(
        onError: (e) => setState(() {
          _lastError = '${e.errorMsg} (${e.permanent})';
        }),
        onStatus: (s) => setState(() => _lastStatus = s),
        debugLogging: false,
      );
      setState(() => _speechAvail = avail);
    } catch (e) {
      setState(() {
        _speechAvail = false;
        _lastError = e.toString();
      });
    }
  }

  /// Main flow: ask a question (TTS) → listen → generate/speak a short story.
  Future<void> _captureAndPlay() async {
    // 1) Permissions first (this is what triggers iOS prompts)
    if (!await _ensurePermissions()) return;

    // 2) Initialize speech engine if needed
    if (!_speechAvail) {
      await _initSpeech();
      if (!_speechAvail) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech not available: $_lastError')),
          );
        }
        return;
      }
    }

    // 3) UI: we’re about to start the flow
    setState(() {
      _isListening = true;
      _prompt = '';
      _lastError = '';
    });

    // 4) Speak the time-of-day question, then *after it finishes* start listening
    final question = _timeOfDayQuestion();
    try {
      await _tts.stop();
      await _tts.speak(question);
    } catch (_) {}

    // A tiny cushion after completion helps on some devices.
    await Future.delayed(const Duration(milliseconds: 250));

    // 5) Listen for the user’s response
    final completer = Completer<void>();
    try {
      await _speech.listen(
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 2),
        listenOptions: SpeechListenOptions(partialResults: true),
        onResult: (result) {
          setState(() => _prompt = result.recognizedWords.trim());
          if (result.finalResult && !completer.isCompleted) {
            completer.complete();
          }
        },
      );
    } catch (e) {
      setState(() {
        _isListening = false;
        _lastError = 'Listen failed: $e';
      });
      return;
    }

    // 6) Wait for final result or a timeout fallback
    unawaited(Future.delayed(const Duration(seconds: 9)).then((_) {
      if (!completer.isCompleted) completer.complete();
    }));
    await completer.future;

    // 7) Stop listening, reset UI
    try {
      await _speech.stop();
    } catch (_) {}
    if (!mounted) return;
    setState(() => _isListening = false);

    // 8) Build a small mood-aware “story” and speak it
    final prompt = _prompt.isEmpty ? 'a moment of peace and hope' : _prompt;
    final story = _buildTinyStory(prompt);

    // Configure TTS (simple defaults)
    await _tts.setSpeechRate(0.44);
    await _tts.setPitch(1.0);

    // Best-effort voice selection (prefer English)
    try {
      final dynamic voicesDyn = await _tts.getVoices;
      final voices = (voicesDyn as List?)?.cast<Map?>() ?? const [];
      if (voices.isNotEmpty) {
        final selected = voices.firstWhere(
          (v) => ((v?['locale'] as String?) ?? '').startsWith('en'),
          orElse: () => voices.first,
        );
        if (selected != null) {
          await _tts.setVoice(Map<String, String>.from(selected));
        }
      }
    } catch (_) {}

    try {
      await _tts.stop();
      await _tts.speak(story);
    } catch (e) {
      setState(() => _lastError = 'TTS failed: $e');
    }
  }

  // --- Helpers: prompt + mood detection + story builder ---

  String _timeOfDayQuestion() {
    final hour = DateTime.now().hour;
    if (hour >= 22 || hour < 5) return 'How is your night going?';
    if (hour >= 18) return 'How was your day?';
    return 'How is your day going?';
  }

  String _detectMood(String prompt) {
    final text = prompt.toLowerCase();
    bool hasAny(List<String> words) => words.any((w) => text.contains(w));
    if (hasAny([
      'grateful',
      'thankful',
      'blessed',
      'good',
      'great',
      'encouraged',
      'joyful',
      'happy'
    ])) {
      return 'joyful';
    }
    if (hasAny(['tired', 'exhausted', 'weary', 'drained', 'worn'])) {
      return 'weary';
    }
    if (hasAny(['stressed', 'anxious', 'worried', 'overwhelmed', 'tense'])) {
      return 'anxious';
    }
    if (hasAny([
      'sad',
      'hurt',
      'lonely',
      'discouraged',
      'down',
      'upset',
      'heartbroken'
    ])) {
      return 'hurting';
    }
    return 'neutral';
  }

  String _buildTinyStory(String prompt) {
    final cleaned = prompt.trim();
    final topic = cleaned.isEmpty ? 'this moment' : cleaned;
    final mood = _detectMood(cleaned);

    switch (mood) {
      case 'joyful':
        return '''
Here is a short reflection inspired by "$topic".

Your words sound bright, like Psalm 118:24 declaring that this day belongs to the Lord.
Let gratitude be the song that steadies your steps, and share that glow with someone nearby.
Celebrate His goodness and keep your heart open to the next blessing waiting at your door.

— End —
'''
            .trim();

      case 'weary':
        return '''
Here is a short reflection inspired by "$topic".

I hear some weariness in your voice. Jesus whispers from Matthew 11:28, "Come to me ... and I will give you rest."
Let the Shepherd lead you beside still waters; breathe deep and let Him shoulder the heavy parts tonight.
He is near, and He delights to give you the rest you crave.

— End —
'''
            .trim();

      case 'anxious':
        return '''
Here is a short reflection inspired by "$topic".

When your thoughts feel tangled, remember Philippians 4:6—trade worry for prayer with thanksgiving.
Name each concern and release it into God's steady hands; His peace is building a guard around your heart even now.
You are not walking this stretch alone; He is closer than the next breath.

— End —
'''
            .trim();

      case 'hurting':
        return '''
Here is a short reflection inspired by "$topic".

The ache you described is seen. Psalm 34:18 promises the Lord is close to the brokenhearted.
Let tears be a prayer and let His presence wrap the tender places until hope rises again.
Reach toward a trusted friend—shared burdens grow lighter in community.

— End —
'''
            .trim();

      default:
        return '''
Here is a short reflection inspired by "$topic".

In every ordinary moment, God's faithful love hums beneath the noise.
Pause long enough to notice His fingerprints today—the kindness, the courage, the gentle nudge forward.
Step into the rest of your day knowing you are held and guided.

— End —
'''
            .trim();
    }
  }

  @override
  void dispose() {
    _tts.stop();
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Whisper')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Whisper is listening ${_isListening ? '…' : ''}',
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    _isListening
                        ? 'Speak your prompt now. We’ll auto-stop in a few seconds.'
                        : 'Tap “Play Story”, we’ll ask how your day is going, then listen and read a tiny story aloud.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: _isListening ? null : _captureAndPlay,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Play Story'),
                      ),
                      const SizedBox(width: 12),
                      if (_isListening)
                        FilledButton.icon(
                          onPressed: () async {
                            try {
                              await _speech.stop();
                            } catch (_) {}
                            if (mounted) setState(() => _isListening = false);
                          },
                          icon: const Icon(Icons.stop),
                          label: const Text('Stop'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Your prompt (recognized):', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(_prompt.isEmpty ? '—' : _prompt),
          ),
          if (_lastError.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Error',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: theme.colorScheme.error)),
            Text(_lastError, style: theme.textTheme.bodySmall),
          ],
          if (_lastStatus.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Status', style: theme.textTheme.titleSmall),
            Text(_lastStatus, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

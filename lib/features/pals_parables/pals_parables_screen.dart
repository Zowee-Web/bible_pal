import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:bible_pal/services/greeting_service.dart';
import 'package:bible_pal/services/mood_service.dart';
import 'package:bible_pal/services/pal_audio_service.dart';
import 'package:bible_pal/providers/service_providers.dart' show palAudioServiceProvider;
import 'package:bible_pal/services/verse_service.dart';
import 'package:bible_pal/services/stt_service.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/widgets/greeting_display.dart';
import 'package:bible_pal/widgets/story_length_radio_selector.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/core/story_length_bucket.dart';

/// Voice input states for the PAL Voice Mood Input flow (Feature 2.2).
///
/// See SPEC.md Feature 2.2 for state machine transitions.
enum VoiceInputState {
  /// Default state. TextField + mic button visible.
  idle,

  /// System permission dialog is showing.
  awaitingPermission,

  /// Microphone active, STT processing. Partial transcript shown as preview.
  listening,

  /// Final transcript inserted into TextField. User can edit/re-record.
  confirming,

  /// Mood detected, proceeding with compassionate reply + verse + length selection.
  proceeding,
}

/// PAL's Parables Screen
/// Based on SPEC.md Features 2, 2.1, 2.2, 3, 4, 5, 14, 16
/// Complete flow: greeting → mood input (type or voice) → compassionate reply + verse → auto-transition to parable playback
class PalsParablesScreen extends ConsumerStatefulWidget {
  const PalsParablesScreen({super.key, this.sttService, this.textOnly = false});

  /// Optional STT service for dependency injection (testing).
  final SttService? sttService;

  /// When true, voice/mic input is hidden (text-only interaction with PAL).
  /// Story audio playback is NOT affected — only input method changes.
  final bool textOnly;

  @override
  ConsumerState<PalsParablesScreen> createState() => _PalsParablesScreenState();
}

class _PalsParablesScreenState extends ConsumerState<PalsParablesScreen> {
  final TextEditingController _moodController = TextEditingController();
  final GreetingService _greetingService = GreetingService();
  final VerseService _verseService = VerseService();

  late final SttService _sttService;

  String? _greeting;
  String? _emoji;
  String? _compassionateReply;
  MoodResult? _moodResult;
  VerseResponse? _verse;
  bool _isSelectingParable = false;
  StoryLengthBucket _selectedLengthBucket = StoryLengthBucket.short;

  // Voice input state (Feature 2.2)
  VoiceInputState _voiceState = VoiceInputState.idle;
  String _partialTranscript = '';
  bool _sttAvailable = false;

  @override
  void initState() {
    super.initState();
    _sttService = widget.sttService ?? SttService();
    _greeting = _greetingService.getGreeting();
    _emoji = _greetingService.getTimeWindowEmoji();

    // Log screen view
    logEvent('screen_view', {'screen_name': 'pals_parables'});

    // Play PAL greeting audio and use its text for display
    _playPalGreeting();

    // Initialize STT engine (non-blocking) to check availability
    if (!widget.textOnly) {
      _initStt();
    }
  }

  Future<void> _playPalGreeting() async {
    final appState = ref.read(appStateProvider).valueOrNull;
    // Skip audio if PAL greetings are disabled
    if (appState?.userPreferences.palGreetingsEnabled == false) return;

    final voiceKey = appState?.userPreferences.palVoiceKey ?? 'VOICE_SARAH_STORYTELLER';
    final palAudio = ref.read(palAudioServiceProvider);

    try {
      final text = await palAudio.playGreeting(voiceKey);
      if (mounted && text.isNotEmpty) {
        setState(() => _greeting = text);
      }
    } catch (e) {
      debugPrint('[PalsParables] PAL greeting audio failed: $e');
      // Text-only fallback — _greeting already set from GreetingService
    }
  }

  Future<void> _initStt() async {
    final available = await _sttService.initialize();
    if (mounted) {
      setState(() => _sttAvailable = available);
    }
  }

  @override
  void dispose() {
    _moodController.dispose();
    _sttService.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Voice input methods (Feature 2.2)
  // ---------------------------------------------------------------------------

  /// Handle mic button tap. Transitions through the state machine:
  /// idle → awaitingPermission → listening → confirming
  Future<void> _onMicTap() async {
    if (_voiceState != VoiceInputState.idle) return;

    // Auto-stop greeting audio if still playing (SPEC 2.2)
    ref.read(palAudioServiceProvider).stop();

    // Check if STT is available
    if (!_sttAvailable) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Voice input not available on this platform'),
            duration: Duration(seconds: 3),
          ),
        );
        logEvent('voice_input_cancelled', {'reason': 'stt_unavailable'});
      }
      return;
    }

    // Check permissions
    setState(() => _voiceState = VoiceInputState.awaitingPermission);

    final permResult = await _sttService.checkPermissions();

    if (!mounted) return;

    switch (permResult) {
      case SttPermissionResult.granted:
        _startListening();

      case SttPermissionResult.denied:
        setState(() => _voiceState = VoiceInputState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required for voice input'),
            duration: Duration(seconds: 3),
          ),
        );
        logEvent('voice_input_cancelled', {'reason': 'permission_denied'});

      case SttPermissionResult.permanentlyDenied:
        setState(() => _voiceState = VoiceInputState.idle);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Microphone permission denied. Enable it in Settings.'),
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Settings',
              onPressed: () => openAppSettings(),
            ),
          ),
        );
        logEvent('voice_input_cancelled', {'reason': 'permission_denied'});
    }
  }

  /// Start STT listening. Transitions: awaitingPermission → listening.
  Future<void> _startListening() async {
    setState(() {
      _voiceState = VoiceInputState.listening;
      _partialTranscript = '';
    });

    final completer = Completer<void>();

    await _sttService.startListening(
      onResult: (result) {
        if (!mounted) return;
        if (result.isFinal) {
          // Final result: place into TextField and transition to confirming
          final transcript = result.text;
          if (transcript.isEmpty) {
            // Silence timeout — 0 words detected
            setState(() {
              _voiceState = VoiceInputState.idle;
              _partialTranscript = '';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("I didn't catch that. Try again or type your response."),
                duration: Duration(seconds: 3),
              ),
            );
            logEvent('voice_input_cancelled', {'reason': 'timeout'});
          } else {
            // Voice transcript → TextField (Invariant 17: input equivalence)
            _moodController.text = transcript;
            setState(() {
              _voiceState = VoiceInputState.confirming;
              _partialTranscript = '';
            });
            // Log completion with word count only — no transcript (Invariant 17)
            logEvent('voice_input_completed', {
              'input_method': 'voice',
              'word_count': transcript.split(RegExp(r'\s+')).length,
            });
          }
          if (!completer.isCompleted) completer.complete();
        } else {
          // Partial result: show preview below mic indicator
          setState(() => _partialTranscript = result.text);
        }
      },
      onError: (error) {
        if (!mounted) return;
        setState(() {
          _voiceState = VoiceInputState.idle;
          _partialTranscript = '';
        });
        logEvent('voice_input_cancelled', {'reason': 'stt_unavailable'});
        if (!completer.isCompleted) completer.complete();
      },
    );

    // Timeout fallback: if no final result within listen duration + buffer
    unawaited(
      Future.delayed(const Duration(seconds: SttService.defaultListenSeconds + 1))
          .then((_) {
        if (!completer.isCompleted) {
          // Use partial transcript if we have one
          if (_partialTranscript.isNotEmpty && mounted) {
            _moodController.text = _partialTranscript;
            setState(() {
              _voiceState = VoiceInputState.confirming;
              _partialTranscript = '';
            });
            logEvent('voice_input_completed', {
              'input_method': 'voice',
              'word_count':
                  _moodController.text.split(RegExp(r'\s+')).length,
            });
          } else if (mounted) {
            setState(() {
              _voiceState = VoiceInputState.idle;
              _partialTranscript = '';
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("I didn't catch that. Try again or type your response."),
                duration: Duration(seconds: 3),
              ),
            );
            logEvent('voice_input_cancelled', {'reason': 'timeout'});
          }
          completer.complete();
        }
      }),
    );
  }

  /// Cancel voice input and return to idle (typing fallback).
  Future<void> _cancelVoiceInput() async {
    await _sttService.stopListening();
    if (mounted) {
      setState(() {
        _voiceState = VoiceInputState.idle;
        _partialTranscript = '';
      });
      logEvent('voice_input_cancelled', {'reason': 'user_cancel'});
    }
  }

  /// Re-record: go back to listening from confirming state.
  Future<void> _reRecord() async {
    _moodController.clear();
    _startListening();
  }

  // ---------------------------------------------------------------------------
  // Mood submission (shared by typed and voice input — Invariant 17)
  // ---------------------------------------------------------------------------

  /// Handle mood detection, show verse, and display length selection.
  /// This is the SAME handler for both typed and voice input (Invariant 17: input equivalence).
  Future<void> _handleMoodSubmission() async {
    if (_moodController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please share how you\'re doing')),
      );
      return;
    }

    final moodService = ref.read(appStateProvider.notifier).moodService;
    final result = moodService.detectMood(_moodController.text);
    final verse = _verseService.getVerseForMood(result.mood);

    // Play PAL compassionate reply audio and use its text
    final appState = ref.read(appStateProvider).valueOrNull;
    final voiceKey = appState?.userPreferences.palVoiceKey ?? 'VOICE_SARAH_STORYTELLER';

    String reply;
    if (appState?.userPreferences.palGreetingsEnabled == false) {
      // PAL greetings disabled — text-only
      reply = moodService.generateCompassionateReply(result);
    } else {
      final palAudio = ref.read(palAudioServiceProvider);
      final moodBucket = PalAudioService.moodToBucket(result.mood);
      try {
        reply = await palAudio.playCompassionateReply(moodBucket, voiceKey);
      } catch (e) {
        debugPrint('[PalsParables] PAL reply audio failed: $e');
        // Fallback to MoodService text
        reply = moodService.generateCompassionateReply(result);
      }
    }

    setState(() {
      _moodResult = result;
      _compassionateReply = reply;
      _verse = verse;
      _voiceState = VoiceInputState.proceeding;
    });
  }

  /// Handle length bucket selection and parable loading
  Future<void> _handleLengthSelection(StoryLengthBucket lengthBucket) async {
    if (_moodResult == null) {
      debugPrint('No mood result available');
      return;
    }

    // Log length selection (no user text logged!)
    // NOTE: length_bucket is canonical - no minute-based fields in telemetry (INVARIANTS.md)
    logEvent('length_selected', {
      'length_bucket': lengthBucket.name,
      'detected_mood': _moodResult!.mood,
    });

    setState(() => _isSelectingParable = true);

    // Log PAL tap event
    logEvent('pal_tap', {
      'length_bucket': lengthBucket.name,
      'detected_mood': _moodResult!.mood,
    });

    try {
      final appStateNotifier = ref.read(appStateProvider.notifier);

      // Select parable based on mood, length bucket, and user's text for relatability
      final parable = await appStateNotifier.selectParable(
        mood: _moodResult!.mood,
        lengthBucket: lengthBucket,
        userText: _moodController.text,
      );

      if (!mounted) return;

      if (parable == null) {
        setState(() => _isSelectingParable = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No story available for this mood and length yet.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }

      // Add to history
      await appStateNotifier.addToHistory(parable);

      // Load into player
      if (!mounted) return;
      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      await playerNotifier.loadParable(parable);

      if (!mounted) return;
      setState(() => _isSelectingParable = false);

      // Navigate to player screen
      if (!mounted) return;
      Navigator.of(context).pushNamed('/parable_player');
    } catch (e) {
      setState(() => _isSelectingParable = false);
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading parable: $e'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isVoiceActive = _voiceState == VoiceInputState.listening ||
        _voiceState == VoiceInputState.awaitingPermission;

    return Scaffold(
      appBar: AppBar(
        title: const Text('PAL\'s Stories'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Greeting Display
          GreetingDisplay(
            greeting: _greeting ?? '',
            emoji: _emoji ?? '✨',
          ),
          const SizedBox(height: 12),

          // Subtitle
          Text(
            'Share how you\'re really doing so PAL can choose a story for your heart.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Mood Input Section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // TextField (always visible per SPEC 2.2)
                  TextField(
                    controller: _moodController,
                    maxLines: 3,
                    autofocus: false,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    enabled: !isVoiceActive,
                    onTap: () {
                      // Tapping TextField cancels voice input (SPEC 2.2)
                      if (_voiceState == VoiceInputState.listening) {
                        _cancelVoiceInput();
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Share how you\'re doing',
                      hintText: _voiceState == VoiceInputState.confirming
                          ? 'Edit your response or tap Continue'
                          : 'Type a few words about your day or night...',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Voice input controls (Feature 2.2)
                  _buildVoiceControls(theme),

                  const SizedBox(height: 12),

                  // Continue button
                  ElevatedButton(
                    onPressed: _compassionateReply != null
                        ? null
                        : _handleMoodSubmission,
                    child: const Text('Continue'),
                  ),
                ],
              ),
            ),
          ),

          // Compassionate Reply with Verse Section
          if (_compassionateReply != null) ...[
            const SizedBox(height: 24),
            Card(
              elevation: 2,
              color: theme.colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // PAL's Response Header
                    Row(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'PAL\'s Response',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: theme.colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Compassionate Reply
                    Text(
                      _compassionateReply!,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),

                    // Verse Section
                    if (_verse != null) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 16),

                      // Verse Reference with Translation Label
                      Text(
                        '${_verse!.reference} (${_verse!.translation})',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Verse Text
                      Text(
                        '"${_verse!.text}"',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Verse Context
                      Text(
                        _verse!.context,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer
                              .withOpacity(0.9),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Length Selection or Loading State
                      if (_isSelectingParable) ...[
                        const Divider(),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Preparing your story...',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        const Divider(),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(
                            'Choose a story length:',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onPrimaryContainer,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        StoryLengthRadioSelector(
                          selectedBucket: _selectedLengthBucket,
                          onBucketChanged: (bucket) =>
                              setState(() => _selectedLengthBucket = bucket),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => _handleLengthSelection(_selectedLengthBucket),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            backgroundColor: theme.colorScheme.primary,
                            foregroundColor: theme.colorScheme.onPrimary,
                          ),
                          child: const Text('Start Story'),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Build voice input controls: mic button, listening indicator, re-record.
  Widget _buildVoiceControls(ThemeData theme) {
    switch (_voiceState) {
      case VoiceInputState.idle:
        if (widget.textOnly) return const SizedBox.shrink();
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'or',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              key: const Key('voice_mic_button'),
              onPressed: _compassionateReply != null ? null : _onMicTap,
              icon: const Icon(Icons.mic),
              tooltip: _sttAvailable
                  ? 'Tap to speak'
                  : 'Voice input not available on this platform',
              color: _sttAvailable
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ],
        );

      case VoiceInputState.awaitingPermission:
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Requesting permission...'),
          ],
        );

      case VoiceInputState.listening:
        return Column(
          children: [
            // Pulsing mic indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.mic,
                  key: const Key('voice_listening_indicator'),
                  color: theme.colorScheme.error,
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Listening...',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: _cancelVoiceInput,
                  child: const Text('Cancel'),
                ),
              ],
            ),
            // Partial transcript preview (NOT in TextField per SPEC 2.2)
            if (_partialTranscript.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                _partialTranscript,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        );

      case VoiceInputState.confirming:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _reRecord,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Re-record'),
            ),
          ],
        );

      case VoiceInputState.proceeding:
        return const SizedBox.shrink();
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/providers/app_state_notifier.dart';
import 'package:bible_pal/features/my_pals/select_pals_dialog.dart';
import 'package:bible_pal/features/consent/voice_consent_dialog.dart';
import 'package:bible_pal/models/parable.dart';
import 'package:bible_pal/models/share_record.dart';
import 'package:bible_pal/services/reflection_service.dart';
import 'package:bible_pal/services/voice_consent_gate.dart';
import 'package:bible_pal/core/app_logger.dart';
import 'package:bible_pal/models/journal_entry.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/ambient_sound_type.dart';
import '../../core/story_length_bucket.dart';
import '../../widgets/living_sky_background.dart';
import '../../widgets/scripture_sources_panel.dart';
import '../../widgets/name_prompt_overlay.dart';
import '../../widgets/premium_components.dart';
import '../../theme/living_sky.dart';
import '../paths/next_in_journey_block.dart';
import '../paths/path_launch_context.dart';
import '../paths/path_type.dart';

/// Auto-advance delay after story completion (SPEC Feature 50.6c).
const kAutoAdvanceDelay = Duration(seconds: 4);

/// Parable Player Screen
/// Based on SPEC.md Features 11, 12, 16, 17, 34-37, 50.6c, 50.6d
/// Displays parable with scripture sources, audio playback, and post-story reflection
class ParablePlayerScreen extends ConsumerStatefulWidget {
  /// One-time gentle arrival animation on the Play button. Opt-in only —
  /// passed `true` by normal mood/text/voice entry. Other launches
  /// (Favorites, History, PALs Paths, etc.) leave it false to preserve
  /// existing behavior.
  final bool showArrivalAnimation;

  /// When provided, the player owns the load: it resolves the user's
  /// preferred-length variant of [pendingParable], adds it to history, and
  /// calls [ParablePlayerNotifier.loadParable] from a post-frame callback in
  /// [_ParablePlayerScreenState.initState]. Used by PALs Paths entry to
  /// avoid calling `loadParable` from the path screen context, which
  /// previously hung when iOS audio-session activation collided with
  /// provider-cascade rebuilds of the path screen mid-await.
  ///
  /// Mood/text/voice entries do NOT use this — they pre-load and pass null.
  final Parable? pendingParable;

  /// Companion to [pendingParable]. Carries the path's
  /// [PathLaunchContext] forward so the player still renders
  /// "Next in Your Journey" and `story_completed` telemetry records
  /// `source: 'path'`.
  final PathLaunchContext? pendingLaunchContext;

  const ParablePlayerScreen({
    super.key,
    this.showArrivalAnimation = false,
    this.pendingParable,
    this.pendingLaunchContext,
  });

  @override
  ConsumerState<ParablePlayerScreen> createState() =>
      _ParablePlayerScreenState();
}

class _ParablePlayerScreenState extends ConsumerState<ParablePlayerScreen>
    with TickerProviderStateMixin {
  bool _isFavorited = false;
  bool _isDraggingSlider = false;
  double _dragValue = 0;
  bool _showReflection = false;
  final bool _reflectionDismissed = false;
  bool _isReflectionPlaying = false;
  bool _reflectionAudioPlayed = false;
  bool _hasReflectionAudio = false;
  // Slice 4: surfaced when the reflection resolver returns null
  // (e.g., offline + no cached reflection audio and bundled lookup
  // failed). UI renders a minimal "Connect to play" label instead of
  // the play button.
  bool _reflectionUnavailable = false;
  final ReflectionService _reflectionService = ReflectionService();

  // Separate audio player for reflection (to not interfere with story player)
  AudioPlayer? _reflectionPlayer;

  // Scroll controller for auto-scrolling to reflection
  final ScrollController _scrollController = ScrollController();

  // Ambient audio local UI state
  bool _ambientOn = false;
  AmbientSoundType _ambientType = AmbientSoundType.defaultType;
  double _ambientVol = 0.10;

  // Variant switching: available sibling variants for length/translation chips
  Map<String, Set<String>> _availableVariants = {};

  // Bedtime mode sleep timer
  Timer? _sleepTimer;

  // PALs Paths continuation toggles (session-scoped, SPEC 50.6c/50.6d)
  bool _stayOnPathEnabled = false;
  bool _pauseForReflectionEnabled = false;
  Timer? _autoAdvanceTimer;
  bool _isAutoAdvancing = false;
  bool _sleepTimerFired = false;
  StreamSubscription<PlayerState>? _reflectionCompletionSub;

  bool get _isBedtimeModeActive {
    final appState = ref.read(appStateProvider).valueOrNull;
    return appState?.userPreferences.bedtimeModeEnabled ?? false;
  }

  bool _showNamePrompt = false;

  // One-time arrival animation for the Play button (mood/text/voice entry only).
  AnimationController? _arrivalController;
  Animation<double>? _arrivalScale;
  Animation<double>? _arrivalOpacity;

  // Deferred-load guard: ensures the post-frame load runs at most once
  // even if the State rebuilds for any reason.
  bool _deferredLoadStarted = false;

  @override
  void initState() {
    super.initState();
    _checkIfFavorited();
    _checkReflectionAudioExists();
    _journalFocusNode.addListener(_onJournalFocusChange);
    _loadAmbientState();
    _loadAvailableVariants();
    if (widget.showArrivalAnimation) {
      _initArrivalAnimation();
    }
    if (widget.pendingParable != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _runDeferredLoad();
      });
    }
  }

  /// Player-owned load entry point. Called from a post-frame callback so
  /// that:
  ///   1. The route push has fully settled (we're the active route).
  ///   2. At least one frame has rendered (audio session has had a chance
  ///      to initialize before we hit just_audio's setFilePath).
  ///   3. The previous screen (e.g., path_detail_screen) is no longer in
  ///      focus, so its provider-watch rebuilds can't tear our context
  ///      mid-await.
  ///
  /// Resolves the user's `preferredLengthBucket` against sibling variants
  /// of [widget.pendingParable] when possible, falls back to the path's
  /// chosen story otherwise. After load, refreshes the per-parable UI
  /// state (favorite, reflection availability, variant chip set).
  Future<void> _runDeferredLoad() async {
    if (_deferredLoadStarted) return;
    _deferredLoadStarted = true;

    final parable = widget.pendingParable;
    if (parable == null) return;

    final launchContext = widget.pendingLaunchContext;

    try {
      // Resolve preferred-length variant when one exists AND has bundled
      // audio. Some bibleStoryKeys only have audio for a subset of lengths
      // (e.g., 1094_jonah has audio for short only); resolveVariant would
      // happily return a length-matching sibling whose audioFilePath is "",
      // which then fails to load and dumps the user back to the empty
      // "Tap PAL" fallback. We treat empty audioFilePath as "no usable
      // variant" and fall back to the path's chosen story, which
      // PathService picked specifically as the audio-bundled representative.
      Parable resolved = parable;
      final appState = ref.read(appStateProvider).valueOrNull;
      final savedBucket =
          appState?.userPreferences.preferredLengthBucket ?? 'short';
      if (parable.hasBibleStoryKey && parable.storyLength != savedBucket) {
        final parableService =
            await ref.read(parableServiceProvider.future);
        final match = await parableService.resolveVariant(
          current: parable,
          storyLength: savedBucket,
          languageStyle: parable.languageStyle,
        );
        if (match != null &&
            match.audioFilePath != null &&
            match.audioFilePath!.isNotEmpty) {
          resolved = match;
        }
      }
      if (!mounted) return;

      // Keep session-scoped bucket in sync with what we actually loaded.
      final loadedBucket = StoryLengthBucket.fromJson(
        resolved.storyLength ?? savedBucket,
      );
      ref.read(sessionLengthBucketProvider.notifier).state = loadedBucket;

      await ref.read(appStateProvider.notifier).addToHistory(resolved);
      if (!mounted) return;

      final notifier = ref.read(parablePlayerProvider.notifier);
      final success = await notifier.loadParable(
        resolved,
        launchContext: launchContext,
      );
      if (!mounted) return;

      if (!success) {
        final state = ref.read(parablePlayerProvider);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.errorMessage ??
              'This story needs an internet connection the first time you play it.'),
          duration: const Duration(seconds: 4),
        ));
        return;
      }

      // Refresh per-parable UI bits now that currentParable is set.
      _checkIfFavorited();
      _checkReflectionAudioExists();
      _loadAvailableVariants();
    } catch (e) {
      debugPrint('[ParablePlayer] deferred load error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Could not open this story: $e'),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  /// Wraps the Play button in a one-time scale+fade arrival animation.
  /// Returns the child unchanged when no animation is active (zero overhead
  /// for non-mood entry points).
  Widget _wrapWithArrivalAnimation(Widget child) {
    final controller = _arrivalController;
    final scale = _arrivalScale;
    final opacity = _arrivalOpacity;
    if (controller == null || scale == null || opacity == null) {
      return child;
    }
    return AnimatedBuilder(
      animation: controller,
      builder: (context, c) {
        return Opacity(
          opacity: opacity.value,
          child: Transform.scale(scale: scale.value, child: c),
        );
      },
      child: child,
    );
  }

  void _initArrivalAnimation() {
    final controller = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    // Scale: gentle emergence 0.85 → 1.03 (0–55%) → 1.0 (55–100%).
    _arrivalScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.85, end: 1.03)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.03, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 45,
      ),
    ]).animate(controller);
    // Opacity: 0 → 1 over the first 40%.
    _arrivalOpacity = CurvedAnimation(
      parent: controller,
      curve: const Interval(0.0, 0.40, curve: Curves.easeOut),
    );
    _arrivalController = controller;
    controller.forward().whenComplete(() {
      controller.dispose();
      if (mounted) {
        setState(() {
          _arrivalController = null;
          _arrivalScale = null;
          _arrivalOpacity = null;
        });
      } else {
        _arrivalController = null;
        _arrivalScale = null;
        _arrivalOpacity = null;
      }
    });
  }

  /// Load available sibling variants for the current story so the variant
  /// control chips know which options to enable/disable.
  Future<void> _loadAvailableVariants() async {
    final playerState = ref.read(parablePlayerProvider);
    final parable = playerState.currentParable;
    if (parable == null || !parable.hasBibleStoryKey) return;

    final parableService = await ref.read(parableServiceProvider.future);
    final variants = await parableService.getAvailableVariants(parable);
    if (mounted) {
      setState(() => _availableVariants = variants);
    }
  }

  /// Switch the current story to a different length/translation variant.
  ///
  /// Preserves playback state: playing → auto-play new variant;
  /// paused → load but stay paused.
  ///
  /// Uses [ParablePlayerNotifier.switchVariant] instead of [loadParable]
  /// so display-only fields (verse, palResponseText, launchContext) are
  /// preserved via copyWith — no layout jump.
  Future<void> _switchVariant({
    required String storyLength,
    required String languageStyle,
  }) async {
    final playerNotifier = ref.read(parablePlayerProvider.notifier);
    final playerState = ref.read(parablePlayerProvider);
    final current = playerState.currentParable;
    if (current == null) return;

    // Already on this variant — no-op.
    if (current.storyLength == storyLength &&
        current.languageStyle == languageStyle) {
      return;
    }

    // Capture playback state BEFORE stopping audio.
    final wasPlaying = playerNotifier.isPlaying;

    final parableService = await ref.read(parableServiceProvider.future);
    final newVariant = await parableService.resolveVariant(
      current: current,
      storyLength: storyLength,
      languageStyle: languageStyle,
    );

    if (newVariant == null || !mounted) return;

    // Persist preference changes (fire-and-forget).
    final appStateNotifier = ref.read(appStateProvider.notifier);
    if (storyLength != current.storyLength) {
      appStateNotifier.updatePreferredLengthBucket(storyLength);
    }
    if (languageStyle != current.languageStyle) {
      appStateNotifier.updateLanguageStyle(languageStyle);
    }

    logEvent('player_variant_switch', {
      'story_id': current.storyId,
      'from_length': current.storyLength,
      'to_length': storyLength,
      'from_lang': current.languageStyle,
      'to_lang': languageStyle,
      'was_playing': wasPlaying,
    });

    // switchVariant stops audio + ambient, then loads new audio/text
    // via copyWith (preserves verse, palResponseText, launchContext).
    final success = await playerNotifier.switchVariant(newVariant);
    if (!mounted) return;

    // Reset ambient UI state — switchVariant force-stops the ambient
    // service, so the toggle must reflect that.
    if (_ambientOn) {
      _ambientOn = false;
      final sp = await SharedPreferences.getInstance();
      await sp.remove('settings.backgroundSoundOn');
    }

    if (success && wasPlaying) {
      await playerNotifier.play();
    }

    // Refresh reflection audio availability + favorite state.
    _checkReflectionAudioExists();
    _checkIfFavorited();

    if (mounted) {
      setState(() => _showReflection = false);
    }
  }

  /// Variant controls — compact length + translation chip rows.
  ///
  /// Visual system matches ambient controls (SPEC Feature 47 locked palette):
  /// - Container: `foreground.subtleSurface` / `subtleBorder` glass pane
  /// - Selected chip: solid `warmHighlight` fill + dark w600 label
  /// - Unselected chip: `subtleSurface` + subtle border
  /// - Disabled chip: reduced opacity, no tap handler
  ///
  /// Hidden for Creative stories (no bibleStoryKey → no sibling variants).
  Widget _buildVariantControls(ThemeData theme, ParablePlayerState playerState) {
    final current = playerState.currentParable;
    if (current == null || !current.hasBibleStoryKey) {
      return const SizedBox.shrink();
    }
    if (_availableVariants.isEmpty) return const SizedBox.shrink();

    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final fg = palette.foreground;

    // Length chips — ordered short → full → long.
    final lengthBuckets = [
      StoryLengthBucket.short,
      StoryLengthBucket.full,
      StoryLengthBucket.long,
    ];

    // Translation chips — ordered WEB → KJV.
    const translations = ['WEB', 'KJV'];

    Widget buildChip({
      required String label,
      required bool isSelected,
      required bool isAvailable,
      required VoidCallback onTap,
    }) {
      return ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: !isAvailable
                ? fg.secondaryText.withValues(alpha: 0.35)
                : isSelected
                    ? const Color(0xFF1A1A1A)
                    : fg.secondaryText,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            letterSpacing: 0.2,
          ),
        ),
        selected: isSelected,
        selectedColor: palette.warmHighlight,
        backgroundColor: fg.subtleSurface,
        disabledColor: fg.subtleSurface,
        side: BorderSide(
          color: isSelected
              ? palette.warmHighlight
              : !isAvailable
                  ? fg.subtleBorder.withValues(alpha: 0.35)
                  : fg.subtleBorder,
          width: 1,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        showCheckmark: false,
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        onSelected: isAvailable && !isSelected
            ? (_) => onTap()
            : null,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fg.subtleSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.subtleBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Length row
          Row(
            children: [
              Icon(Icons.straighten, size: 14, color: fg.secondaryIcon),
              const SizedBox(width: 8),
              Text(
                'Length',
                style: TextStyle(
                  color: fg.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: lengthBuckets.map((bucket) {
              final isSelected = current.storyLength == bucket.name;
              final langSet = _availableVariants[bucket.name];
              final isAvailable =
                  langSet != null && langSet.contains(current.languageStyle);
              return buildChip(
                label: bucket.displayLabel,
                isSelected: isSelected,
                isAvailable: isAvailable,
                onTap: () => _switchVariant(
                  storyLength: bucket.name,
                  languageStyle: current.languageStyle,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          // Translation row
          Row(
            children: [
              Icon(Icons.translate, size: 14, color: fg.secondaryIcon),
              const SizedBox(width: 8),
              Text(
                'Translation',
                style: TextStyle(
                  color: fg.secondaryText,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: translations.map((lang) {
              final isSelected = current.languageStyle == lang;
              final currentLength = current.storyLength ?? 'short';
              final langSet = _availableVariants[currentLength];
              final isAvailable = langSet != null && langSet.contains(lang);
              return buildChip(
                label: lang,
                isSelected: isSelected,
                isAvailable: isAvailable,
                onTap: () => _switchVariant(
                  storyLength: currentLength,
                  languageStyle: lang,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAmbientState() async {
    final sp = await SharedPreferences.getInstance();
    // Ambient toggle is session-only — always starts OFF on every screen
    // entry (SPEC Feature 49 session-reset). Clear the persisted key so
    // startIfEnabled() (called by the player notifier on play) does not
    // auto-resume ambient from a previous visit.
    await sp.remove('settings.backgroundSoundOn');
    final ambient = ref.read(ambientAudioServiceProvider);
    await ambient.forceStop();
    if (!mounted) return;
    setState(() {
      // _ambientOn intentionally NOT restored — starts false.
      _ambientType = AmbientSoundType.fromString(
          sp.getString('settings.ambientSoundType'));
      _ambientVol = sp.getDouble('settings.ambientVolume') ?? 0.10;
    });
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    _autoAdvanceTimer?.cancel();
    _reflectionCompletionSub?.cancel();
    _arrivalController?.dispose();
    _scrollController.dispose();
    _reflectionPlayer?.dispose();
    _journalFocusNode.removeListener(_onJournalFocusChange);
    _journalFocusNode.dispose();
    _journalController.dispose();
    super.dispose();
  }

  /// Check if pre-generated reflection audio exists for current parable
  Future<void> _checkReflectionAudioExists() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final reflectionPath = _getReflectionAudioPath(playerState.currentParable!);
    if (reflectionPath == null) return;

    try {
      // Try to load the asset to check if it exists
      await rootBundle.load('assets/stories/$reflectionPath');
      if (mounted) {
        setState(() => _hasReflectionAudio = true);
      }
    } catch (_) {
      // Asset doesn't exist - reflection audio not available
      if (mounted) {
        setState(() => _hasReflectionAudio = false);
      }
    }
  }

  /// Get reflection audio path from parable metadata or derive from story audio path
  /// Convention: parable_001_joyful_5min.mp3 → parable_001_joyful_5min.reflection.mp3
  String? _getReflectionAudioPath(Parable parable) {
    // Prefer explicit reflection path from manifest
    if (parable.reflectionAudioPath != null) {
      return parable.reflectionAudioPath;
    }
    // Fall back to convention-based derivation
    final storyAudioPath = parable.audioFilePath;
    if (storyAudioPath == null) return null;
    if (!storyAudioPath.endsWith('.mp3')) return null;
    return storyAudioPath.replaceAll('.mp3', '.reflection.mp3');
  }

  void _onPlaybackCompleted() async {
    // Check if we should show the post-first-story name prompt
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState != null) {
      final userName = appState.userPreferences.userName;
      final shouldShow = await NamePromptOverlay.shouldShow(userName);
      if (shouldShow && mounted) {
        setState(() => _showNamePrompt = true);
      }
    }

    if (!_reflectionDismissed) {
      setState(() => _showReflection = true);

      // Auto-scroll to show the reflection
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOut,
          );
        }
      });

      // SPEC Feature 50.6d: Pause for Reflection opt-in autoplay.
      // When enabled, auto-play reflection instead of waiting for
      // user tap. After reflection completes, auto-advance starts
      // if Stay on the Path is also enabled.
      if (_pauseForReflectionEnabled && _hasReflectionAudio) {
        await _autoPlayReflectionThenMaybeAdvance();
      } else {
        // Default: no auto-play (ADR-010 baseline).
        // If Stay on the Path is ON without Pause for Reflection,
        // start the auto-advance countdown immediately.
        _startAutoAdvanceIfEnabled();
      }
    } else {
      // Reflection dismissed — skip straight to auto-advance if enabled.
      _startAutoAdvanceIfEnabled();
    }

    _startBedtimeSleepTimerIfNeeded();
  }

  /// Start sleep timer if bedtime mode is enabled.
  /// After the timer expires, fade out any playing audio and stop.
  void _startBedtimeSleepTimerIfNeeded() {
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) return;
    if (!appState.userPreferences.bedtimeModeEnabled) return;

    _sleepTimer?.cancel();
    final minutes = appState.userPreferences.sleepTimerMinutes;

    _sleepTimer = Timer(Duration(minutes: minutes), () async {
      if (!mounted) return;
      // Bedtime takes priority over auto-advance (SPEC 50.6c).
      setState(() => _sleepTimerFired = true);
      _cancelAutoAdvance('bedtime_timer');
      final playerNotifier = ref.read(parablePlayerProvider.notifier);
      await playerNotifier.audioService.fadeOutAndStop();
      // Also stop reflection audio if playing
      _reflectionPlayer?.stop();
    });
  }

  /// SPEC Feature 50.6d: Auto-play reflection then optionally auto-advance.
  /// Called when Pause for Reflection is enabled and reflection audio exists.
  /// After reflection completes, starts auto-advance if Stay on the Path is ON.
  Future<void> _autoPlayReflectionThenMaybeAdvance() async {
    // Check voice consent before auto-playing reflection.
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) {
      _startAutoAdvanceIfEnabled();
      return;
    }
    final gateResult =
        VoiceConsentGate.checkStoryNarration(appState.userPreferences);
    if (gateResult != VoiceGateResult.allowed) {
      // Voice narration disabled/needs consent — fall back to manual.
      _startAutoAdvanceIfEnabled();
      return;
    }

    // Listen for reflection completion BEFORE starting playback.
    // Cancel any existing subscription to prevent duplicates.
    await _reflectionCompletionSub?.cancel();
    _reflectionCompletionSub = null;

    _reflectionPlayer ??= AudioPlayer();
    _reflectionCompletionSub =
        _reflectionPlayer!.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _reflectionCompletionSub?.cancel();
        _reflectionCompletionSub = null;
        if (mounted) {
          setState(() => _isReflectionPlaying = false);
          // Reflection done — now start auto-advance if enabled.
          _startAutoAdvanceIfEnabled();
        }
      }
    });

    // Start reflection playback.
    await _playReflectionAudio();
  }

  /// Cancel any pending auto-advance countdown and reset state.
  void _cancelAutoAdvance(String reason) {
    if (!_isAutoAdvancing) return;
    _autoAdvanceTimer?.cancel();
    _autoAdvanceTimer = null;
    if (mounted) {
      setState(() => _isAutoAdvancing = false);
    }
    final playerState = ref.read(parablePlayerProvider);
    logEvent('auto_advance_cancelled', {
      'story_id': playerState.currentParable?.storyId,
      'reason': reason,
    });
  }

  /// SPEC Feature 50.6c: Start auto-advance countdown if Stay on the Path
  /// is enabled and conditions are met.
  void _startAutoAdvanceIfEnabled() {
    if (!_stayOnPathEnabled) return;
    if (_sleepTimerFired) return;
    if (!mounted) return;

    final playerState = ref.read(parablePlayerProvider);
    final launchContext = playerState.launchContext;
    if (launchContext == null) return;

    // Check if there IS a next story before starting countdown.
    final pathServiceAsync = ref.read(pathServiceProvider);
    final pathService = pathServiceAsync.valueOrNull;
    if (pathService == null) return;

    final next = pathService.getNextInPath(
      launchContext.pathType,
      launchContext.pathId,
      launchContext.positionInPath,
    );
    if (next == null) return; // End of path — no auto-advance.

    // Cancel any existing timer (idempotency).
    _autoAdvanceTimer?.cancel();

    setState(() => _isAutoAdvancing = true);

    logEvent('auto_advance_started', {
      'story_id': playerState.currentParable?.storyId,
      'path_type': launchContext.pathType.wireId,
      'path_id': launchContext.pathId,
      'position': launchContext.positionInPath,
    });

    _autoAdvanceTimer = Timer(kAutoAdvanceDelay, _executeAutoAdvance);
  }

  /// Execute the actual auto-advance: load and play the next story.
  Future<void> _executeAutoAdvance() async {
    if (!mounted) return;
    setState(() => _isAutoAdvancing = false);

    final playerState = ref.read(parablePlayerProvider);
    final launchContext = playerState.launchContext;
    if (launchContext == null) return;

    // Resolve next story from PathService.
    final pathService = await ref.read(pathServiceProvider.future);
    final nextParable = pathService.getNextInPath(
      launchContext.pathType,
      launchContext.pathId,
      launchContext.positionInPath,
    );
    if (nextParable == null || !mounted) return;

    final nextLaunchContext = PathLaunchContext(
      pathType: launchContext.pathType,
      pathId: launchContext.pathId,
      positionInPath: launchContext.positionInPath + 1,
    );

    // Resolve matching variant (same length + language as current).
    final current = playerState.currentParable;
    Parable storyToLoad = nextParable;
    if (current != null) {
      final parableService = await ref.read(parableServiceProvider.future);
      final variant = await parableService.resolveVariant(
        current: nextParable,
        storyLength: current.storyLength ?? 'short',
        languageStyle: current.languageStyle,
      );
      if (variant != null) storyToLoad = variant;
    }

    if (!mounted) return;

    // Add to history.
    final appStateNotifier = ref.read(appStateProvider.notifier);
    await appStateNotifier.addToHistory(storyToLoad);

    // Reset UI state for the new story.
    _reflectionCompletionSub?.cancel();
    _reflectionCompletionSub = null;
    _reflectionPlayer?.stop();
    _sleepTimer?.cancel();
    _journalController.clear();
    setState(() {
      _showReflection = false;
      _reflectionAudioPlayed = false;
      _isReflectionPlaying = false;
      _hasReflectionAudio = false;
      _showNamePrompt = false;
      _journalSaved = false;
      _journalEditing = false;
      _sleepTimerFired = false;
    });

    // Load the new parable with the next launch context.
    final playerNotifier = ref.read(parablePlayerProvider.notifier);
    final success = await playerNotifier.loadParable(
      storyToLoad,
      launchContext: nextLaunchContext,
    );

    if (!mounted) return;

    if (success) {
      // Refresh state for the new story.
      _checkReflectionAudioExists();
      _checkIfFavorited();
      _loadAvailableVariants();

      // Auto-play the next story.
      await _handlePlay(playerNotifier);

      // Scroll back to top.
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }

      logEvent('auto_advance_played', {
        'story_id': storyToLoad.storyId,
        'path_type': nextLaunchContext.pathType.wireId,
        'path_id': nextLaunchContext.pathId,
        'position': nextLaunchContext.positionInPath,
      });
    } else {
      // Load failed — cancel auto-advance gracefully.
      logEvent('auto_advance_cancelled', {
        'story_id': storyToLoad.storyId,
        'reason': 'load_failure',
      });
    }
  }

  /// Play pre-generated reflection audio. Slice 4: routes through
  /// [ParableService.getReflectionAudioFile] so reflection audio
  /// flows through the same cache → bundled → R2 cascade as story
  /// audio on Android. Surfaces "Connect to play" when the resolver
  /// returns null (e.g., offline + nothing cached + nothing bundled).
  Future<void> _playReflectionAudio() async {
    final playerState = ref.read(parablePlayerProvider);
    final parable = playerState.currentParable;
    if (parable == null) return;
    if (_getReflectionAudioPath(parable) == null) return;

    try {
      final parableService = await ref.read(parableServiceProvider.future);
      final file = await parableService.getReflectionAudioFile(parable);
      // User may have exited the player while the resolver was in
      // flight — drop the result silently.
      if (!mounted) return;

      if (file == null) {
        logEvent('reflection_unavailable', {'story_id': parable.storyId});
        setState(() {
          _isReflectionPlaying = false;
          _reflectionUnavailable = true;
        });
        return;
      }

      _reflectionPlayer ??= AudioPlayer();
      await _reflectionPlayer!.setFilePath(file.path);
      // Second mounted guard: just_audio's setFilePath is awaitable
      // and dispose() may have run during the load.
      if (!mounted) {
        await _reflectionPlayer?.stop();
        return;
      }

      logEvent('reflection_start', {'story_id': parable.storyId});

      setState(() {
        _isReflectionPlaying = true;
        _reflectionAudioPlayed = true;
        _reflectionUnavailable = false;
      });

      await _reflectionPlayer!.play();

      // Listen for completion
      _reflectionPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() => _isReflectionPlaying = false);
          }
        }
      });
    } catch (e) {
      if (!mounted) return;
      debugPrint('[ReflectionAudio] Error playing: $e');

      logEvent('reflection_fail', {
        'story_id': parable.storyId,
        'error_type': e.runtimeType.toString(),
      }, level: LogLevel.error);

      setState(() {
        _isReflectionPlaying = false;
        _hasReflectionAudio = false; // Mark as unavailable
      });
    }
  }

  /// Stop reflection audio playback
  Future<void> _stopReflectionAudio() async {
    if (_reflectionPlayer != null) {
      await _reflectionPlayer!.stop();
      setState(() => _isReflectionPlaying = false);
    }
  }

  /// Replay reflection audio
  Future<void> _replayReflectionAudio() async {
    if (_reflectionPlayer != null) {
      await _reflectionPlayer!.seek(Duration.zero);
      await _reflectionPlayer!.play();
      setState(() => _isReflectionPlaying = true);
    } else {
      await _playReflectionAudio();
    }
  }

  /// Handle play reflection button with consent check
  Future<void> _handlePlayReflection() async {
    _cancelAutoAdvance('reflection');
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) return;

    final gateResult =
        VoiceConsentGate.checkStoryNarration(appState.userPreferences);

    switch (gateResult) {
      case VoiceGateResult.allowed:
        await _playReflectionAudio();
        break;

      case VoiceGateResult.needsConsent:
        if (!mounted) return;
        final consentResult = await VoiceConsentDialog.show(context);
        if (consentResult == VoiceConsentResult.enabled) {
          await _playReflectionAudio();
        }
        break;

      case VoiceGateResult.blocked:
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Voice narration is disabled. Enable it in Settings.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;
    }
  }

  Future<void> _checkIfFavorited() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable != null) {
      final appStateNotifier = ref.read(appStateProvider.notifier);
      final favorited = await appStateNotifier
          .isFavorited(playerState.currentParable!.storyId);
      if (mounted) {
        setState(() {
          _isFavorited = favorited;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final appStateNotifier = ref.read(appStateProvider.notifier);

    if (_isFavorited) {
      await appStateNotifier
          .removeFavorite(playerState.currentParable!.storyId);
      if (mounted) {
        setState(() => _isFavorited = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Removed from favorites'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } else {
      await appStateNotifier.addFavorite(playerState.currentParable!);
      if (mounted) {
        setState(() => _isFavorited = true);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Added to favorites'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _shareWithPals() async {
    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) return;

    final appStateAsync = ref.read(appStateProvider);
    final pals = appStateAsync.valueOrNull?.pals ?? [];

    if (!mounted) return;

    // Show dialog to select PALs
    final selectedPalIds = await showDialog<List<String>>(
      context: context,
      builder: (context) => SelectPalsDialog(pals: pals),
    );

    if (selectedPalIds == null || selectedPalIds.isEmpty) return;

    final appStateNotifier = ref.read(appStateProvider.notifier);
    final parable = playerState.currentParable!;

    // Share with each selected PAL
    for (final palId in selectedPalIds) {
      final shareId = const Uuid().v4();
      final share = ShareRecord(
        shareId: shareId,
        storyId: parable.storyId,
        storyTitle: parable.title,
        toPalId: palId,
        timestamp: DateTime.now(),
        direction: ShareDirection.sent,
      );

      await appStateNotifier.shareStoryWithPal(share);
    }

    // Invoke platform share sheet with story content
    final shareService = ref.read(shareServiceProvider);
    await shareService.shareParable(
      parable: parable,
      storyText: playerState.parableText,
    );

    if (!mounted) return;

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          selectedPalIds.length == 1
              ? 'Shared with 1 PAL'
              : 'Shared with ${selectedPalIds.length} PALs',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Handle play button press with voice consent check.
  /// Shows VoiceConsentDialog if user hasn't consented yet.
  Future<void> _handlePlay(ParablePlayerNotifier playerNotifier) async {
    final result = await playerNotifier.play();

    if (!mounted) return;

    switch (result) {
      case VoicePlayResult.played:
        // Audio started successfully, nothing more to do
        break;

      case VoicePlayResult.needsConsent:
        // Show consent dialog
        final consentResult = await VoiceConsentDialog.show(context);

        if (!mounted) return;

        // If user enabled narration, retry play
        if (consentResult == VoiceConsentResult.enabled) {
          // Re-check consent by playing again
          await playerNotifier.play();
        }
        // If declined or dismissed, stay in text-only mode (no action needed)
        break;

      case VoicePlayResult.disabled:
        // User explicitly disabled narration - show snackbar as gentle reminder
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Story narration is disabled. Enable it in Settings.'),
            duration: Duration(seconds: 3),
          ),
        );
        break;

      case VoicePlayResult.noParable:
        // Should not happen since button is only visible when parable is loaded
        break;

      case VoicePlayResult.error:
        // Error message is set in state, will be displayed by UI
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final playerState = ref.watch(parablePlayerProvider);
    final playerNotifier = ref.watch(parablePlayerProvider.notifier);
    final theme = Theme.of(context);
    // Phase 3.2 global contrast pass — resolve the sky palette once at
    // build time so text surfaces below route through the enforced
    // foreground palette (primary/secondary/tertiary + shadows).
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    // Detect playback completion and trigger reflection.
    // ref.listen inside build() is the correct Riverpod API — subscription is
    // automatically managed (no manual guard or cancel needed).
    ref.listen(parablePlayerProvider, (prev, next) {
      final wasCompleted = prev?.playbackCompleted ?? false;
      if (!wasCompleted && next.playbackCompleted && mounted) {
        _onPlaybackCompleted();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        // CRITICAL back-nav ordering (Phase 3.2 polish pass):
        // POP the route FIRST, then tear audio + state down AFTER.
        //
        // If we call `clear()` before `pop()`, Riverpod flips
        // `currentParable` to null and the widget rebuilds with
        // its "Tap PAL to start a story" empty state before the
        // pop transition completes. The user briefly sees that
        // empty state and perceives it as a broken back-nav
        // (appearing on a wrong screen). Popping first disposes
        // the widget before Riverpod can trigger the rebuild, so
        // the empty-state flash never paints.
        //
        // The notifier + reflection player live OUTSIDE the
        // widget tree, so calling them after pop is safe — their
        // cleanup just runs in the background while the user is
        // already on the previous route.
        _cancelAutoAdvance('back_nav');
        _autoAdvanceTimer?.cancel();
        _reflectionCompletionSub?.cancel();
        // Wipe player state BEFORE pop so the main menu's panel
        // AnimatedSwitcher rebuilds in idle mode under the player while
        // the back transition runs — eliminates the post-pop layout
        // shift. clear() now sets state synchronously on its first line;
        // we fire-and-forget the audio stop so pop isn't blocked.
        unawaited(playerNotifier.clear());
        // Reflection player doesn't need setState (_stopReflectionAudio
        // would, so we call stop() directly to skip the setState branch
        // on a disposing widget).
        unawaited(_reflectionPlayer?.stop() ?? Future<void>.value());
        Navigator.of(context).pop();
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
        ),
        body: Stack(
          children: [
            const LivingSkyBackground(),
            SafeArea(
              child: playerState.currentParable == null
                  ? (playerState.errorMessage != null
                      // Real error: surface the message + retry path.
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.auto_stories,
                                  size: 48,
                                  color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(height: 16),
                              Text(
                                playerState.errorMessage!,
                                style: theme.textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                              if (playerState.canRetry)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: TextButton(
                                    onPressed: () => Navigator.of(context)
                                        .pushNamedAndRemoveUntil(
                                            '/main_menu', (_) => false),
                                    child: const Text('Try Again'),
                                  ),
                                ),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: () => Navigator.of(context)
                                    .pushNamedAndRemoveUntil(
                                        '/main_menu', (_) => false),
                                child: const Text('Back to PAL'),
                              ),
                            ],
                          ),
                        )
                      // No parable + no error = transient state during the
                      // deferred-load gap or during the back-pop animation
                      // (clear() races with pop). Show the LivingSky
                      // background only — no flashing "Tap PAL" UI.
                      : const SizedBox.shrink())
                  : Column(
                      children: [
                        // Scrollable content area
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                            child: Column(
                              children: [
                                // Story title — large, centered.
                                // Phase 3.2 contrast pass: routes
                                // through foreground palette for
                                // phase-aware white + shadow on all
                                // sky phases.
                                Text(
                                  playerState.currentParable!.title,
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: palette.foreground.primaryText,
                                    shadows: palette.foreground.textShadow,
                                  ),
                                  textAlign: TextAlign.center,
                                ),

                                // Mood-flow verse (from PAL's mood response)
                                if (playerState.verse != null) ...[
                                  const SizedBox(height: 20),
                                  Container(
                                    padding: const EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer.withOpacity(0.3),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: theme.colorScheme.outline.withOpacity(0.3)),
                                    ),
                                    child: Column(
                                      children: [
                                        Text(
                                          '"${playerState.verse!.text}"',
                                          style: theme.textTheme.bodyMedium?.copyWith(
                                            fontStyle: FontStyle.italic,
                                            color: palette.foreground.primaryText,
                                            shadows: palette.foreground.subtitleShadow,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '— ${playerState.verse!.reference}',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            color: palette.foreground.tertiaryText,
                                            shadows: palette.foreground.captionShadow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                const SizedBox(height: 32),

                                // LARGE Play/Pause Button — glowing orb style
                                _wrapWithArrivalAnimation(
                                  GlowingOrbButton(
                                    icon: playerNotifier.isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 80,
                                    onPressed: () async {
                                      _cancelAutoAdvance('manual_control');
                                      if (playerNotifier.isPlaying) {
                                        playerNotifier.pause();
                                      } else {
                                        await _handlePlay(playerNotifier);
                                      }
                                    },
                                  ),
                                ),

                                const SizedBox(height: 8),

                                // Seek slider
                                StreamBuilder<Duration>(
                                  stream: playerNotifier.positionStream,
                                  builder: (context, snapshot) {
                                    final position = snapshot.data ?? Duration.zero;
                                    final duration =
                                        playerNotifier.duration ?? Duration.zero;
                                    final max = duration.inMilliseconds.toDouble();
                                    final displayValue = _isDraggingSlider
                                        ? _dragValue
                                        : position.inMilliseconds
                                            .toDouble()
                                            .clamp(0.0, max);

                                    final sliderPalette = LivingSky.getPalette(LivingSky.getPhase());
                                    return Column(
                                      children: [
                                        SliderTheme(
                                          data: SliderThemeData(
                                            activeTrackColor: sliderPalette.orbGlowColor,
                                            inactiveTrackColor: sliderPalette.cardBorder,
                                            thumbColor: sliderPalette.orbGlowColor,
                                            overlayColor: sliderPalette.orbGlowColor.withOpacity(0.2),
                                            trackHeight: 4,
                                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                                            trackShape: const RoundedRectSliderTrackShape(),
                                          ),
                                          child: Slider(
                                            value: displayValue,
                                            max: max > 0 ? max : 1,
                                            onChangeStart: (v) {
                                              setState(() {
                                                _isDraggingSlider = true;
                                                _dragValue = v;
                                              });
                                            },
                                            onChanged: (v) {
                                              setState(() => _dragValue = v);
                                            },
                                            onChangeEnd: (v) {
                                              playerNotifier.seek(
                                                Duration(milliseconds: v.toInt()),
                                              );
                                              setState(() => _isDraggingSlider = false);
                                            },
                                          ),
                                        ),
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 16,
                                          ),
                                          child: Row(
                                            mainAxisAlignment:
                                                MainAxisAlignment.spaceBetween,
                                            children: [
                                              Text(
                                                _formatDuration(
                                                  _isDraggingSlider
                                                      ? Duration(milliseconds: _dragValue.toInt())
                                                      : position,
                                                ),
                                                style: TextStyle(
                                                  color: palette.foreground.secondaryText,
                                                  fontSize: 13,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                  shadows: palette.foreground.subtitleShadow,
                                                ),
                                              ),
                                              Text(
                                                _formatDuration(duration),
                                                style: TextStyle(
                                                  color: palette.foreground.secondaryText,
                                                  fontSize: 13,
                                                  fontFeatures: const [FontFeature.tabularFigures()],
                                                  shadows: palette.foreground.subtitleShadow,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    );
                                  },
                                ),

                                // Download progress (Android-only, R2 audio
                                // delivery — SPEC Feature 27, Cloud Foundation v1).
                                if (playerState.downloadProgress != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        SizedBox(
                                          width: 48,
                                          height: 48,
                                          child: CircularProgressIndicator(
                                            value: playerState.downloadProgress,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Downloading ${(playerState.downloadProgress! * 100).round()}%',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: palette.foreground.secondaryText,
                                            shadows: palette.foreground.subtitleShadow,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else if (playerState.isLoading)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 16),
                                    child: CircularProgressIndicator(),
                                  ),
                                if (playerState.errorMessage != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          playerState.errorMessage!,
                                          style: TextStyle(
                                              color: theme.colorScheme.error),
                                          textAlign: TextAlign.center,
                                        ),
                                        if (playerState.canRetry &&
                                            playerState.currentParable != null)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 12),
                                            child: TextButton(
                                              onPressed: () {
                                                playerNotifier.loadParable(
                                                    playerState
                                                        .currentParable!);
                                              },
                                              child: const Text('Try Again'),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),

                                const SizedBox(height: 16),

                                // Scripture Sources panel (SPEC.md Feature 12) — glass capsule
                                GlassCapsule(
                                  padding: const EdgeInsets.all(4),
                                  borderRadius: 16,
                                  child: ScriptureSourcesPanel(
                                    parable: playerState.currentParable!,
                                    playbackCompleted: playerState.playbackCompleted,
                                    onReadScriptureTapped: () {
                                      Navigator.of(context).pushNamed('/scripture_reader');
                                    },
                                  ),
                                ),

                                // Story variant controls (length + translation)
                                _buildVariantControls(theme, playerState),

                                // Ambient Sound Controls
                                _buildAmbientControls(theme),

                                // PALs Paths continuation toggles (SPEC 50.6c/50.6d)
                                _buildPathContinuationToggles(theme, playerState),

                                const SizedBox(height: 16),

                                // Action buttons — primary + glass hierarchy
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    // Read Story — glass (same style as siblings)
                                    GlassButton.icon(
                                      icon: Icons.menu_book,
                                      label: 'Read Story',
                                      onPressed: () => Navigator.of(context).pushNamed('/story_reader'),
                                    ),

                                    // Favorite — glass
                                    GlassButton.icon(
                                      icon: _isFavorited ? Icons.favorite : Icons.favorite_border,
                                      label: _isFavorited ? 'Favorited' : 'Favorite',
                                      onPressed: _toggleFavorite,
                                    ),

                                    // Share with a PAL — glass
                                    GlassButton.icon(
                                      icon: Icons.share,
                                      label: 'Share with a PAL',
                                      onPressed: _shareWithPals,
                                    ),

                                    // Share a clip — glass
                                    Builder(builder: (context) {
                                      return GlassButton.icon(
                                        icon: Icons.format_quote,
                                        label: 'Share a clip',
                                        onPressed: () async {
                                          final playerState = ref.read(parablePlayerProvider);
                                          if (playerState.currentParable == null) return;
                                          final box = context.findRenderObject() as RenderBox?;
                                          final origin = box != null
                                              ? box.localToGlobal(Offset.zero) & box.size
                                              : null;
                                          try {
                                            final shareService = ref.read(shareServiceProvider);
                                            await shareService.shareClip(
                                              parable: playerState.currentParable!,
                                              storyText: playerState.parableText,
                                              sharePositionOrigin: origin,
                                            );
                                          } catch (e) {
                                            if (!context.mounted) return;
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(content: Text('Unable to share: $e')),
                                            );
                                          }
                                        },
                                      );
                                    }),
                                  ],
                                ),

                                // Add to Journal — always visible (SPEC Feature 40)
                                _buildJournalAction(theme, playerState),

                                // Post-Story Reflection (SPEC.md Features #34-36)
                                _buildReflectionSection(theme),

                                // Auto-advance countdown OR Next in Journey block
                                if (_isAutoAdvancing)
                                  _buildAutoAdvanceCountdown(theme)
                                else
                                  const NextInJourneyBlock(),

                                const SizedBox(height: 24),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            // Bedtime mode dim overlay
            if (_isBedtimeModeActive)
              Positioned.fill(
                child: IgnorePointer(
                  child: Container(
                    color: Colors.black.withOpacity(0.3),
                  ),
                ),
              ),
            // Post-first-story name prompt
            if (_showNamePrompt)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: SafeArea(
                  child: NamePromptOverlay(
                    onDismiss: () {
                      if (mounted) setState(() => _showNamePrompt = false);
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Build the post-story reflection section
  /// Only shows when:
  /// - Playback has completed
  /// Ambient sound controls — toggle, type selector, volume slider.
  ///
  /// Visual system (SPEC Feature 47 locked palette):
  /// - Container reads as a single subtle glass pane via
  ///   `foreground.subtleSurface` / `subtleBorder`.
  /// - Selected chip: solid `warmHighlight` fill + dark w600 label —
  ///   unmistakable across every phase.
  /// - Unselected chip: same `subtleSurface` family as the container
  ///   but with a slightly stronger border, so inactive chips read as
  ///   "quietly present" rather than washed out.
  /// - Slider and toggle both use `warmHighlight` so the whole block
  ///   feels like one system.
  Widget _buildAmbientControls(ThemeData theme) {
    final ambient = ref.read(ambientAudioServiceProvider);
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final fg = palette.foreground;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fg.subtleSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.subtleBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.music_note, size: 16, color: fg.secondaryIcon),
              const SizedBox(width: 8),
              Text(
                'Ambient Sound',
                style: TextStyle(
                  color: fg.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: Switch.adaptive(
                  value: _ambientOn,
                  activeColor: palette.warmHighlight,
                  onChanged: (on) async {
                    // Update toggle immediately so the UI responds
                    // without waiting for async work.
                    setState(() => _ambientOn = on);
                    final sp = await SharedPreferences.getInstance();
                    await sp.setBool('settings.backgroundSoundOn', on);
                    if (on) {
                      final player = ref.read(parablePlayerProvider.notifier);
                      if (player.isPlaying) {
                        await ambient.forceStart();
                      }
                    } else {
                      await ambient.forceStop();
                    }
                  },
                ),
              ),
            ],
          ),
          if (_ambientOn) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AmbientSoundType.values.map((t) {
                final isChipSelected = _ambientType == t;
                return ChoiceChip(
                  label: Text(
                    t.displayName,
                    style: TextStyle(
                      fontSize: 12,
                      color: isChipSelected
                          ? const Color(0xFF1A1A1A)
                          : fg.secondaryText,
                      fontWeight:
                          isChipSelected ? FontWeight.w600 : FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                  selected: isChipSelected,
                  selectedColor: palette.warmHighlight,
                  backgroundColor: fg.subtleSurface,
                  side: BorderSide(
                    color: isChipSelected
                        ? palette.warmHighlight
                        : fg.subtleBorder,
                    width: 1,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  onSelected: (_) async {
                    final sp = await SharedPreferences.getInstance();
                    await sp.setString('settings.ambientSoundType', t.assetName);
                    await ambient.forceStop();
                    setState(() => _ambientType = t);
                    final player = ref.read(parablePlayerProvider.notifier);
                    if (player.isPlaying) {
                      await ambient.forceStart();
                    }
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.volume_down, size: 16, color: fg.secondaryIcon),
                Expanded(
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: palette.warmHighlight,
                      inactiveTrackColor: fg.subtleBorder,
                      thumbColor: palette.warmHighlight,
                      overlayColor: palette.warmHighlight.withValues(alpha: 0.2),
                    ),
                    child: Slider(
                      value: _ambientVol.clamp(0.02, 0.25),
                      min: 0.02,
                      max: 0.25,
                      onChanged: (v) async {
                        setState(() => _ambientVol = v);
                        final sp = await SharedPreferences.getInstance();
                        await sp.setDouble('settings.ambientVolume', v);
                        ambient.setVolume(v);
                      },
                    ),
                  ),
                ),
                Icon(Icons.volume_up, size: 16, color: fg.secondaryIcon),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// - User has showEverydayReflections enabled
  /// - Reflection has not been dismissed
  Widget _buildReflectionSection(ThemeData theme) {
    if (!_showReflection || _reflectionDismissed) {
      return const SizedBox.shrink();
    }

    final playerState = ref.read(parablePlayerProvider);
    if (playerState.currentParable == null) {
      return const SizedBox.shrink();
    }

    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) {
      return const SizedBox.shrink();
    }

    // Check if reflections are enabled
    if (!appState.userPreferences.showEverydayReflections) {
      return const SizedBox.shrink();
    }

    final isKidMode = appState.userPreferences.kidFriendlyOnly;
    final reflection = _reflectionService.getReflectionForParable(
      parable: playerState.currentParable!,
      isKidMode: isKidMode,
    );

    if (reflection == null) {
      return const SizedBox.shrink();
    }

    return Column(
      children: [
        // Standalone reflection audio button
        if (_hasReflectionAudio) ...[
          const SizedBox(height: 16),
          _buildReflectionAudioControls(theme),
        ],
      ],
    );
  }

  // Journal input state
  final TextEditingController _journalController = TextEditingController();
  final FocusNode _journalFocusNode = FocusNode();
  bool _journalEditing = false;
  bool _journalSaved = false;

  void _onJournalFocusChange() {
    if (!_journalFocusNode.hasFocus && _journalEditing) {
      final parable = ref.read(parablePlayerProvider).currentParable;
      if (parable != null) _saveJournal(parable);
    }
  }

  void _saveJournal(Parable parable) async {
    final text = _journalController.text.trim();
    if (text.isEmpty) {
      if (mounted) setState(() => _journalEditing = false);
      return;
    }

    final entry = JournalEntry(
      id: const Uuid().v4(),
      storyId: parable.storyId,
      storyTitle: parable.title,
      mood: parable.mood,
      note: text,
      createdAt: DateTime.now(),
    );

    final storage = await ref.read(storageServiceProvider.future);
    await storage.addJournalEntry(entry);

    if (mounted) {
      setState(() {
        _journalSaved = true;
        _journalEditing = false;
      });
      _journalController.clear();
    }
  }

  /// Always-visible "Add to Journal" action (SPEC Feature 40).
  /// Independent of reflection visibility and playback state.
  /// Hidden in kid mode.
  Widget _buildJournalAction(ThemeData theme, ParablePlayerState playerState) {
    final appState = ref.read(appStateProvider).valueOrNull;
    if (appState == null) return const SizedBox.shrink();
    if (appState.userPreferences.kidFriendlyOnly) return const SizedBox.shrink();
    if (playerState.currentParable == null) return const SizedBox.shrink();

    final parable = playerState.currentParable!;
    final palette = LivingSky.getPalette(LivingSky.getPhase());

    if (_journalSaved) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Saved to your journal.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: palette.foreground.tertiaryText,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    }

    if (!_journalEditing) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GlassButton.icon(
              icon: Icons.edit_note,
              label: 'Add to Journal',
              onPressed: () {
                _cancelAutoAdvance('journal');
                setState(() => _journalEditing = true);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _journalFocusNode.requestFocus();
                });
              },
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: TextField(
          controller: _journalController,
          focusNode: _journalFocusNode,
          maxLength: 200,
          maxLines: 1,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _saveJournal(parable),
          cursorColor: palette.foreground.primaryText,
          style: TextStyle(
            color: palette.foreground.primaryText,
            fontSize: 14,
          ),
          decoration: InputDecoration(
            hintText: 'Add to Journal...',
            hintStyle: TextStyle(
              color: palette.foreground.tertiaryText,
              fontSize: 14,
            ),
            isDense: true,
            filled: true,
            fillColor: palette.cardColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: palette.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide(color: palette.warmHighlight.withOpacity(0.5), width: 1.5),
            ),
            counterText: '',
          ),
        ),
      ),
    );
  }

  /// PALs Paths continuation toggles (SPEC Features 50.6c, 50.6d).
  /// Visible only when the current story was launched from a path context.
  Widget _buildPathContinuationToggles(
      ThemeData theme, ParablePlayerState playerState) {
    if (playerState.launchContext == null) return const SizedBox.shrink();

    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final fg = palette.foreground;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: fg.subtleSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.subtleBorder, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stay on the Path toggle
          Row(
            children: [
              Icon(Icons.route, size: 16, color: fg.secondaryIcon),
              const SizedBox(width: 8),
              Text(
                'Stay on the Path',
                style: TextStyle(
                  color: fg.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: Switch.adaptive(
                  value: _stayOnPathEnabled,
                  activeColor: palette.warmHighlight,
                  onChanged: (on) {
                    setState(() => _stayOnPathEnabled = on);
                    if (!on) {
                      _cancelAutoAdvance('toggle_off');
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Pause for Reflection toggle
          Row(
            children: [
              Icon(Icons.self_improvement, size: 16, color: fg.secondaryIcon),
              const SizedBox(width: 8),
              Text(
                'Pause for Reflection',
                style: TextStyle(
                  color: fg.secondaryText,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 28,
                child: Switch.adaptive(
                  value: _pauseForReflectionEnabled,
                  activeColor: palette.warmHighlight,
                  onChanged: (on) {
                    setState(() => _pauseForReflectionEnabled = on);
                    if (!on) {
                      _cancelAutoAdvance('toggle_off');
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Auto-advance countdown UI (SPEC Feature 50.6c).
  /// Shown in place of NextInJourneyBlock during the 4-second countdown.
  Widget _buildAutoAdvanceCountdown(ThemeData theme) {
    final palette = LivingSky.getPalette(LivingSky.getPhase());
    final fg = palette.foreground;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: palette.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: palette.accentColor.withOpacity(0.35),
            width: 1,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.accentColor.withOpacity(0.6),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Continuing your path\u2026',
                style: TextStyle(
                  color: fg.secondaryText,
                  fontSize: 14,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _cancelAutoAdvance('cancel_button'),
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: fg.tertiaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build audio control buttons for reflection
  Widget _buildReflectionAudioControls(ThemeData theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Play/Stop/Replay button — glass style.
        // Slice 4: when the resolver could not produce a file (offline,
        // remote-only), render a minimal "Connect to play" label instead
        // of the play button.
        if (_reflectionUnavailable)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            child: Text(
              'Connect to play',
              style: TextStyle(
                color: Colors.white70,
                fontStyle: FontStyle.italic,
              ),
            ),
          )
        else if (_isReflectionPlaying)
          GlassButton.icon(
            icon: Icons.stop,
            label: 'Stop',
            onPressed: _stopReflectionAudio,
          )
        else if (_reflectionAudioPlayed)
          GlassButton.icon(
            icon: Icons.replay,
            label: 'Replay',
            onPressed: _replayReflectionAudio,
          )
        else
          GlassButton.icon(
            icon: Icons.play_arrow,
            label: 'Hear Reflection', // ADR-010: User taps to hear
            onPressed: _handlePlayReflection,
          ),
      ],
    );
  }

  /// Format duration to MM:SS
  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

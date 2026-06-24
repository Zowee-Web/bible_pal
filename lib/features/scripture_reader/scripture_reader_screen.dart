import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';
import 'package:bible_pal/core/app_logger.dart';
import '../../widgets/living_sky_background.dart';
import '../../widgets/scripture_verse_block.dart';
import '../kids/parent_lock_flows.dart';

/// Scripture Reader Screen — scrollable full-text scripture display.
///
/// Shows the actual Bible passage (WEB or KJV) for the currently playing
/// Traditional story. Mirrors the StoryReaderScreen pattern.
class ScriptureReaderScreen extends ConsumerStatefulWidget {
  const ScriptureReaderScreen({super.key});

  @override
  ConsumerState<ScriptureReaderScreen> createState() =>
      _ScriptureReaderScreenState();
}

class _ScriptureReaderScreenState extends ConsumerState<ScriptureReaderScreen>
    with SingleTickerProviderStateMixin {
  String? _scriptureText;
  bool _loading = true;

  // Kid lane (SPEC 12.1): full WEB passage is parent-gated. Default is the
  // kid-simple view (reference + key verse). Unlocking reveals the full passage;
  // returning to the simple view is instant (no auth).
  //
  // The unlock affordance mirrors the Kids-mode toggle exactly: a 3-second HOLD
  // (always), then authenticateParent layered on completion — which is instant
  // when no parent lock is set (so the hold IS the gate), or Face ID / PIN when
  // a lock is configured.
  bool _parentUnlocked = false;
  bool _authInFlight = false;
  late final AnimationController _holdController;

  @override
  void initState() {
    super.initState();
    _holdController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) _onHoldComplete();
      });
    _loadScripture();
  }

  @override
  void dispose() {
    _holdController.dispose();
    super.dispose();
  }

  Future<void> _onHoldComplete() async {
    if (_authInFlight) return;
    _authInFlight = true;
    HapticFeedback.mediumImpact();
    final ok =
        await authenticateParent(context, ref, reason: 'Read full Scripture');
    _authInFlight = false;
    if (!mounted) return;
    if (ok) {
      setState(() => _parentUnlocked = true);
    } else {
      _holdController.reset(); // auth cancelled → ready to hold again
    }
  }

  void _cancelHold() {
    if (_holdController.status != AnimationStatus.completed) {
      _holdController.stop();
      _holdController.reset();
    }
  }

  Future<void> _loadScripture() async {
    final playerState = ref.read(parablePlayerProvider);
    final parable = playerState.currentParable;
    if (parable == null) {
      setState(() => _loading = false);
      return;
    }

    final service = await ref.read(parableServiceProvider.future);
    final text = await service.getScriptureText(parable);

    if (mounted) {
      setState(() {
        _scriptureText = text;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    logEvent('screen_view', {'screen_name': 'scripture_reader'});

    final theme = Theme.of(context);
    final playerState = ref.watch(parablePlayerProvider);
    final parable = playerState.currentParable;

    final reference = parable?.hasBibleSourceRef == true
        ? parable!.bibleSourceRef!
        : '';

    final displayStyle = parable?.languageStyle ?? 'WEB';
    final translation = BibleTranslationRegistry.getById(displayStyle);
    final translationLabel = translation != null
        ? '${translation.name} (${translation.id})'
        : 'World English Bible (WEB)';

    // Strip header line from scripture text (e.g. "Exodus 14:10-31 (KJV)")
    String? verseBody;
    if (_scriptureText != null) {
      final lines = _scriptureText!.split('\n');
      final startIdx = lines.length > 2 && lines[1].trim().isEmpty ? 2 : 0;
      verseBody = lines.sublist(startIdx).join('\n').trim();
    }

    // SPEC 12.1: the parent gate keys off kidFriendly ALONE — never the key
    // verse. A kid story always opens in the simple view first; the full WEB
    // passage is always behind the parent unlock. The key verse only enriches
    // the simple view: present -> reference + key verse; missing -> reference
    // only. A missing key verse must never leak the full (adult) passage.
    final keyVerse = parable?.scriptureKeyVerse;
    final isKidGated = parable?.kidFriendly == true;
    final showKidSimple = isKidGated && !_parentUnlocked;

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Read Scripture'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          const LivingSkyBackground(),
          SafeArea(
            child: showKidSimple
                ? _buildKidSimple(theme, reference, keyVerse)
                : _buildFullPassage(
                    theme, reference, translationLabel, verseBody, isKidGated),
          ),
        ],
      ),
    );
  }

  /// Kid-simple, ungated view: reference + (when available) one curated key
  /// verse (SPEC 12.1). When [keyVerse] is null the view falls back to the
  /// reference only — the full passage is NEVER shown here; it lives behind the
  /// parent gate. [keyVerse] is nullable so a missing verse can't leak scripture.
  Widget _buildKidSimple(
      ThemeData theme, String reference, Map<String, dynamic>? keyVerse) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'This story comes from',
            style: theme.textTheme.titleMedium?.copyWith(color: muted),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            reference.isNotEmpty ? reference : 'the Bible',
            style: theme.textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          if (keyVerse != null) ...[
            const SizedBox(height: 36),
            Text(
              'Key Verse',
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: muted, letterSpacing: 1.2),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (keyVerse['ref'] ?? '').toString(),
                    style: theme.textTheme.labelLarge
                        ?.copyWith(fontWeight: FontWeight.bold, color: muted),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    (keyVerse['text'] ?? '').toString(),
                    style: theme.textTheme.titleMedium?.copyWith(height: 1.5),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 40),
          _buildHoldToUnlock(theme),
        ],
      ),
    );
  }

  /// Hold-to-unlock the full passage (kid lane). Like the Kids-mode toggle:
  /// a 3-second hold drives the fill; on completion authenticateParent runs
  /// (instant when no lock — the hold is the gate — or Face ID / PIN if set).
  Widget _buildHoldToUnlock(ThemeData theme) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _holdController.forward(from: 0),
      onTapUp: (_) => _cancelHold(),
      onTapCancel: _cancelHold,
      child: AnimatedBuilder(
        animation: _holdController,
        builder: (context, _) {
          final v = _holdController.value.clamp(0.0, 1.0);
          final holding = _holdController.isAnimating;
          return Container(
            width: double.infinity,
            height: 54,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.primary),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: v,
                    heightFactor: 1.0,
                    child: ColoredBox(color: theme.colorScheme.primaryContainer),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline, size: 18),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        holding
                            ? 'Keep holding…'
                            : 'Parent: Hold to Read Full Scripture',
                        style: theme.textTheme.labelLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Full WEB passage — adult/Traditional default, or the kid lane once the
  /// parent has unlocked. When unlocked in kid mode, offers an instant
  /// (no-auth) return to the kid-simple view.
  Widget _buildFullPassage(ThemeData theme, String reference,
      String translationLabel, String? verseBody, bool isKidGated) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (verseBody == null || verseBody.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Scripture text is not yet available for this story.',
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 16, 28, 48),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (isKidGated && _parentUnlocked) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.child_care, size: 18),
                label: const Text('Return to Kid View'),
                onPressed: () => setState(() => _parentUnlocked = false),
              ),
            ),
            const SizedBox(height: 8),
          ],
          ScripturePassageView(
            rawScriptureText: verseBody,
            reference: reference.isNotEmpty ? reference : null,
            translationLabel: translationLabel,
          ),
        ],
      ),
    );
  }
}

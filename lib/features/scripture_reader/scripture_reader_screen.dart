import 'package:flutter/material.dart';
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

class _ScriptureReaderScreenState extends ConsumerState<ScriptureReaderScreen> {
  String? _scriptureText;
  bool _loading = true;

  // Kid lane (SPEC 12.1): full WEB passage is parent-gated. Default is the
  // kid-simple view (reference + key verse). Unlocking reveals the full passage;
  // returning to the simple view is instant (no auth).
  bool _parentUnlocked = false;

  Future<void> _unlockParent() async {
    final ok =
        await authenticateParent(context, ref, reason: 'Read full Scripture');
    if (ok && mounted) setState(() => _parentUnlocked = true);
  }

  @override
  void initState() {
    super.initState();
    _loadScripture();
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

    // SPEC 12.1: kid stories default to the simple view (reference + key verse);
    // the full WEB passage is parent-gated. Adult/Traditional stories are
    // unaffected (no scriptureKeyVerse) and render the full passage as before.
    final keyVerse = parable?.scriptureKeyVerse;
    final isKidGated = parable?.kidFriendly == true && keyVerse != null;
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

  /// Kid-simple, ungated view: reference + one curated key verse (SPEC 12.1).
  /// The full passage is never shown here — it lives behind the parent gate.
  Widget _buildKidSimple(
      ThemeData theme, String reference, Map<String, dynamic> keyVerse) {
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
          const SizedBox(height: 40),
          OutlinedButton.icon(
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Parent: Read Full Scripture'),
            onPressed: _unlockParent,
          ),
        ],
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

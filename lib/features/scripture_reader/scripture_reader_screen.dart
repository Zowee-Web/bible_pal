import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';
import 'package:bible_pal/core/app_logger.dart';
import '../../widgets/living_sky_background.dart';
import '../../widgets/scripture_verse_block.dart';

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
            child: _loading
          ? const Center(child: CircularProgressIndicator())
          : verseBody == null || verseBody.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Scripture text is not yet available for this story.',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(28, 16, 28, 48),
                  child: ScripturePassageView(
                    rawScriptureText: verseBody,
                    reference: reference.isNotEmpty ? reference : null,
                    translationLabel: translationLabel,
                  ),
                ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bible_pal/providers/parable_player_notifier.dart';
import 'package:bible_pal/providers/service_providers.dart';
import 'package:bible_pal/core/bible_translation_registry.dart';
import 'package:bible_pal/core/app_logger.dart';

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
      appBar: AppBar(
        title: const Text('Read Scripture'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
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
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Reference and translation
                      if (reference.isNotEmpty) ...[
                        Text(
                          reference,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          translationLabel,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 16),
                      ],
                      // Scripture text
                      SelectableText(
                        verseBody,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          height: 1.8,
                          fontSize: 17,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}

import 'package:flutter/material.dart';

import '../core/bible_translation_registry.dart';
import '../models/parable.dart';

/// Collapsible panel showing scripture reference(s) and translation label.
///
/// Collapsed by default. When expanded, shows the Bible reference and
/// translation. After playback completes, a "Read Scripture" button appears.
///
/// Returns [SizedBox.shrink] for stories with no scripture data (Creative mode).
class ScriptureSourcesPanel extends StatefulWidget {
  const ScriptureSourcesPanel({
    super.key,
    required this.parable,
    required this.playbackCompleted,
    required this.onReadScriptureTapped,
  });

  final Parable parable;
  final bool playbackCompleted;
  final VoidCallback onReadScriptureTapped;

  @override
  State<ScriptureSourcesPanel> createState() => _ScriptureSourcesPanelState();
}

class _ScriptureSourcesPanelState extends State<ScriptureSourcesPanel> {
  bool _expanded = false;

  String? get _referenceText {
    if (widget.parable.hasBibleSourceRef) {
      return widget.parable.bibleSourceRef;
    }
    if (widget.parable.scriptureSources.isNotEmpty) {
      return widget.parable.scriptureSources.join(', ');
    }
    return null;
  }

  String get _translationLabel {
    final translation =
        BibleTranslationRegistry.getById(widget.parable.translationId);
    if (translation != null) {
      return '${translation.name} (${translation.id})';
    }
    return 'World English Bible (WEB)';
  }

  @override
  Widget build(BuildContext context) {
    if (_referenceText == null) return const SizedBox.shrink();

    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Card(
        elevation: 2,
        color: theme.colorScheme.tertiaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row — always visible
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    Icon(
                      Icons.menu_book,
                      size: 18,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Scripture Sources',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Icon(
                      _expanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ],
                ),
              ),

              // Expanded content
              if (_expanded) ...[
                const SizedBox(height: 12),
                // Reference
                Text(
                  _referenceText!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                // Translation label
                Text(
                  _translationLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // "Read Scripture" button — post-completion only
                if (widget.playbackCompleted) ...[
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: widget.onReadScriptureTapped,
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Read Scripture'),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

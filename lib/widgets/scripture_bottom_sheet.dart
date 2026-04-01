import 'package:flutter/material.dart';

import '../core/bible_translation_registry.dart';
import '../models/parable.dart';

/// Opens a bottom sheet displaying the scripture reference, translation label,
/// and the actual verse text if available.
void showScriptureBottomSheet(
  BuildContext context,
  Parable parable, {
  String? scriptureText,
}) {
  final reference = parable.hasBibleSourceRef
      ? parable.bibleSourceRef!
      : parable.scriptureSources.join(', ');

  final translation =
      BibleTranslationRegistry.getById(parable.translationId);
  final translationLabel = translation != null
      ? '${translation.name} (${translation.id})'
      : 'World English Bible (WEB)';

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      final theme = Theme.of(context);

      // Parse scripture text: skip the header line (reference) if present
      String? verseBody;
      if (scriptureText != null) {
        final lines = scriptureText.split('\n');
        // Skip header line and blank line after it
        final startIdx = lines.length > 2 && lines[1].trim().isEmpty ? 2 : 0;
        verseBody = lines.sublist(startIdx).join('\n').trim();
      }

      return DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.3,
        maxChildSize: 0.85,
        expand: false,
        builder: (context, scrollController) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title
                      Text(
                        'Read Scripture',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),

                      // Reference
                      Text(
                        reference,
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 4),

                      // Translation label
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
                  ),
                ),

                // Scripture text or placeholder
                SliverToBoxAdapter(
                  child: verseBody != null
                      ? SelectableText(
                          verseBody,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            height: 1.6,
                          ),
                        )
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            'Scripture text is not yet available for this story.',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontStyle: FontStyle.italic,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                ),

                const SliverToBoxAdapter(
                  child: SizedBox(height: 24),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

import 'package:flutter/material.dart';

import '../core/bible_translation_registry.dart';
import '../models/parable.dart';

/// Opens a bottom sheet displaying the scripture reference, translation label,
/// and a placeholder for verse text (Phase 1 — text not yet available).
void showScriptureBottomSheet(BuildContext context, Parable parable) {
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
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      final theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
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

            // Placeholder for verse text (Phase 2)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest
                    .withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Scripture text will be available in a future update.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      );
    },
  );
}

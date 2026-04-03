import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A single parsed verse: number + text.
class ScriptureVerse {
  final String number;
  final String text;
  const ScriptureVerse({required this.number, required this.text});
}

/// Parses raw scripture text into verse-level data.
///
/// Expects lines like:
///   1 In the beginning God created...
///   2 And the earth was without form...
///
/// Continuation lines (no leading number) are joined to the previous verse.
List<ScriptureVerse> parseScriptureVerses(String rawText) {
  final lines = rawText.split('\n');
  final verses = <ScriptureVerse>[];
  final versePattern = RegExp(r'^(\d+)\s+(.*)$');

  String currentNumber = '';
  final currentText = StringBuffer();

  for (final line in lines) {
    final match = versePattern.firstMatch(line);
    if (match != null) {
      // Flush previous verse
      if (currentNumber.isNotEmpty) {
        verses.add(ScriptureVerse(
          number: currentNumber,
          text: currentText.toString().trim(),
        ));
      }
      currentNumber = match.group(1)!;
      currentText
        ..clear()
        ..write(match.group(2)!);
    } else if (currentNumber.isNotEmpty && line.trim().isNotEmpty) {
      // Continuation line
      currentText
        ..write('\n')
        ..write(line);
    }
  }

  // Flush final verse
  if (currentNumber.isNotEmpty) {
    verses.add(ScriptureVerse(
      number: currentNumber,
      text: currentText.toString().trim(),
    ));
  }

  return verses;
}

/// Renders a single verse as a calm, spacious block.
class ScriptureVerseBlock extends StatelessWidget {
  final ScriptureVerse verse;
  const ScriptureVerseBlock({super.key, required this.verse});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // Verse number — small, muted, fixed width
          SizedBox(
            width: 28,
            child: Text(
              verse.number,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.mutedSlate,
                height: 2.0,
              ),
            ),
          ),
          // Verse text — primary reading content
          Expanded(
            child: SelectableText(
              verse.text,
              style: const TextStyle(
                fontSize: 18,
                height: 2.0,
                color: AppTheme.warmIvory,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a full scripture passage as a column of verse blocks.
///
/// Use this anywhere scripture text needs to be displayed.
/// Handles parsing internally — just pass the raw text.
class ScripturePassageView extends StatelessWidget {
  final String rawScriptureText;
  final String? reference;
  final String? translationLabel;

  const ScripturePassageView({
    super.key,
    required this.rawScriptureText,
    this.reference,
    this.translationLabel,
  });

  @override
  Widget build(BuildContext context) {
    final verses = parseScriptureVerses(rawScriptureText);

    // Fallback: if parsing produces no verses, show raw text
    if (verses.isEmpty) {
      return SelectableText(
        rawScriptureText,
        style: const TextStyle(
          fontSize: 18,
          height: 2.0,
          color: AppTheme.warmIvory,
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: reference + translation
            if (reference != null && reference!.isNotEmpty) ...[
              Text(
                reference!,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.warmIvory,
                  letterSpacing: 0.3,
                ),
              ),
              if (translationLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  translationLabel!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppTheme.mutedSlate,
                  ),
                ),
              ],
              const SizedBox(height: 24),
            ],
            // Verse blocks
            for (final verse in verses)
              ScriptureVerseBlock(verse: verse),
          ],
        ),
      ),
    );
  }
}

// Share Service
// Implements SPEC.md Feature #14: Share With a PAL
// Formats story content and invokes the platform share sheet.

import 'package:share_plus/share_plus.dart';
import '../models/parable.dart';

class ShareService {
  /// Format and share a parable via the platform share sheet.
  Future<bool> shareParable({
    required Parable parable,
    required String? storyText,
  }) async {
    final shareText = _formatShareText(parable, storyText);

    final result = await Share.share(shareText);

    return result.status == ShareResultStatus.success;
  }

  String _formatShareText(Parable parable, String? storyText) {
    final buffer = StringBuffer();

    buffer.writeln(parable.title);
    buffer.writeln();

    if (storyText != null && storyText.isNotEmpty) {
      final excerpt = storyText.length > 500
          ? '${storyText.substring(0, 500)}...'
          : storyText;
      buffer.writeln(excerpt);
      buffer.writeln();
    }

    if (parable.bibleSourceRef != null && parable.bibleSourceRef!.isNotEmpty) {
      buffer.writeln('Scripture: ${parable.bibleSourceRef}');
      buffer.writeln();
    }

    buffer.write('Shared from Bible PAL');

    return buffer.toString();
  }

  /// Share a short, compelling clip — the best 2-3 sentences from the story.
  /// Designed for social sharing (text messages, social media posts).
  Future<bool> shareClip({
    required Parable parable,
    required String? storyText,
  }) async {
    final clip = _extractBestClip(storyText);
    final buffer = StringBuffer();

    buffer.writeln('"$clip"');
    buffer.writeln();
    buffer.writeln('— ${parable.title}');

    if (parable.bibleSourceRef != null && parable.bibleSourceRef!.isNotEmpty) {
      buffer.writeln('  ${parable.bibleSourceRef}');
    }

    buffer.writeln();
    buffer.write('Listen on Bible PAL');

    final result = await Share.share(buffer.toString());
    return result.status == ShareResultStatus.success;
  }

  /// Extract 2-3 compelling sentences from the middle of the story.
  /// Avoids the opening (often setup) and ending (often resolution).
  String _extractBestClip(String? storyText) {
    if (storyText == null || storyText.isEmpty) {
      return 'A story worth hearing.';
    }

    // Split into sentences
    final sentences = storyText
        .replaceAll('\n', ' ')
        .split(RegExp(r'(?<=[.!?])\s+'))
        .where((s) => s.trim().length > 10)
        .toList();

    if (sentences.length <= 3) return sentences.join(' ');

    // Pick 2-3 sentences from the middle third
    final midStart = sentences.length ~/ 3;
    final clip = sentences.skip(midStart).take(3).join(' ');

    // Cap at ~200 chars
    if (clip.length > 200) {
      return '${clip.substring(0, 197)}...';
    }
    return clip;
  }
}

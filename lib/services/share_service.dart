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
}

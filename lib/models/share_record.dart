import 'package:flutter/foundation.dart';

/// Share record for tracking story shares between PALs
/// v1.0: Local-only records (no actual delivery mechanism yet)
@immutable
class ShareRecord {
  final String shareId; // UUID
  final String storyId; // Which story was shared
  final String storyTitle; // Human-readable story title
  final String toPalId; // Recipient PAL ID
  final DateTime timestamp; // When shared
  final ShareDirection direction; // sent or received

  const ShareRecord({
    required this.shareId,
    required this.storyId,
    required this.storyTitle,
    required this.toPalId,
    required this.timestamp,
    required this.direction,
  });

  /// Create from JSON (SharedPreferences)
  factory ShareRecord.fromJson(Map<String, dynamic> json) {
    final normalizedDirection =
        _normalizeDirection(json['direction'] as String?);

    return ShareRecord(
      shareId: json['shareId'] as String,
      storyId: json['storyId'] as String,
      storyTitle: json['storyTitle'] as String? ??
          json['storyId']
              as String, // Backward compatibility: fallback to storyId
      toPalId: json['toPalId'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      direction: ShareDirection.values.firstWhere(
        (e) => e.name == normalizedDirection,
        orElse: () =>
            ShareDirection.sent, // Safe default for backward compatibility
      ),
    );
  }

  /// Normalize direction string for backward compatibility
  /// Handles: "sent", "received", "ShareDirection.sent", "ShareDirection.received", null, empty
  /// Returns: "sent" or "received" (or null/empty if input is invalid)
  static String? _normalizeDirection(String? raw) {
    if (raw == null || raw.isEmpty) return null;

    // Strip "ShareDirection." prefix if present (legacy .toString() format)
    if (raw.startsWith('ShareDirection.')) {
      return raw.substring('ShareDirection.'.length);
    }

    return raw;
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'shareId': shareId,
      'storyId': storyId,
      'storyTitle': storyTitle,
      'toPalId': toPalId,
      'timestamp': timestamp.toIso8601String(),
      'direction': direction.name, // Serialize as "sent" or "received"
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ShareRecord && other.shareId == shareId;
  }

  @override
  int get hashCode => shareId.hashCode;
}

/// Direction of share (for future received-from tracking)
enum ShareDirection {
  sent,
  received,
}

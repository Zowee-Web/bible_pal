import 'package:flutter/foundation.dart';

/// Pending share for offline retry queue
/// Stores shares that need to be sent to backend when network available
@immutable
class PendingShare {
  /// Stable UUID generated once at share creation (CRITICAL for idempotency)
  final String shareId;

  /// Story identifier
  final String storyId;

  /// Human-readable story title
  final String storyTitle;

  /// Recipient PAL ID
  final String toPalId;

  /// When this share was created locally
  final DateTime createdAt;

  /// Number of retry attempts (for monitoring/debugging)
  final int retryCount;

  const PendingShare({
    required this.shareId,
    required this.storyId,
    required this.storyTitle,
    required this.toPalId,
    required this.createdAt,
    this.retryCount = 0,
  });

  /// Create from JSON (SharedPreferences)
  factory PendingShare.fromJson(Map<String, dynamic> json) {
    return PendingShare(
      shareId: json['shareId'] as String,
      storyId: json['storyId'] as String,
      storyTitle: json['storyTitle'] as String,
      toPalId: json['toPalId'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      retryCount: json['retryCount'] as int? ?? 0,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'shareId': shareId,
      'storyId': storyId,
      'storyTitle': storyTitle,
      'toPalId': toPalId,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
    };
  }

  /// Create a copy with updated retry count
  PendingShare copyWith({
    String? shareId,
    String? storyId,
    String? storyTitle,
    String? toPalId,
    DateTime? createdAt,
    int? retryCount,
  }) {
    return PendingShare(
      shareId: shareId ?? this.shareId,
      storyId: storyId ?? this.storyId,
      storyTitle: storyTitle ?? this.storyTitle,
      toPalId: toPalId ?? this.toPalId,
      createdAt: createdAt ?? this.createdAt,
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PendingShare && other.shareId == shareId;
  }

  @override
  int get hashCode => shareId.hashCode;

  @override
  String toString() {
    return 'PendingShare(shareId: $shareId, storyId: $storyId, toPalId: $toPalId, retryCount: $retryCount)';
  }
}

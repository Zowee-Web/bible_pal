import 'package:flutter/foundation.dart';

/// PAL (friend/contact) model for v1.0 story sharing
/// Supports manual entry and invite codes
@immutable
class PAL {
  final String palId; // UUID or generated ID
  final String displayName; // User-visible name
  final DateTime createdAt; // When added
  final bool pinned; // Optional: pinned to top
  final int shareCount; // Track frequency for Top PALs ordering

  const PAL({
    required this.palId,
    required this.displayName,
    required this.createdAt,
    this.pinned = false,
    this.shareCount = 0,
  });

  /// Create from JSON (SharedPreferences)
  factory PAL.fromJson(Map<String, dynamic> json) {
    return PAL(
      palId: json['palId'] as String,
      displayName: json['displayName'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      pinned: json['pinned'] as bool? ?? false,
      shareCount: json['shareCount'] as int? ?? 0,
    );
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'palId': palId,
      'displayName': displayName,
      'createdAt': createdAt.toIso8601String(),
      'pinned': pinned,
      'shareCount': shareCount,
    };
  }

  /// Create a copy with updated fields
  PAL copyWith({
    String? palId,
    String? displayName,
    DateTime? createdAt,
    bool? pinned,
    int? shareCount,
  }) {
    return PAL(
      palId: palId ?? this.palId,
      displayName: displayName ?? this.displayName,
      createdAt: createdAt ?? this.createdAt,
      pinned: pinned ?? this.pinned,
      shareCount: shareCount ?? this.shareCount,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PAL && other.palId == palId;
  }

  @override
  int get hashCode => palId.hashCode;
}

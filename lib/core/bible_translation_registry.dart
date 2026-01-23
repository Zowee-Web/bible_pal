/// Bible Translation Registry - SINGLE SOURCE OF TRUTH
///
/// HARD INVARIANT: Bible PAL must NEVER use or offer any non-open-source /
/// non-public-domain Bible translations.
///
/// This registry is the ONLY place that defines allowed translations.
/// Any code that handles Bible translations MUST reference this registry.
///
/// ALLOWED: Only open-source and public-domain translations
/// BANNED: NIV, ESV, NRSV, NLT, CSB, NASB, MSG, HCSB, AMP, GNT, and all others not explicitly listed below
library;

/// License types for Bible translations
enum LicenseType {
  /// Public domain - no copyright restrictions
  publicDomain,

  /// Open-source license (e.g., Creative Commons, MIT-like)
  openLicense,
}

/// Allowed Bible translations (open-source / public domain only)
class BibleTranslationRegistry {
  /// Private constructor to prevent instantiation
  BibleTranslationRegistry._();

  /// ALLOWLIST: Only these translations are permitted
  ///
  /// Each entry must include:
  /// - id: Short identifier (used in code and data) - UPPERCASE
  /// - name: Full display name
  /// - licenseType: Structured license type (publicDomain or openLicense)
  /// - licenseName: Human-readable license description
  /// - year: Year of publication
  static const List<BibleTranslation> allowedTranslations = [
    BibleTranslation(
      id: 'WEB',
      name: 'World English Bible',
      licenseType: LicenseType.publicDomain,
      licenseName: 'Public Domain (no copyright)',
      year: 2000,
      url: 'https://worldenglish.bible',
      notes:
          'Modern English update based on ASV, released to public domain by editors',
    ),
    BibleTranslation(
      id: 'KJV',
      name: 'King James Version',
      licenseType: LicenseType.publicDomain,
      licenseName: 'Public Domain (Crown copyright expired)',
      year: 1611,
      url: 'https://www.kingjamesbibleonline.org',
      notes: 'Classic English translation, universally public domain',
    ),
    BibleTranslation(
      id: 'ASV',
      name: 'American Standard Version',
      licenseType: LicenseType.publicDomain,
      licenseName: 'Public Domain (copyright expired)',
      year: 1901,
      url:
          'https://www.biblegateway.com/versions/American-Standard-Version-ASV-Bible',
      notes: 'Public domain revision of KJV',
    ),
    BibleTranslation(
      id: 'YLT',
      name: "Young's Literal Translation",
      licenseType: LicenseType.publicDomain,
      licenseName: 'Public Domain (copyright expired)',
      year: 1862,
      url:
          'https://www.biblegateway.com/versions/Youngs-Literal-Translation-YLT-Bible',
      notes: 'Highly literal translation, public domain',
    ),
    BibleTranslation(
      id: 'DRA',
      name: 'Douay-Rheims (American Edition)',
      licenseType: LicenseType.publicDomain,
      licenseName: 'Public Domain (copyright expired)',
      year: 1899,
      url: 'https://www.drbo.org',
      notes: 'Catholic translation, public domain edition',
    ),
  ];

  /// BANNED: Copyrighted translations that must NEVER appear
  ///
  /// This list is used by tests to detect compliance violations.
  /// If any of these IDs or fingerprint strings are found in code or data,
  /// the build MUST fail.
  static const List<BannedTranslation> bannedTranslations = [
    BannedTranslation(
      id: 'NIV',
      name: 'New International Version',
      owner: 'Biblica, Inc.',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: ['heavy laden', 'lowly in heart'],
    ),
    BannedTranslation(
      id: 'ESV',
      name: 'English Standard Version',
      owner: 'Crossway',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: ['heavy laden', 'lowly in heart', 'conviction of things'],
    ),
    BannedTranslation(
      id: 'NRSV',
      name: 'New Revised Standard Version',
      owner: 'National Council of Churches',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: [],
    ),
    BannedTranslation(
      id: 'NLT',
      name: 'New Living Translation',
      owner: 'Tyndale House Foundation',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: [],
    ),
    BannedTranslation(
      id: 'NASB',
      name: 'New American Standard Bible',
      owner: 'The Lockman Foundation',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: [],
    ),
    BannedTranslation(
      id: 'CSB',
      name: 'Christian Standard Bible',
      owner: 'Holman Bible Publishers',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: [],
    ),
    BannedTranslation(
      id: 'MSG',
      name: 'The Message',
      owner: 'NavPress',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: [],
    ),
    BannedTranslation(
      id: 'HCSB',
      name: 'Holman Christian Standard Bible',
      owner: 'Holman Bible Publishers',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: [],
    ),
    BannedTranslation(
      id: 'AMP',
      name: 'Amplified Bible',
      owner: 'The Lockman Foundation',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: [],
    ),
    BannedTranslation(
      id: 'GNT',
      name: 'Good News Translation',
      owner: 'American Bible Society',
      reason: 'Copyrighted - Requires licensing fees',
      fingerprints: [],
    ),
  ];

  /// Default translation ID (fallback when user preference is invalid)
  static const String defaultTranslationId = 'WEB';

  /// Get all allowed translation IDs
  static Set<String> get allowedIds =>
      allowedTranslations.map((t) => t.id).toSet();

  /// Get all banned translation IDs
  static Set<String> get bannedIds =>
      bannedTranslations.map((t) => t.id).toSet();

  /// Get all banned fingerprints (for text scanning)
  static Set<String> get bannedFingerprints => bannedTranslations
      .expand((t) => t.fingerprints)
      .map((f) => f.toLowerCase())
      .toSet();

  /// Check if a translation ID is allowed
  static bool isAllowed(String translationId) {
    return allowedIds.contains(translationId);
  }

  /// Check if a translation ID is banned
  static bool isBanned(String translationId) {
    return bannedIds.contains(translationId);
  }

  /// Get translation by ID (returns null if not allowed)
  static BibleTranslation? getById(String id) {
    try {
      return allowedTranslations.firstWhere((t) => t.id == id);
    } catch (e) {
      return null;
    }
  }

  /// Validate and sanitize a translation ID
  ///
  /// Normalizes input (trim + uppercase) before validation.
  ///
  /// Returns:
  /// - The normalized ID if it's allowed
  /// - The default ID if invalid/banned
  /// - Logs a warning if banned translation detected
  static String validateAndSanitize(String translationId) {
    // Normalize: trim whitespace and convert to uppercase
    final normalized = translationId.trim().toUpperCase();

    // Check if banned (compliance violation)
    if (isBanned(normalized)) {
      // In production, this should trigger an alert
      // ignore: avoid_print
      print(
          '⚠️ COMPLIANCE VIOLATION: Banned translation "$translationId" (normalized: "$normalized") detected. Resetting to $defaultTranslationId');
      return defaultTranslationId;
    }

    // Check if allowed
    if (isAllowed(normalized)) {
      return normalized;
    }

    // Unknown translation - reset to default
    // ignore: avoid_print
    print(
        '⚠️ WARNING: Unknown translation "$translationId" (normalized: "$normalized") detected. Resetting to $defaultTranslationId');
    return defaultTranslationId;
  }

  /// Scan text for banned translation fingerprints
  ///
  /// Returns a list of detected fingerprints (empty if clean)
  static List<String> scanForBannedFingerprints(String text) {
    final detected = <String>[];
    final lowerText = text.toLowerCase();

    for (final fingerprint in bannedFingerprints) {
      if (lowerText.contains(fingerprint)) {
        detected.add(fingerprint);
      }
    }

    return detected;
  }
}

/// Model for an allowed Bible translation
class BibleTranslation {
  final String id;
  final String name;
  final LicenseType licenseType;
  final String licenseName;
  final int year;
  final String url;
  final String notes;

  const BibleTranslation({
    required this.id,
    required this.name,
    required this.licenseType,
    required this.licenseName,
    required this.year,
    required this.url,
    required this.notes,
  });

  @override
  String toString() => '$name ($id) - $licenseName';
}

/// Model for a banned (copyrighted) Bible translation
class BannedTranslation {
  final String id;
  final String name;
  final String owner;
  final String reason;
  final List<String> fingerprints;

  const BannedTranslation({
    required this.id,
    required this.name,
    required this.owner,
    required this.reason,
    required this.fingerprints,
  });

  @override
  String toString() => '$name ($id) - $reason';
}

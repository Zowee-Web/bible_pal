/// Ambient background sound types for story playback (Feature 49).
/// Assets must exist at: assets/audio/ambient/{assetName}.mp3
enum AmbientSoundType {
  rain('rain', 'Rain'),
  wind('wind', 'Soft Wind'),
  night('night', 'Night Ambience'),
  pads('pads', 'Soft Pads');

  final String assetName;
  final String displayName;

  const AmbientSoundType(this.assetName, this.displayName);

  /// Asset path for this sound type.
  String get assetPath => 'assets/audio/ambient/$assetName.mp3';

  /// Parse from persisted string. Returns [defaultType] if null or invalid.
  static AmbientSoundType fromString(String? value) {
    if (value == null) return defaultType;
    return AmbientSoundType.values.firstWhere(
      (t) => t.assetName == value,
      orElse: () => defaultType,
    );
  }

  static const AmbientSoundType defaultType = AmbientSoundType.rain;
}

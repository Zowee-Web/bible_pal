/// A reference to a PAL line with both its ID (for audio asset lookup) and text.
///
/// Used by all PAL line registries (reflection, framing, transition, opening)
/// to return both the display text and the audio asset ID from a single lookup.
class PalLineRef {
  final String id;
  final String text;
  const PalLineRef(this.id, this.text);
}

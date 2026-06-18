// Kid feeling cards — SPEC Feature 51.3
//
// The tap-a-feeling input for Kids mode (ages 4-7). Each card submits a fixed
// canonical phrase as `userText` into the existing mood pipeline
// (MoodService.detectMood → RelatabilityMatcher → ParableService.selectParable)
// — the selection engine is unchanged. A card is purely a front-end input that
// produces the same `userText` a child would type or speak.
//
// LOCKED design rule: every canonical phrase MUST contain at least one
// MoodService keyword so detection never falls to the no-match default. The
// phrase may also carry a RelatabilityMatcher situation keyword (lonely,
// in_trouble, feeling_small, missing_someone, …) to bias ranking toward the
// kid story that fits the feeling. Validated card → (mood, tags) → story:
//
//   😨 scared    "I feel scared"                     → anxious  {anxious}
//                  → Walks on Water / Calms the Storm / Red Sea (+ brave bridge)
//   😟 lonely    "I feel lonely and left out"        → hurting  {lonely, rejection}
//                  → The Lost Sheep (1826)
//   😔 trouble   "I got in trouble and I feel upset" → hurting  {in_trouble}
//                  → The Loving Father (1817)
//   🥺 little    "I feel too little and scared"      → anxious  {anxious, feeling_small}
//                  → Walls of Jericho (1818) / David (1801)
//   🫂 miss      "I miss my mom and feel lonely"     → hurting  {lonely, missing_someone}
//                  → The Lost Sheep (1826) — no story is retagged (SPEC 51.5)
//   😄 happy     "I'm happy"                         → joyful   {}  → joyful pool
//   🙏 thankful  "I'm thankful"                      → grateful {grateful}
//                  → Creation (1805) / Loving Father (1817) / Big Picnic (1825)
//   😴 tired     "I'm tired"                         → weary    {overwhelmed}
//                  → The Lord Is My Shepherd (1803)

/// A single tap-a-feeling card shown in Kids mode.
class KidFeelingCard {
  /// Short, child-readable label shown under the emoji.
  final String label;

  /// The card's emoji glyph.
  final String emoji;

  /// Fixed phrase submitted as `userText` when the card is tapped. Always
  /// contains a MoodService keyword (LOCKED design rule above).
  final String canonicalPhrase;

  const KidFeelingCard({
    required this.label,
    required this.emoji,
    required this.canonicalPhrase,
  });
}

/// The 8 feeling cards, in display order. Mix of hard feelings (scared,
/// lonely, trouble, little, missing) and warm ones (happy, thankful, tired)
/// so the grid offers all four kid registers, not just comfort.
const List<KidFeelingCard> kidFeelingCards = [
  KidFeelingCard(
    label: "I'm scared",
    emoji: '😨',
    canonicalPhrase: 'I feel scared',
  ),
  KidFeelingCard(
    label: 'I feel lonely',
    emoji: '😟',
    canonicalPhrase: 'I feel lonely and left out',
  ),
  KidFeelingCard(
    label: 'I got in trouble',
    emoji: '😔',
    canonicalPhrase: 'I got in trouble and I feel upset',
  ),
  KidFeelingCard(
    label: 'I feel little',
    emoji: '🥺',
    canonicalPhrase: 'I feel too little and scared',
  ),
  KidFeelingCard(
    label: 'I miss someone',
    emoji: '🫂',
    canonicalPhrase: 'I miss my mom and feel lonely',
  ),
  KidFeelingCard(
    label: "I'm happy",
    emoji: '😄',
    canonicalPhrase: "I'm happy",
  ),
  KidFeelingCard(
    label: "I'm thankful",
    emoji: '🙏',
    canonicalPhrase: "I'm thankful",
  ),
  KidFeelingCard(
    label: "I'm tired",
    emoji: '😴',
    canonicalPhrase: "I'm tired",
  ),
];

/// Kids-mode mood fallback (SPEC Feature 51.3).
///
/// When mood detection yields the low-confidence no-match default
/// (`weary` @ 0.4 with no tags — see [MoodService] default branch), Kids mode
/// substitutes `joyful` so an unmatched spoken/typed sentence lands on a warm
/// story instead of the weary pool. The feeling cards always carry a keyword
/// so they never hit this path; it exists for free-form kid voice input.
///
/// Scoped to the kid input layer — the global MoodService default is untouched,
/// so the adult fallback stays `weary`.
String kidFallbackMood({
  required String detectedMood,
  required double confidenceScore,
}) {
  final isNoMatchDefault = detectedMood == 'weary' && confidenceScore <= 0.4;
  return isNoMatchDefault ? 'joyful' : detectedMood;
}

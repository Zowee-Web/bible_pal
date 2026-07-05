/// Journey Doctrine Slice 2 Phase 7 — response classifier.
///
/// Pure, lane-agnostic, no IO. Maps a free-form user utterance (the
/// STT result of "Last time, we walked with Daniel into the lions'
/// den… and there's more to his story if you'd like to hear it.") to
/// one of four buckets the cascade dispatches on:
///
///   - accept       — play the next-in-journey story
///   - decline      — say the decline clip → fall through to mood-flow
///   - moodRedirect — silently dispatch to mood-flow with the user's
///                    phrase as the mood signal (NO decline clip).
///                    The "user's response IS the decline signal"
///                    principle from the doctrine: do not ask them to
///                    decline twice.
///   - ambiguous    — say the decline clip → re-listen for a mood.
///                    Reserved for genuine uncertainty (empty input,
///                    "I don't know", "maybe", "um") where PAL has
///                    nothing to work with and a gentle re-prompt is
///                    the honest response.
///
/// Priority order (locked):
///   1. Empty / whitespace          → ambiguous
///   2. Ambiguous markers anywhere  → ambiguous  ("I don't know" wins
///      before negative-start, so "I don't know" is NOT decline.)
///   3. Affirmative at START        → accept     ("yes I'm anxious"
///      stays accept — user's first word answers the offer.)
///   4. Mood word anywhere          → moodRedirect
///   5. Negative at START           → decline
///   6. Else                        → moodRedirect  (any substantive
///      statement IS the user opening the door PAL offered — "tell me
///      what's on your heart." Route it to a story rather than playing
///      a decline clip and re-listening, which reads as dismissal. The
///      mood service defaults unmatched phrases to "weary", so a story
///      always follows. Fixes the 2026-07-05 freeze: "I had a long day
///      at work" / "I got in trouble at school" matched no mood keyword
///      and fell here → decline clip + re-listen → apparent freeze.)
library;

/// The bucket a user utterance falls into. The cascade (Phase 9)
/// dispatches on this enum.
enum JourneyResponseBucket {
  accept,
  decline,
  moodRedirect,
  ambiguous,
}

/// Classification result. `text` is the user's input, trimmed but
/// with original casing preserved — so a [moodRedirect] caller can
/// pass it through to mood detection without losing nuance.
class JourneyResponseClassification {
  final JourneyResponseBucket bucket;
  final String text;

  const JourneyResponseClassification({
    required this.bucket,
    required this.text,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is JourneyResponseClassification &&
          other.bucket == bucket &&
          other.text == text);

  @override
  int get hashCode => Object.hash(bucket, text);

  @override
  String toString() => 'JourneyResponseClassification($bucket, "$text")';
}

/// Stateless, const-constructible classifier. Phase 9 will inject
/// this into the cascade. Mockable in tests by subclassing.
class JourneyResponseClassifier {
  const JourneyResponseClassifier();

  JourneyResponseClassification classify(String userResponse) {
    final trimmed = userResponse.trim();
    if (trimmed.isEmpty) {
      return const JourneyResponseClassification(
        bucket: JourneyResponseBucket.ambiguous,
        text: '',
      );
    }

    final lower = trimmed.toLowerCase();

    if (_ambiguousPattern.hasMatch(lower)) {
      return JourneyResponseClassification(
        bucket: JourneyResponseBucket.ambiguous,
        text: trimmed,
      );
    }

    if (_acceptStartPattern.hasMatch(lower)) {
      return JourneyResponseClassification(
        bucket: JourneyResponseBucket.accept,
        text: trimmed,
      );
    }

    if (_moodPattern.hasMatch(lower)) {
      return JourneyResponseClassification(
        bucket: JourneyResponseBucket.moodRedirect,
        text: trimmed,
      );
    }

    if (_declineStartPattern.hasMatch(lower)) {
      return JourneyResponseClassification(
        bucket: JourneyResponseBucket.decline,
        text: trimmed,
      );
    }

    // Any remaining substantive utterance is the user answering the
    // open door ("tell me what's on your heart") — route it to the
    // mood flow for a story rather than treating it as a decline.
    // Only empty input and explicit-uncertainty markers (handled
    // above) fall to `ambiguous`.
    return JourneyResponseClassification(
      bucket: JourneyResponseBucket.moodRedirect,
      text: trimmed,
    );
  }

  // ---- patterns ----------------------------------------------------
  //
  // Locked vocabulary. Keep additions disciplined — every keyword
  // here changes runtime behavior for everyone. New entries should
  // come from observed STT transcripts, not hypothetical phrasings.
  //
  // Ambiguous markers are checked BEFORE the negative-start pattern
  // so "I don't know" (contains "don't know") is classified as
  // ambiguous, not decline.

  static final RegExp _ambiguousPattern = RegExp(
    r"\b(don'?t know|do not know|not sure|dunno|i dunno|hmm+|um+|uh+|maybe|i guess)\b",
    caseSensitive: false,
  );

  static final RegExp _acceptStartPattern = RegExp(
    r"^(yes|yeah|yep|yup|sure|ok|okay|alright|continue|keep going|go (on|ahead)|let'?s|tell me|i would|i'd|please|definitely|absolutely|of course|sounds (good|great))\b",
    caseSensitive: false,
  );

  static final RegExp _moodPattern = RegExp(
    r"\b(anxious|anxiety|scared|afraid|fearful|fear|sad|lonely|alone|tired|exhausted|weary|grateful|thankful|joyful|joy|happy|overwhelmed|stressed|hurting|hurt|worried|empty|broken|angry|frustrated|peaceful|lost|heavy|down|discouraged|can'?t sleep|couldn'?t sleep|hard day|rough day|bad day|tough day|i'?m not (ok|okay)|need help|i feel|i'?m feeling)\b",
    caseSensitive: false,
  );

  static final RegExp _declineStartPattern = RegExp(
    r"^(no|nope|nah|not (now|today|tonight|right now)|something else|different|skip|pass)\b",
    caseSensitive: false,
  );
}

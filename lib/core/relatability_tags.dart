// Relatability Tags - Single source of truth for tag vocabulary
// Used by RelatabilityMatcher to extract tags from user input and match stories.
//
// Tag categories (flat storage, categorized here for documentation only):
// - Emotions (7 v1 + 8 PR β = 15): overwhelmed, anxious, sad, angry, lonely,
//   hopeless, grateful, danger, courage, hope, uncertainty, celebration,
//   togetherness, solemnity, wonder
// - Situations (13): workplace_conflict, unfair_authority, relationship_conflict,
//   rejection, failure, grief, illness, financial_stress, parenting_struggle,
//   self_doubt, temptation, waiting, injustice
//
// PR β expansion: added 8 emotional registers authored across the 1287-story
// corpus. The new entries are registers (not extracted-from-user-input
// categories), so they appear here primarily for manifest validation. The
// `tagKeywords` map below intentionally does NOT add keywords for them —
// adding keywords for `danger` etc. would change the matcher's behavior on
// user input, which is outside this PR's scope.

/// Explicit iteration order for deterministic tag extraction.
/// When multiple tags match, we keep the first 3 in this order.
const List<String> tagOrder = [
  // Emotions first (often more specific to user state)
  'overwhelmed',
  'anxious',
  'sad',
  'angry',
  'lonely',
  'hopeless',
  'grateful',
  // PR β expansion — emotional registers authored in corpus
  'danger',
  'courage',
  'hope',
  'uncertainty',
  'celebration',
  'togetherness',
  'solemnity',
  'wonder',
  // Situations second
  'workplace_conflict',
  'unfair_authority',
  'relationship_conflict',
  'rejection',
  'failure',
  'grief',
  'illness',
  'financial_stress',
  'parenting_struggle',
  'self_doubt',
  'temptation',
  'waiting',
  'injustice',
];

/// Map of tag -> keywords that trigger that tag.
/// Keywords are matched via substring contains (case-insensitive).
/// Each tag has ~10 keywords max for maintainability.
const Map<String, List<String>> tagKeywords = {
  // === EMOTIONS (7) ===
  'overwhelmed': [
    'overwhelmed',
    'too much',
    "can't keep up",
    'drowning',
    'burned out',
    'burnt out',
    'exhausted',
    'swamped',
    'tired',
    'drained',
    'maxed out',
    'at my limit',
    'spread thin',
  ],
  'anxious': [
    'anxious',
    'worried',
    'stress',
    'panic',
    'nervous',
    'afraid',
    'scared',
    'terrified',
    'dread',
    'overthinking',
  ],
  'sad': [
    'sad',
    'down',
    'depressed',
    'empty',
    'crying',
    'tears',
    'miserable',
    'unhappy',
  ],
  'angry': [
    'angry',
    'mad',
    'furious',
    'resentful',
    'frustrated',
    'annoyed',
    'rage',
    'bitter',
  ],
  'lonely': [
    'lonely',
    'feel alone',
    'feeling alone',
    'feel isolated',
    'feeling isolated',
    'by myself',
    'abandoned',
    'all alone',
  ],
  'hopeless': [
    'hopeless',
    'giving up',
    'no point',
    'despair',
    "can't go on",
    'no hope',
    'pointless',
  ],
  'grateful': [
    'grateful',
    'thankful',
    'blessed',
    'appreciate',
    'gratitude',
    'thank god',
  ],

  // === SITUATIONS (13) ===
  'workplace_conflict': [
    'job',
    'office',
    'coworker',
    'colleague',
    'career',
    'workplace',
    'hr',
    'work drama',
  ],
  'unfair_authority': [
    'boss',
    'manager',
    'supervisor',
    'teacher',
    'yelled at',
    'mistreated',
    'bully',
    'bullied',
    'abusive',
  ],
  'relationship_conflict': [
    'spouse',
    'husband',
    'wife',
    'partner',
    'marriage',
    'divorce',
    'girlfriend',
    'boyfriend',
    'we argued',
    'fight with',
    'silent treatment',
  ],
  'rejection': [
    'rejected',
    'left out',
    'ignored',
    'dismissed',
    'not chosen',
    'unwanted',
    'excluded',
    'overlooked',
  ],
  'failure': [
    'failed',
    'messed up',
    'mistake',
    'blew it',
    "didn't work",
    'screwed up',
    'bombed',
    'flopped',
  ],
  'grief': [
    'grief',
    'loss',
    'died',
    'death',
    'passed away',
    'miss them',
    'mourning',
    'funeral',
  ],
  'illness': [
    'sick',
    'ill',
    'diagnosis',
    'pain',
    'hospital',
    'doctor',
    'disease',
    'surgery',
    'symptoms',
    'fever',
    'injury',
    'chronic',
  ],
  'financial_stress': [
    'money',
    'bills',
    'debt',
    'afford',
    'broke',
    'financial',
    'rent',
    'mortgage',
    'bankrupt',
  ],
  'parenting_struggle': [
    'kids',
    'children',
    'son',
    'daughter',
    'parenting',
    'teenager',
    'toddler',
  ],
  'self_doubt': [
    'not good enough',
    'imposter',
    'doubt myself',
    'worthless',
    'inadequate',
    'incompetent',
    "can't do",
    'useless',
  ],
  'temptation': [
    'tempted',
    'temptation',
    'addicted',
    'craving',
    'addiction',
    'relapse',
    'urge',
  ],
  'waiting': [
    'waiting',
    'patience',
    'how long',
    'when will',
    'still waiting',
    'delayed',
    'stuck',
  ],
  'injustice': [
    'unfair',
    'injustice',
    "shouldn't happen",
    'not right',
    'unjust',
    'discrimination',
    'double standard',
    'played favorites',
    'treated unfairly',
  ],
};

/// Low-signal inputs that should skip relatability matching.
/// When user input matches one of these (after normalization), return empty tags.
const Set<String> lowSignalInputs = {
  'ok',
  'okay',
  'fine',
  'good',
  'alright',
  'meh',
  'idk',
  'yes',
  'no',
  'hi',
  'hello',
  'hey',
  'thanks',
  'thank you',
};

/// Minimum input length (characters) required for tag extraction.
/// Inputs shorter than this return empty tags.
const int minInputLength = 5;

/// Maximum number of tags to extract from user input.
const int maxExtractedTags = 3;

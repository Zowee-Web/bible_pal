// Relatability Tags - Single source of truth for tag vocabulary
// Used by RelatabilityMatcher to extract tags from user input and match stories.
//
// Tag categories (flat storage, categorized here for documentation only):
// - Emotions (7 v1 + 8 PR β + 10 PR β extension = 25): overwhelmed, anxious,
//   sad, angry, lonely, hopeless, grateful, danger, courage, hope, uncertainty,
//   celebration, togetherness, solemnity, wonder, anguish, loneliness,
//   persecution, unheard, longing, doubt, patience, fear, desperation, faith
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
//
// PR β extension (2026-05): added 10 more emotional registers actually used
// by the corpus manifest (anguish, loneliness, persecution, unheard, longing,
// doubt, patience, fear, desperation, faith). Same pattern as the original 8 —
// tagOrder entries only, no tagKeywords additions. Adding keywords would
// change matcher behavior on user input, which remains out of scope for
// vocab-allowlist work.

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
  // PR β extension — additional registers used by the corpus manifest
  'anguish',
  'loneliness',
  'persecution',
  'unheard',
  'longing',
  'doubt',
  'patience',
  'fear',
  'desperation',
  'faith',
  // Test-health pass (2026-06) — register tags authored across the corpus,
  // surfaced into the annotation vocab (registers, not user-extracted).
  'accompanied', 'afraid', 'alone', 'amazed', 'awakened', 'awe',
  'awed', 'blessed', 'brave', 'broken', 'called', 'calm',
  'challenged', 'comforted', 'committed', 'confused', 'convicted', 'courageous',
  'crying', 'curious', 'delighted', 'devastated', 'discouraged', 'earnest',
  'emboldened', 'encouraged', 'exalted', 'exposed', 'fearful', 'feeling_small',
  'free', 'generous', 'grieved', 'grieving', 'growing', 'helped',
  'holding on', 'honored', 'hopeful', 'humbled', 'hurting', 'in_trouble',
  'interceding', 'joyful', 'kind', 'known', 'lamenting', 'left_out',
  'listening', 'loved', 'loving', 'missing_someone', 'moved', 'not alone',
  'patient', 'peaceful', 'reassured', 'redeemed', 'relieved', 'renewed',
  'resolute', 'reverent', 'safe', 'scared_dark', 'scattered', 'seen',
  'sent', 'settled', 'small', 'solemn', 'sorrowful', 'steadfast',
  'steady', 'stirred', 'stripped', 'strong', 'stunned', 'surrounded',
  'tender', 'tired', 'trembling', 'trusting', 'uncertain', 'valued',
  'vindicated', 'watchful', 'weary', 'weighed', 'weighted', 'weighty',
  'wondering', 'wonderstruck',
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
  // Kid situations — child's-life equivalents of the adult situation tags.
  // Additive: adult stories carry none of these (and the kidFriendly filter keeps
  // kid stories out of adult pools), so adult matching is unchanged.
  'left_out',
  'scared_dark',
  'in_trouble',
  'missing_someone',
  'feeling_small',
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

  // === KID SITUATIONS (5) ===
  // Child's-life equivalents of the adult situation tags. Only kid stories are
  // tagged with these; the kidFriendly filter keeps kid stories out of adult
  // pools, and no adult story carries these tags, so adult ranking is unchanged.
  'left_out': [
    'left me out',
    'no one played',
    "wouldn't play with me",
    "didn't play with me",
    "didn't sit with me",
    'picked last',
    'no friends',
    'nobody likes me',
    'no one to play with',
    'left me behind',
  ],
  'scared_dark': [
    'scared of the dark',
    'afraid of the dark',
    'nightmare',
    'bad dream',
    'monster',
    'scared to sleep',
    'scary dream',
    'under my bed',
  ],
  'in_trouble': [
    'got in trouble',
    'in trouble',
    'did something bad',
    'i was bad',
    'i was naughty',
    'i lied',
    'did something wrong',
    'broke it',
  ],
  'missing_someone': [
    'miss my mom',
    'miss my dad',
    'miss mommy',
    'miss daddy',
    'miss grandma',
    'miss grandpa',
    'moved away',
    'far from home',
    'went away',
  ],
  'feeling_small': [
    'too little',
    'too small',
    'just a kid',
    "i'm little",
    'too young',
    'not big enough',
    'everyone is bigger',
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

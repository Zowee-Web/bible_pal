// Reflection Templates - Pre-written reflection content by mood and tag
// SAFETY: All templates MUST comply with INVARIANTS.md Reflection Language Safety
// - Descriptive only, no prescriptions
// - No advice, diagnosis, or therapeutic claims
// - Kid mode uses short, literal language

/// Reflection content for a given context
class ReflectionContent {
  final String text;
  final String? question;

  const ReflectionContent({
    required this.text,
    this.question,
  });
}

/// Adult reflection templates by mood
/// Language: descriptive patterns, "stories like this show...", "often looks like..."
/// Each reflection ends with a soft landing line for gentle closure.
const Map<String, ReflectionContent> adultReflectionsByMood = {
  'joyful': ReflectionContent(
    text:
        'Stories of joy often reflect moments when gratitude and connection come together. '
        'These narratives show how small blessings can accumulate into a sense of abundance. '
        'And even a small step forward can be enough for today.',
    question: 'What small moment from today stands out to you?',
  ),
  'weary': ReflectionContent(
    text:
        'Weariness in stories often looks like carrying burdens over long stretches. '
        'These narratives show that rest and renewal are part of the natural rhythm of life. '
        'And even a small step forward can be enough for today.',
    question: 'Where might rest be waiting for you?',
  ),
  'anxious': ReflectionContent(
    text:
        'Stories about worry often reflect the tension between what we can control and what we cannot. '
        'These narratives show that peace sometimes comes from releasing our grip on outcomes. '
        'And even a small step forward can be enough for today.',
    question: 'What feels most uncertain right now?',
  ),
  'hurting': ReflectionContent(
    text:
        'Pain in stories often looks like walking through seasons of loss or disappointment. '
        'These narratives show that sorrow and hope can exist together. '
        'And even a small step forward can be enough for today.',
    question: 'What would comfort look like today?',
  ),
  'grateful': ReflectionContent(
    text:
        'Gratitude in stories often looks like noticing what was always there but easy to overlook. '
        'These narratives show how thankfulness can shift the way we see even difficult seasons. '
        'And even a small step forward can be enough for today.',
    question: 'What is one thing you\'re grateful for right now?',
  ),
  'brave_courage': ReflectionContent(
    text:
        'Courage in stories often looks less like fearlessness and more like taking the next step anyway. '
        'These narratives show that bravery is usually quieter than we expect. '
        'And even a small step forward can be enough for today.',
    question: 'Where might you be braver than you realize?',
  ),
  'calm_peaceful': ReflectionContent(
    text:
        'Peace in stories often arrives not when circumstances change, but when perspective does. '
        'These narratives show that stillness can be its own kind of strength. '
        'And even a small step forward can be enough for today.',
    question: 'Where do you find stillness in your day?',
  ),
  'encouraging': ReflectionContent(
    text:
        'Encouragement in stories often comes from unexpected places — a word, a gesture, a memory. '
        'These narratives show that hope has a way of showing up when we need it most. '
        'And even a small step forward can be enough for today.',
    question: 'Who has encouraged you recently?',
  ),
  'neutral': ReflectionContent(
    text:
        'Stories of ordinary days often reflect the steady rhythm of daily faithfulness. '
        'These narratives show that meaning can be found in quiet, unremarkable moments. '
        'And even a small step forward can be enough for today.',
    question: 'What ordinary thing might deserve a second look?',
  ),
};

/// Adult reflection templates by emotional tag (from relatability_tags.dart)
/// Used when story has matching emotional tags
/// Each reflection ends with a soft landing line for gentle closure.
const Map<String, ReflectionContent> adultReflectionsByTag = {
  'overwhelmed': ReflectionContent(
    text:
        'Stories of overwhelm often reflect seasons when demands exceed capacity. '
        'These narratives show that limits are not failures—they are part of being human. '
        'And even a small step forward can be enough for today.',
    question: 'What one thing might be set down, even briefly?',
  ),
  'anxious': ReflectionContent(
    text:
        'Anxiety in stories often looks like minds racing ahead to futures not yet here. '
        'These narratives show that the present moment is often more stable than our fears suggest. '
        'And even a small step forward can be enough for today.',
    question: 'What is actually true right now, in this moment?',
  ),
  'sad': ReflectionContent(
    text:
        'Sadness in stories often reflects something valued that has been lost or changed. '
        'These narratives show that grief can be a form of honoring what mattered. '
        'And even a small step forward can be enough for today.',
    question: 'What might your sadness be honoring?',
  ),
  'angry': ReflectionContent(
    text:
        'Anger in stories often points to boundaries that have been crossed or needs unmet. '
        'These narratives show that anger can carry important information about what matters. '
        'And even a small step forward can be enough for today.',
    question: 'What might your frustration be protecting?',
  ),
  'lonely': ReflectionContent(
    text:
        'Loneliness in stories often looks like distance—from others, from purpose, from self. '
        'These narratives show that connection can take many forms, some unexpected. '
        'And even a small step forward can be enough for today.',
    question: 'Where might connection already exist, even in small ways?',
  ),
  'hopeless': ReflectionContent(
    text:
        'Stories of despair often reflect moments when the path forward seems invisible. '
        'These narratives show that new beginnings sometimes emerge from endings. '
        'And even a small step forward can be enough for today.',
    question: 'What tiny possibility might still remain?',
  ),
  'grateful': ReflectionContent(
    text:
        'Gratitude in stories often reflects a shift in perspective—seeing gifts hidden in plain sight. '
        'These narratives show that thankfulness can reshape how ordinary days feel. '
        'And even a small step forward can be enough for today.',
    question: 'What unexpected gift appeared recently?',
  ),
  'workplace_conflict': ReflectionContent(
    text:
        'Workplace tensions in stories often reflect competing values or misunderstood intentions. '
        'These narratives show that patience and clarity can shift difficult dynamics over time. '
        'And even a small step forward can be enough for today.',
    question: 'What might you not yet fully understand about the situation?',
  ),
  'unfair_authority': ReflectionContent(
    text:
        'Stories of unjust authority often reflect power imbalances and the ache for fairness. '
        'These narratives show that dignity persists even when circumstances are unjust. '
        'And even a small step forward can be enough for today.',
    question: 'What truth about yourself remains unchanged by this situation?',
  ),
  'relationship_conflict': ReflectionContent(
    text:
        'Conflict with loved ones in stories often reflects the complexity of intimacy. '
        'These narratives show that repair and understanding can follow rupture. '
        'And even a small step forward can be enough for today.',
    question: 'What might the other person be experiencing?',
  ),
  'rejection': ReflectionContent(
    text:
        'Rejection in stories often looks like doors closing and questions about worth arising. '
        'These narratives show that belonging is not always found where we first seek it. '
        'And even a small step forward can be enough for today.',
    question: 'Where have you been welcomed before?',
  ),
  'failure': ReflectionContent(
    text:
        'Failure in stories often reflects attempts that did not go as hoped. '
        'These narratives show that learning and growth frequently emerge from missteps. '
        'And even a small step forward can be enough for today.',
    question: 'What might this experience be teaching?',
  ),
  'grief': ReflectionContent(
    text:
        'Grief in stories often reflects the depth of love for someone or something now absent. '
        'These narratives show that mourning is the heart\'s way of honoring what was treasured. '
        'And even a small step forward can be enough for today.',
    question: 'What memory brings both tears and gratitude?',
  ),
  'illness': ReflectionContent(
    text:
        'Illness in stories often reflects the body\'s limits and the soul\'s resilience. '
        'These narratives show that vulnerability and strength can coexist. '
        'And even a small step forward can be enough for today.',
    question: 'What does your body need most right now?',
  ),
  'financial_stress': ReflectionContent(
    text:
        'Financial worry in stories often reflects the weight of providing and planning. '
        'These narratives show that security has many dimensions beyond money alone. '
        'And even a small step forward can be enough for today.',
    question: 'What resources do you have that cannot be counted?',
  ),
  'parenting_struggle': ReflectionContent(
    text:
        'Parenting challenges in stories often reflect the gap between hopes and daily reality. '
        'These narratives show that imperfect love can still be deeply nourishing. '
        'And even a small step forward can be enough for today.',
    question: 'What small moment of connection happened recently?',
  ),
  'self_doubt': ReflectionContent(
    text:
        'Self-doubt in stories often reflects internal voices questioning competence or worth. '
        'These narratives show that confidence often grows through action, not waiting. '
        'And even a small step forward can be enough for today.',
    question: 'What have you done before that once felt impossible?',
  ),
  'temptation': ReflectionContent(
    text:
        'Temptation in stories often reflects the pull between immediate relief and longer-term values. '
        'These narratives show that struggle itself can be a sign of growth. '
        'And even a small step forward can be enough for today.',
    question: 'What value are you trying to protect?',
  ),
  'waiting': ReflectionContent(
    text:
        'Waiting in stories often looks like time moving slowly while hope and doubt trade places. '
        'These narratives show that seasons of waiting can also be seasons of preparation. '
        'And even a small step forward can be enough for today.',
    question: 'What might be growing while you wait?',
  ),
  'injustice': ReflectionContent(
    text:
        'Injustice in stories often reflects systems or people acting against what is right. '
        'These narratives show that standing for truth has a long and honored tradition. '
        'And even a small step forward can be enough for today.',
    question: 'What small step toward justice might be possible?',
  ),
};

/// Kid-mode reflection templates by mood
/// Language: short, literal, no abstract concepts, age-appropriate (5-9)
/// Each reflection ends with a gentle closing line.
const Map<String, ReflectionContent> kidReflectionsByMood = {
  'joyful': ReflectionContent(
    text: 'This story shows that good things happen when we share with others. '
        'Even one small kindness matters.',
  ),
  'weary': ReflectionContent(
    text: 'This story shows that it is okay to rest when we are tired. '
        'Even one small rest can help.',
  ),
  'anxious': ReflectionContent(
    text: 'This story shows that when things feel scary, we are not alone. '
        'Even one small brave step counts.',
  ),
  'hurting': ReflectionContent(
    text:
        'This story shows that being kind matters, even when things are hard. '
        'Even one small kindness helps.',
  ),
  'grateful': ReflectionContent(
    text: 'This story shows that saying thank you can make us feel happy. '
        'Even one small thank you matters.',
  ),
  'brave_courage': ReflectionContent(
    text: 'This story shows that being brave does not mean not being scared. '
        'Even one small brave step counts.',
  ),
  'calm_peaceful': ReflectionContent(
    text: 'This story shows that being still and quiet can feel really good. '
        'Even one small quiet moment helps.',
  ),
  'encouraging': ReflectionContent(
    text: 'This story shows that kind words can make someone\'s day better. '
        'Even one small encouragement helps.',
  ),
  'neutral': ReflectionContent(
    text: 'This story shows that every day has moments worth noticing. '
        'Even one small thing can be special.',
  ),
};

/// Kid-mode reflection templates by emotional tag
/// Simpler versions of the adult templates
/// Each reflection ends with a gentle closing line.
const Map<String, ReflectionContent> kidReflectionsByTag = {
  'overwhelmed': ReflectionContent(
    text: 'This story shows that asking for help is okay. '
        'Even one small step forward is good.',
  ),
  'anxious': ReflectionContent(
    text: 'This story shows that worries can feel big, but we can be brave. '
        'One small brave thing counts.',
  ),
  'sad': ReflectionContent(
    text: 'This story shows that feeling sad means we care about things. '
        'Even one small moment of care helps.',
  ),
  'angry': ReflectionContent(
    text: 'This story shows that even when we feel upset, kindness can help. '
        'Even one small kindness matters.',
  ),
  'lonely': ReflectionContent(
    text: 'This story shows that friends can appear in unexpected places. '
        'Even one small hello matters.',
  ),
  'hopeless': ReflectionContent(
    text: 'This story shows that things can get better, even when hard. '
        'Even one small hope is enough.',
  ),
  'grateful': ReflectionContent(
    text: 'This story shows that saying thank you makes everyone feel good. '
        'One small thank you matters.',
  ),
  'rejection': ReflectionContent(
    text: 'This story shows that being left out hurts, but friends are near. '
        'Even one friend is a gift.',
  ),
  'failure': ReflectionContent(
    text: 'This story shows that mistakes help us learn and try again. '
        'Even one small try counts.',
  ),
  'waiting': ReflectionContent(
    text: 'This story shows that good things sometimes take time. '
        'Even one small wait can be worth it.',
  ),
};

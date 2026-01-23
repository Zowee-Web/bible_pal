import 'dart:math';

/// Verse Service
/// Provides mood-appropriate Bible verses for the conversational experience
///
/// SCRIPTURE LICENSING COMPLIANCE:
/// All verse text uses World English Bible (WEB) translation - Public Domain
/// Source: https://worldenglish.bible
/// WEB is completely free and unrestricted for all uses
class VerseService {
  final Random _random = Random();

  /// Get a verse and context appropriate for the detected mood
  VerseResponse getVerseForMood(String mood) {
    switch (mood) {
      case 'joyful':
        return _randomChoice(_joyfulVerses);
      case 'weary':
        return _randomChoice(_wearyVerses);
      case 'anxious':
        return _randomChoice(_anxiousVerses);
      case 'hurting':
        return _randomChoice(_hurtingVerses);
      case 'neutral':
      default:
        return _randomChoice(_neutralVerses);
    }
  }

  /// Randomly select a verse from a list
  VerseResponse _randomChoice(List<VerseResponse> verses) {
    return verses[_random.nextInt(verses.length)];
  }

  /// Joyful verses - celebrating gratitude and blessings
  static const List<VerseResponse> _joyfulVerses = [
    VerseResponse(
      reference: 'Psalm 118:24',
      text:
          'This is the day that Yahweh has made. We will rejoice and be glad in it!',
      context:
          'Your joy is a gift. This psalm reminds us that every day is crafted by God\'s hand, worthy of celebration.',
    ),
    VerseResponse(
      reference: 'Philippians 4:4',
      text: 'Rejoice in the Lord always! Again I will say, "Rejoice!"',
      context:
          'Paul encourages us to find joy not in circumstances, but in the constant presence of the Lord.',
    ),
    VerseResponse(
      reference: '1 Thessalonians 5:16-18',
      text:
          'Rejoice always. Pray without ceasing. In everything give thanks, for this is the will of God in Christ Jesus toward you.',
      context:
          'Gratitude is more than a feeling—it\'s a practice that draws us closer to God\'s heart.',
    ),
  ];

  /// Weary verses - offering rest and renewal
  static const List<VerseResponse> _wearyVerses = [
    VerseResponse(
      reference: 'Matthew 11:28-30',
      text:
          'Come to me, all you who labor and are heavily burdened, and I will give you rest. Take my yoke upon you and learn from me, for I am gentle and humble in heart; and you will find rest for your souls.',
      context:
          'Jesus offers an invitation to those who are exhausted. Rest is not weakness—it\'s a sacred trust in God\'s provision.',
    ),
    VerseResponse(
      reference: 'Psalm 23:1-3',
      text:
          'Yahweh is my shepherd; I shall lack nothing. He makes me lie down in green pastures. He leads me beside still waters. He restores my soul.',
      context:
          'The Good Shepherd knows when we need rest. He doesn\'t drive us relentlessly but leads us to places of renewal.',
    ),
    VerseResponse(
      reference: 'Isaiah 40:28-31',
      text:
          'He gives power to the weak. He increases the strength of him who has no might. Even the youths faint and get weary, and the young men utterly fall; but those who wait for Yahweh will renew their strength.',
      context:
          'When our own strength fails, God\'s strength becomes available. Waiting on Him is not passive—it\'s a posture of trust.',
    ),
  ];

  /// Anxious verses - bringing peace and calm
  static const List<VerseResponse> _anxiousVerses = [
    VerseResponse(
      reference: 'Philippians 4:6-7',
      text:
          'In nothing be anxious, but in everything, by prayer and petition with thanksgiving, let your requests be made known to God. And the peace of God, which surpasses all understanding, will guard your hearts and your thoughts in Christ Jesus.',
      context:
          'Anxiety loses its power when we bring it into God\'s presence. His peace is not just absence of trouble, but a presence that guards our hearts.',
    ),
    VerseResponse(
      reference: 'Matthew 6:25-34',
      text:
          'Therefore I tell you, don\'t be anxious for your life... See the birds of the sky, that they don\'t sow, neither do they reap, nor gather into barns. Your heavenly Father feeds them. Aren\'t you of much more value than they?',
      context:
          'Jesus reminds us that the God who cares for sparrows cares infinitely more for you. Worry cannot add a single hour to your life, but trust can change how you live each hour.',
    ),
    VerseResponse(
      reference: 'Isaiah 41:10',
      text:
          'Don\'t you be afraid, for I am with you. Don\'t be dismayed, for I am your God. I will strengthen you. Yes, I will help you. Yes, I will uphold you with the right hand of my righteousness.',
      context:
          'God doesn\'t say the threatening circumstances will disappear, but that He will be present in them with you.',
    ),
  ];

  /// Hurting verses - offering comfort and healing
  static const List<VerseResponse> _hurtingVerses = [
    VerseResponse(
      reference: 'Psalm 34:18',
      text:
          'Yahweh is near to those who have a broken heart, and saves those who have a crushed spirit.',
      context:
          'God doesn\'t stand at a distance from our pain. He draws close, especially when our hearts are breaking.',
    ),
    VerseResponse(
      reference: '2 Corinthians 1:3-4',
      text:
          'Blessed be the God and Father of our Lord Jesus Christ, the Father of mercies and God of all comfort, who comforts us in all our affliction, that we may be able to comfort those who are in any affliction.',
      context:
          'The comfort God gives us in our pain is never meant to end with us. It becomes a gift we can share with others who hurt.',
    ),
    VerseResponse(
      reference: 'Romans 8:28',
      text:
          'We know that all things work together for good for those who love God, for those who are called according to his purpose.',
      context:
          'This doesn\'t mean all things are good, but that God is at work even in painful circumstances, weaving them into something redemptive.',
    ),
    VerseResponse(
      reference: 'Psalm 147:3',
      text: 'He heals the broken in heart, and binds up their wounds.',
      context:
          'Healing is God\'s nature. He is the gentle physician who tends to our deepest wounds with care and patience.',
    ),
  ];

  /// Neutral verses - general encouragement and wisdom
  static const List<VerseResponse> _neutralVerses = [
    VerseResponse(
      reference: 'Proverbs 3:5-6',
      text:
          'Trust in Yahweh with all your heart, and don\'t lean on your own understanding. In all your ways acknowledge him, and he will make your paths straight.',
      context:
          'Faith is learning to trust God\'s wisdom even when the path ahead isn\'t clear to us.',
    ),
    VerseResponse(
      reference: 'Hebrews 11:1',
      text:
          'Now faith is assurance of things hoped for, proof of things not seen.',
      context:
          'Faith is not blind optimism, but a confident trust in God\'s character and promises, even when we can\'t see the outcome.',
    ),
    VerseResponse(
      reference: 'James 1:2-4',
      text:
          'Count it all joy, my brothers, when you fall into various temptations, knowing that the testing of your faith produces endurance.',
      context:
          'Trials are not punishments but opportunities for faith to grow stronger, like a muscle strengthened through use.',
    ),
  ];
}

/// Response containing verse, reference, and contextual explanation
class VerseResponse {
  final String reference;
  final String text;
  final String context;
  final String
      translation; // Bible translation label (e.g., 'WEB', 'KJV', 'ASV')

  const VerseResponse({
    required this.reference,
    required this.text,
    required this.context,
    this.translation = 'WEB', // Default to World English Bible (public domain)
  });
}

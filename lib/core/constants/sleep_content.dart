// sleep_content.dart
// All types, keyword corpus, and response content for the sleep module.
// Pure Dart — no Flutter imports.
//
// IMPROVEMENTS APPLIED:
//  1. Synonym expansion  — each intent has a synonyms map that maps
//     variant words to their canonical form before scoring.
//  2. N-gram support     — 2- and 3-word phrases are stored separately
//     and weighted 2× / 3× vs single keywords.
//  3. Negation awareness — negation prefix list used by the engine
//     to discount intents whose keywords follow a negation marker.

import 'dart:math';

// ════════════════════════════════════════════════════════════════
// 1. TYPES
// ════════════════════════════════════════════════════════════════

enum SleepIntent {
  greeting,
  gratitude,
  repeat,
  help,
  affirmation,
  negation,
  cantSleep,
  bedtimeRoutine,
  sleepTips,
  screenTime,
  nap,
  wakeTime,
  sleepDuration,
  stressed,
  tired,
  frustrated,
  unknown,
}

enum EmotionalTone { stressed, tired, frustrated, neutral }

class SleepResponse {
  final String message;
  final SleepIntent intent;
  final EmotionalTone tone;
  final List<SleepTip>? tips;
  final List<String>? routineSteps;
  final List<String>? suggestions;
  final String? handoffRoute;
  final bool isCrisis;
  final double confidence;

  const SleepResponse({
    required this.message,
    required this.intent,
    this.tone = EmotionalTone.neutral,
    this.tips,
    this.routineSteps,
    this.suggestions,
    this.handoffRoute,
    this.isCrisis = false,
    this.confidence = 1.0,
  });
}

class SleepTip {
  final String emoji;
  final String title;
  final String body;

  const SleepTip({
    required this.emoji,
    required this.title,
    required this.body,
  });
}

class ChatMessage {
  final bool isUser;
  final String text;
  final DateTime timestamp;
  final SleepIntent? intent;
  final double? confidence;

  ChatMessage({
    required this.isUser,
    required this.text,
    this.intent,
    this.confidence,
  }) : timestamp = DateTime.now();
}

class IntentLog {
  final DateTime time;
  final String input;
  final SleepIntent intent;
  final double confidence;
  final EmotionalTone tone;

  IntentLog({
    required this.input,
    required this.intent,
    required this.confidence,
    required this.tone,
  }) : time = DateTime.now();

  @override
  String toString() =>
      '[${time.hour}:${time.minute.toString().padLeft(2, '0')}] '
          'intent=${intent.name} conf=${confidence.toStringAsFixed(2)} '
          'tone=${tone.name} input="$input"';
}

// ════════════════════════════════════════════════════════════════
// 2. CORPUS
// ════════════════════════════════════════════════════════════════

class SleepCorpus {
  SleepCorpus._();

  static final _random = Random();

  static String pick(List<String> variants) =>
      variants[_random.nextInt(variants.length)];

  // ── Crisis ───────────────────────────────────────────────────
  static const List<String> crisisKeywords = [
    "don't want to wake up",
    "dont want to wake up",
    "never wake up",
    "sleep forever",
    "wish i wouldn't wake",
    "wish i wouldnt wake",
    "not wake up",
    "sleep and not wake",
    "go to sleep forever",
  ];

  // ── Handoff triggers ─────────────────────────────────────────
  static const Map<String, List<String>> handoffTriggers = {
    '/breathing': [
      'i feel anxious',
      "i'm anxious",
      'im anxious',
      'help me relax',
      'calm me down',
      'i am panicking',
      'having a panic',
      'panic attack',
      'anxious at night',
      'anxiety before bed',
    ],
    '/meditation': [
      'meditate before bed',
      'guided meditation',
      'meditation for sleep',
      'open meditation',
    ],
    '/psychoeducation': [
      'i feel depressed',
      "i'm depressed",
      'im depressed',
      'depression and sleep',
    ],
  };

  // ── Direct entry ─────────────────────────────────────────────
  static const List<String> directEntryKeywords = [
    'sleep module',
    'sleep hygiene',
    'sleep tips',
    'bedtime help',
    'open sleep',
    'go to sleep module',
    'help me sleep',
    'sleep support',
    'sleep health',
    'sleep problems',
    'sleeping problems',
    'sleep issues',
    'sleeping issues',
    'talk about sleep',
    'sleep advice',
  ];

  // ── Exit ─────────────────────────────────────────────────────
  static const List<String> exitKeywords = [
    'exit',
    'back',
    'bye',
    'goodbye',
    'stop',
    'quit',
    'go back',
    'home',
    'leave',
    'done',
    'enough',
    'close',
  ];

  // ════════════════════════════════════════════════════════════════
  // IMPROVEMENT 1 — SYNONYM EXPANSION
  // Maps alternate/informal words → canonical form.
  // Applied during normalisation so every other corpus list stays
  // clean (no need to list every variant in intentKeywords).
  // ════════════════════════════════════════════════════════════════
  static const Map<String, String> synonymMap = {
    // Can't sleep variants
    'insomnia':           'cant sleep',
    'sleeplessness':      'cant sleep',
    'sleepless':          'cant sleep',
    'insomniac':          'cant sleep',
    'wakefulness':        'cant sleep',

    // Tired variants
    'exhausted':          'tired',
    'drained':            'tired',
    'fatigued':           'tired',
    'worn out':           'tired',
    'burnt out':          'tired',
    'burned out':         'tired',
    'lethargic':          'tired',
    'drowsy':             'tired',
    'sluggish':           'tired',
    'weary':              'tired',
    'knackered':          'tired',
    'shattered':          'tired',
    'dead tired':         'tired',

    // Stressed variants
    'overwhelmed':        'stressed',
    'anxious':            'stressed',
    'nervous':            'stressed',
    'tense':              'stressed',
    'on edge':            'stressed',
    'wound up':           'stressed',
    'worked up':          'stressed',
    'freaking out':       'stressed',
    'panicky':            'stressed',
    'restless':           'stressed',

    // Frustrated variants
    'annoyed':            'frustrated',
    'irritated':          'frustrated',
    'fed up':             'frustrated',
    'agitated':           'frustrated',
    'upset':              'frustrated',
    'pissed off':         'frustrated',

    // Screen time variants
    'phone':              'screen',
    'smartphone':         'screen',
    'tablet':             'screen',
    'laptop':             'screen',
    'computer':           'screen',
    'tv':                 'screen',
    'television':         'screen',
    'device':             'screen',
    'tiktok':             'screen',
    'instagram':          'screen',
    'youtube':            'screen',
    'social media':       'screen',
    'scrolling':          'screen',
    'doomscrolling':      'screen',
    'doom scrolling':     'screen',

    // Nap variants
    'siesta':             'nap',
    'power nap':          'nap',
    'afternoon sleep':    'nap',
    'daytime sleep':      'nap',
    'midday sleep':       'nap',
    'catnap':             'nap',

    // Routine variants
    'wind down':          'bedtime routine',
    'winding down':       'bedtime routine',
    'pre sleep':          'bedtime routine',
    'night routine':      'bedtime routine',
    'evening routine':    'bedtime routine',
    'before bed':         'bedtime routine',

    // Duration variants
    'hours of rest':      'hours of sleep',
    'sleep time':         'sleep duration',
    'rest time':          'sleep duration',
    'sleeping hours':     'sleep duration',

    // Wake time variants
    'alarm':              'wake time',
    'body clock':         'circadian',
    'internal clock':     'circadian',
    'circadian rhythm':   'circadian',
    'sleep schedule':     'wake time',
    'sleep pattern':      'wake time',
    'social jetlag':      'wake time',

    // General tips variants
    'melatonin':          'sleep tips',
    'white noise':        'sleep tips',
    'sleep environment':  'sleep tips',
    'bedroom':            'sleep tips',
    'caffeine':           'sleep tips',
    'alcohol':            'sleep tips',
    'exercise':           'sleep tips',
  };

  // ════════════════════════════════════════════════════════════════
  // IMPROVEMENT 2 — NEGATION AWARENESS
  // If any of these prefixes immediately precede an intent keyword,
  // that intent's score is penalised in the engine.
  // ════════════════════════════════════════════════════════════════
  static const List<String> negationPrefixes = [
    "don't want",
    "dont want",
    "do not want",
    "not looking for",
    "don't need",
    "dont need",
    "do not need",
    "no need for",
    "not interested in",
    "not asking about",
    "i don't want",
    "i dont want",
    "i do not want",
    "without",
    "not about",
    "nothing about",
    "stop talking about",
    "skip",
    "forget",
    "ignore",
    "not",
    "no",
  ];

  // ════════════════════════════════════════════════════════════════
  // IMPROVEMENT 2 (cont.) — N-GRAM KEYWORD MAP
  // 2- and 3-word phrases. Stored separately from unigrams.
  // Engine weights these: bigram = ×2, trigram = ×3.
  // This allows precise phrases to dominate over accidental
  // single-word collisions.
  // ════════════════════════════════════════════════════════════════

  /// Bigrams (2-word phrases) — weight ×2 in engine scoring.
  static const Map<SleepIntent, List<String>> bigrams = {
    SleepIntent.cantSleep: [
      'cant sleep',
      'cannot sleep',
      'trouble sleeping',
      'lying awake',
      'no sleep',
      'wide awake',
      'sleepless night',
      'racing thoughts',
      'tossing turning',
      'sleep deprivation',
      'restless night',
      'keep waking',
    ],
    SleepIntent.screenTime: [
      'screen time',
      'blue light',
      'phone bed',
      'scroll bed',
      'screen bed',
      'device bed',
    ],
    SleepIntent.bedtimeRoutine: [
      'bedtime routine',
      'night routine',
      'wind down',
      'pre sleep',
      'sleep routine',
      'before bed',
      'going bed',
    ],
    SleepIntent.nap: [
      'power nap',
      'short nap',
      'quick nap',
      'daytime sleep',
      'afternoon nap',
      'midday nap',
    ],
    SleepIntent.sleepDuration: [
      'how long',
      'enough sleep',
      'hours sleep',
      'sleep debt',
      'too little',
      'not enough',
      'sleep amount',
      'how much',
    ],
    SleepIntent.wakeTime: [
      'wake time',
      'wake up',
      'sleep schedule',
      'body clock',
      'circadian rhythm',
      'sleep pattern',
      'fix schedule',
    ],
    SleepIntent.sleepTips: [
      'sleep tips',
      'sleep advice',
      'sleep better',
      'improve sleep',
      'sleep hygiene',
      'sleep quality',
      'good sleep',
      'sleep hacks',
      'give me',
      'show me',
      'tell me',
      'any tips',
      'any advice',
      'how can',
      'how do',
      'what can',
      'what should',
      'help me',
    ],
    SleepIntent.stressed: [
      'mind racing',
      'cant relax',
      'too stressed',
      'on edge',
      'wound up',
    ],
    SleepIntent.tired: [
      'so tired',
      'no energy',
      'dead tired',
      'worn out',
      'running empty',
    ],
    SleepIntent.frustrated: [
      'nothing works',
      'nothing helps',
      'give up',
      'sick of',
      'fed up',
      'why cant',
    ],
    SleepIntent.greeting: [
      'good morning',
      'good evening',
      'good night',
      'whats up',
    ],
    SleepIntent.help: [
      'what can',
      'how does',
      'what do',
      'show me',
      'guide me',
    ],
  };

  /// Trigrams (3-word phrases) — weight ×3 in engine scoring.
  static const Map<SleepIntent, List<String>> trigrams = {
    SleepIntent.cantSleep: [
      'cant fall asleep',
      'unable to sleep',
      'lying in bed',
      'staring at ceiling',
      'middle of night',
      'been awake all',
      'trouble falling asleep',
      'cant stop thinking',
      'mind wont stop',
      'sleep wont come',
    ],
    SleepIntent.screenTime: [
      'phone before bed',
      'screen before bed',
      'laptop before bed',
      'social media night',
      'blue light glasses',
      'screen affects sleep',
      'tv in bedroom',
    ],
    SleepIntent.bedtimeRoutine: [
      'prepare for sleep',
      'ready for bed',
      'what to do before',
      'calm down before sleep',
      'routine for sleep',
      'habits before bed',
    ],
    SleepIntent.sleepDuration: [
      'how many hours',
      'how much sleep',
      'how long sleep',
      'recommended sleep hours',
      'catching up sleep',
      'not enough sleep',
      'sleeping too much',
      'sleeping too little',
    ],
    SleepIntent.wakeTime: [
      'same wake time',
      'fix sleep schedule',
      'reset sleep cycle',
      'consistent wake time',
      'hard to wake',
      'sleeping through alarm',
      'waking up early',
    ],
    SleepIntent.stressed: [
      'too much on mind',
      'cant stop worrying',
      'mind is racing',
      'so much stress',
    ],
    SleepIntent.tired: [
      'cant keep eyes open',
      'running on empty',
      'no energy left',
    ],
    SleepIntent.frustrated: [
      'why cant i sleep',
      'nothing is working',
      'i give up',
      'sick of this',
      'this isnt working',
    ],
  };

  // ── Intent keyword map (unigrams) ────────────────────────────
  static const Map<SleepIntent, List<String>> intentKeywords = {
    SleepIntent.greeting: [
      'hi', 'hello', 'hey', 'howdy', 'greetings', 'sup', 'hiya',
    ],

    SleepIntent.gratitude: [
      'thanks', 'thank you', 'cheers', 'appreciate',
      'helpful', 'great help',
    ],

    SleepIntent.repeat: [
      'repeat', 'again', 'pardon', 'once more',
      'missed that', 'didnt catch',
    ],

    SleepIntent.help: [
      'help', 'options', 'commands', 'features', 'capabilities',
      'what can you do', 'how does this work', 'how can you help',
      'how do you work', 'what are you', 'how can you',
    ],

    SleepIntent.affirmation: [
      'yes', 'yeah', 'yep', 'yup', 'sure', 'okay', 'ok',
      'alright', 'absolutely', 'definitely', 'please', 'continue',
    ],

    SleepIntent.negation: [
      'no', 'nope', 'nah', 'never mind', 'nevermind',
      'not interested', 'forget it', 'maybe later',
    ],

    SleepIntent.cantSleep: [
      'sleep', 'awake', 'asleep', 'insomnia',
      'sleepless', 'restless', 'tossing', 'turning',
      'waking', 'woke', 'tired', 'dreaming',
    ],

    SleepIntent.screenTime: [
      'screen', 'phone', 'blue light', 'scroll',
      'social media', 'tiktok', 'instagram', 'youtube',
      'doomscrolling', 'device', 'tablet', 'laptop', 'tv',
    ],

    SleepIntent.bedtimeRoutine: [
      'routine', 'ritual', 'habit', 'wind down',
      'prepare', 'ready', 'bedtime', 'night',
    ],

    SleepIntent.nap: [
      'nap', 'napping', 'siesta', 'daytime', 'afternoon',
      'midday', 'catnap', 'lunchtime',
    ],

    SleepIntent.sleepDuration: [
      'hours', 'duration', 'long', 'much', 'enough',
      'debt', 'requirement', 'amount', 'optimal',
    ],

    SleepIntent.wakeTime: [
      'wake', 'alarm', 'morning', 'circadian',
      'schedule', 'pattern', 'rhythm', 'clock',
    ],

    SleepIntent.sleepTips: [
      'tips', 'advice', 'better', 'improve', 'hygiene',
      'quality', 'habits', 'suggestions', 'hacks',
      'caffeine', 'alcohol', 'melatonin', 'exercise',
      'dark', 'cool', 'quiet', 'noise',
    ],

    SleepIntent.stressed: [
      'stressed', 'stress', 'overwhelmed', 'anxious',
      'worried', 'worrying', 'tense', 'nervous', 'restless',
    ],

    SleepIntent.tired: [
      'tired', 'exhausted', 'drained', 'fatigued',
      'sleepy', 'drowsy', 'energy', 'burnout',
    ],

    SleepIntent.frustrated: [
      'frustrated', 'annoyed', 'irritated', 'fed up',
      'angry', 'annoying', 'hate', 'sick',
    ],
  };

  // ── Emotional tone keyword map ────────────────────────────────
  static const Map<EmotionalTone, List<String>> toneKeywords = {
    EmotionalTone.stressed: [
      'stressed', 'overwhelmed', 'anxious', 'worried', 'worrying',
      'on edge', 'tense', 'wound up', 'mind is racing',
    ],
    EmotionalTone.tired: [
      'tired', 'exhausted', 'drained', 'worn out', 'fatigued',
      'sleepy', 'drowsy', 'burned out', 'no energy',
    ],
    EmotionalTone.frustrated: [
      'frustrated', 'annoyed', 'fed up', 'nothing works',
      'nothing helps', 'i give up', 'sick of this',
    ],
  };

  // ════════════════════════════════════════════════════════════════
  // 3. RESPONSE VARIANTS
  // ════════════════════════════════════════════════════════════════

  static const Map<SleepIntent, List<String>> responseVariants = {
    SleepIntent.greeting: [
      "Hello! I'm your sleep assistant. You can ask me about bedtime routines, "
          "why you can't sleep, screen time habits, naps, or general sleep tips.",
      "Hey there! Ready to help with your sleep. What's on your mind — "
          "trouble falling asleep, a bedtime routine, or something else?",
      "Hi! I'm here to help you sleep better. Ask me anything about sleep hygiene, "
          "routines, naps, or what to do when your mind won't switch off.",
    ],

    SleepIntent.gratitude: [
      "You're welcome! Sleep well tonight.",
      "Glad that helped. Feel free to ask anything else.",
      "Of course! Come back anytime you need sleep support.",
      "Happy to help. Wishing you a restful night.",
    ],

    SleepIntent.help: [
      "Here's what I can help with: trouble falling asleep, bedtime routines, "
          "screen time before bed, nap advice, how many hours of sleep you need, "
          "and fixing your wake time. Just ask naturally.",
      "You can ask me things like: 'I can't sleep', 'give me a bedtime routine', "
          "'is napping bad?', 'how much sleep do I need?', or 'help with screen time'.",
      "I specialise in sleep hygiene. Try asking about: insomnia, bedtime wind-down, "
          "blue light, power naps, sleep duration, or wake schedules.",
    ],

    SleepIntent.affirmation: [
      "Great, let's continue.",
      "Alright, here we go.",
      "Sure thing.",
      "Okay, I'll go ahead.",
    ],

    SleepIntent.negation: [
      "No problem, let me know if there's anything else.",
      "Alright, I'm here whenever you need me.",
      "Got it. Just say the word if you'd like help with something.",
    ],

    SleepIntent.unknown: [
      "I didn't quite catch that. Try asking about trouble sleeping, "
          "a bedtime routine, screen time, naps, or sleep duration.",
      "Not sure I understood. You can say things like 'I can't sleep' "
          "or 'give me sleep tips' and I'll help.",
      "Could you rephrase that? I'm best with questions about sleep — "
          "routines, insomnia, naps, wake times, and screen habits.",
      "I didn't get that one. Ask me about bedtime routines, "
          "why you can't sleep, or how much sleep you need.",
    ],
  };

  // ── Tone-adapted prefixes ─────────────────────────────────────
  static const Map<EmotionalTone, List<String>> tonePrefixes = {
    EmotionalTone.stressed: [
      "It sounds like your mind is really busy right now. Let's slow things down. ",
      "I hear you — stress and sleep really don't mix. Here's what can help. ",
      "When stress keeps you awake, your body needs a reset. Let's work on that. ",
    ],
    EmotionalTone.tired: [
      "You sound really drained. Let's get you some proper rest. ",
      "Exhaustion is rough. Here's what will actually help tonight. ",
      "When you're this tired, the right approach matters. Let's cover them. ",
    ],
    EmotionalTone.frustrated: [
      "I understand the frustration — it's genuinely hard when sleep doesn't come. ",
      "That irritation is completely valid. Let's try a different angle. ",
      "Sleep struggles are exhausting in themselves. Here's something concrete to try. ",
    ],
  };

  // ── Contextual follow-up suggestions ─────────────────────────
  static const Map<SleepIntent, List<String>> followUpSuggestions = {
    SleepIntent.cantSleep: [
      "Try a breathing exercise",
      "Give me a bedtime routine",
      "Tips on screen time",
    ],
    SleepIntent.bedtimeRoutine: [
      "What about screen time?",
      "How many hours do I need?",
      "Help, I still can't sleep",
    ],
    SleepIntent.screenTime: [
      "Give me a bedtime routine",
      "I still can't sleep",
      "Tell me about blue light",
    ],
    SleepIntent.nap: [
      "What's the best wake time?",
      "How much sleep do I need?",
      "General sleep tips",
    ],
    SleepIntent.sleepDuration: [
      "Help me fix my wake time",
      "I can't sleep anyway",
      "Give me sleep tips",
    ],
    SleepIntent.wakeTime: [
      "Give me a bedtime routine",
      "How much sleep do I need?",
      "General sleep tips",
    ],
    SleepIntent.sleepTips: [
      "I can't sleep tonight",
      "Give me a bedtime routine",
      "What about naps?",
    ],
    SleepIntent.stressed: [
      "Try a breathing exercise",
      "Give me a bedtime routine",
      "Tips for racing thoughts",
    ],
    SleepIntent.tired: [
      "How much sleep do I need?",
      "Give me sleep tips",
      "Fix my sleep schedule",
    ],
    SleepIntent.frustrated: [
      "What actually works for sleep?",
      "Try a bedtime routine",
      "Help me with screen time",
    ],
  };

  // ── Tips ─────────────────────────────────────────────────────
  static const Map<SleepIntent, List<SleepTip>> intentTips = {
    SleepIntent.cantSleep: [
      SleepTip(
        emoji: '🌬️',
        title: '4-7-8 breathing',
        body: 'Inhale 4 sec, hold 7, exhale 8. Repeat 3 times. '
            'Activates your parasympathetic nervous system immediately.',
      ),
      SleepTip(
        emoji: '🧠',
        title: '20-minute rule',
        body: 'Lying awake trains your brain to associate bed with wakefulness. '
            'Get up after 20 minutes and do something quiet.',
      ),
      SleepTip(
        emoji: '❄️',
        title: 'Cool your room',
        body: 'Core body temp must drop to trigger sleep. '
            'Aim for 16–19°C (60–67°F).',
      ),
    ],

    SleepIntent.screenTime: [
      SleepTip(
        emoji: '🔅',
        title: 'Enable night mode',
        body: 'Use Night Shift (iOS) or Night Light (Android) '
            'if you must use your phone.',
      ),
      SleepTip(
        emoji: '📚',
        title: 'Replace with reading',
        body: 'A physical book relaxes your eyes and slows your thoughts — '
            'the best screen substitute.',
      ),
      SleepTip(
        emoji: '🔌',
        title: 'Charge outside the bedroom',
        body: 'If your phone is on your nightstand, you will check it. '
            'Charge it in another room.',
      ),
    ],

    SleepIntent.nap: [
      SleepTip(
        emoji: '⏱️',
        title: 'Keep it 10–20 minutes',
        body: 'Short naps boost alertness without deep sleep, '
            'so you wake refreshed, not groggy.',
      ),
      SleepTip(
        emoji: '🕒',
        title: 'Nap before 3 PM',
        body: 'Late naps reduce sleep pressure, '
            'making it harder to fall asleep at night.',
      ),
      SleepTip(
        emoji: '☕',
        title: 'Caffeine nap trick',
        body: 'Drink coffee right before a 20-min nap. '
            'Caffeine kicks in as you wake — double boost.',
      ),
    ],

    SleepIntent.sleepDuration: [
      SleepTip(
        emoji: '📊',
        title: 'Sleep needs by age',
        body: 'Adults 18–64: 7–9 hrs · Adults 65+: 7–8 hrs · '
            'Teens 14–17: 8–10 hrs.',
      ),
      SleepTip(
        emoji: '⚡',
        title: 'Sleep debt is real',
        body: "You can't fully recover lost sleep. "
            'Chronic short sleep impairs cognition and immunity.',
      ),
    ],

    SleepIntent.wakeTime: [
      SleepTip(
        emoji: '☀️',
        title: 'Morning light first',
        body: '5–10 minutes of sunlight within an hour of waking '
            'resets your circadian clock for the day.',
      ),
      SleepTip(
        emoji: '⏰',
        title: 'Same time on weekends',
        body: 'Social jetlag from sleeping in disrupts your rhythm '
            'just like real jetlag.',
      ),
    ],

    SleepIntent.sleepTips: [
      SleepTip(
        emoji: '☕',
        title: 'Cut caffeine at 2 PM',
        body: 'Caffeine has a 5-hr half-life. '
            'A 4 PM coffee means half is still active at 9 PM.',
      ),
      SleepTip(
        emoji: '🌡️',
        title: 'Cool, dark, quiet',
        body: 'Ideal environment: 16–19°C, blackout curtains, '
            'white noise if needed.',
      ),
      SleepTip(
        emoji: '🏃',
        title: 'Exercise — but not late',
        body: 'Regular exercise improves sleep quality significantly. '
            'Avoid intense workouts within 2 hours of bedtime.',
      ),
      SleepTip(
        emoji: '🍷',
        title: 'Alcohol disrupts sleep',
        body: 'Alcohol helps you fall asleep but fragments sleep '
            'in the second half of the night.',
      ),
    ],

    SleepIntent.stressed: [
      SleepTip(
        emoji: '📝',
        title: 'Brain dump',
        body: 'Write every worry on paper before bed. '
            'Externalising thoughts reduces mental load.',
      ),
      SleepTip(
        emoji: '🌬️',
        title: 'Box breathing',
        body: 'Inhale 4, hold 4, exhale 4, hold 4. '
            'Repeat 4 cycles. Used by military to calm under pressure.',
      ),
    ],

    SleepIntent.tired: [
      SleepTip(
        emoji: '🕗',
        title: 'Prioritise consistency',
        body: 'Same bedtime every night matters more than total hours. '
            'Pick a time and protect it.',
      ),
      SleepTip(
        emoji: '💧',
        title: 'Check hydration',
        body: 'Dehydration causes fatigue. Drink water through the day, '
            'not just at night.',
      ),
    ],

    SleepIntent.frustrated: [
      SleepTip(
        emoji: '🧘',
        title: 'Stop trying to sleep',
        body: 'Paradoxical intention: try to stay awake with eyes closed. '
            'Removes performance anxiety around sleep.',
      ),
      SleepTip(
        emoji: '🛏️',
        title: 'Bed is only for sleep',
        body: 'No phones, TV, or work in bed. '
            'Train your brain that bed = sleep.',
      ),
    ],
  };

  // ── Routine steps ─────────────────────────────────────────────
  static const List<String> bedtimeRoutineSteps = [
    'T-30 min — Dim all lights in your room',
    'T-25 min — Put your phone in another room',
    'T-20 min — Light stretching or gentle yoga (5 min)',
    'T-15 min — Warm shower or wash your face',
    'T-10 min — Read a physical book or journal',
    'T-0       — Lights off, eyes closed',
  ];

  // ── Main intent response messages ─────────────────────────────
  static const Map<SleepIntent, List<String>> intentMessages = {
    SleepIntent.cantSleep: [
      "Struggling to sleep is really tough. Try the 20-minute rule: "
          "if you're awake for more than 20 minutes, get up, do something "
          "quiet in dim light, then return when you feel sleepy.",
      "When sleep won't come, the worst thing is lying there fighting it. "
          "Get up, reset, and come back to bed when your body is ready.",
      "Racing thoughts at night are common. The key is to stop trying to force sleep "
          "— your brain needs to feel safe, not pressured.",
    ],

    SleepIntent.bedtimeRoutine: [
      "A consistent wind-down routine trains your brain to expect sleep. "
          "Here's a simple 30-minute plan for tonight.",
      "Your pre-sleep routine is a signal to your nervous system. "
          "The same steps each night build a powerful sleep association.",
      "Routines work because they're predictable. Here's one to try tonight.",
    ],

    SleepIntent.screenTime: [
      "Blue light from screens tells your brain it's daytime, "
          "suppressing melatonin for up to 3 hours. "
          "Aim to put devices away 30–60 minutes before bed.",
      "Every scroll before bed delays your melatonin release. "
          "Even 30 minutes screen-free makes a measurable difference.",
      "Screens are the biggest modern enemy of sleep. "
          "The content also keeps your brain alert — not just the light.",
    ],

    SleepIntent.nap: [
      "Naps can be great or harmful depending on how you use them. "
          "The key is keeping them short and early.",
      "A well-timed nap is one of the most effective performance tools. "
          "A badly timed one can ruin your night.",
      "The science on naps is clear: 10–20 minutes before 3 PM is the sweet spot.",
    ],

    SleepIntent.sleepDuration: [
      "Most adults need 7–9 hours. Consistency matters more than total hours — "
          "the same bedtime every night resets your internal clock.",
      "Sleep needs vary by person, but the 7–9 hour range covers most adults. "
          "Quality matters as much as quantity.",
      "There's no real way to 'catch up' on sleep. "
          "Chronic short sleep compounds over time.",
    ],

    SleepIntent.wakeTime: [
      "A fixed wake time is the single most powerful sleep habit. "
          "Even on weekends, stay within 30 minutes of your usual time.",
      "Your wake time anchors your entire sleep cycle. "
          "Fixing it is more effective than fixing your bedtime.",
      "Consistency at wake time sets your circadian rhythm. "
          "Irregular wake times cause social jetlag.",
    ],

    SleepIntent.sleepTips: [
      "Here are the most evidence-based sleep habits. "
          "Pick just one to start — trying everything at once is overwhelming.",
      "Good sleep hygiene comes down to a few key behaviours. "
          "Here are the ones with the strongest evidence.",
      "Sleep science is clear on what works. "
          "Here are the top habits to build.",
    ],

    SleepIntent.stressed: [
      "Stress activates your fight-or-flight response — "
          "the opposite of what sleep needs. Let's work on calming your system.",
      "A stressed mind needs a physical reset before it can sleep. "
          "Here's what actually works.",
      "When your mind is overloaded, sleep feels impossible. "
          "Let's change that.",
    ],

    SleepIntent.tired: [
      "Being this tired and still not sleeping well is genuinely hard. "
          "Let's figure out what's getting in the way.",
      "Exhaustion without good sleep is a cycle we can break. "
          "Here's where to start.",
      "When you're drained, the basics matter most. Let's cover them.",
    ],

    SleepIntent.frustrated: [
      "Sleep frustration is real and valid. "
          "The key is removing the performance pressure around sleep.",
      "The more you try to force sleep, the harder it becomes. "
          "Let's take a different approach.",
      "I hear you — it's exhausting to be exhausted and still not sleep. "
          "Here's a fresh angle.",
    ],
  };
}
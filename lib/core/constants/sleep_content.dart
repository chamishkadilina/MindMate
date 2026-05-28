// lib/core/constants/sleep_content.dart
//
// Single source of truth for the Sleep Hygiene module.
// Contains:
//   • SleepIntent, EmotionalTone enums
//   • SleepTip, SleepResponse, ChatMessage, IntentLog data classes
//   • SleepCorpus — all NLP data + all spoken strings (all map)

import 'dart:math';

// ════════════════════════════════════════════════════════════════
// ENUMS
// ════════════════════════════════════════════════════════════════

enum SleepIntent {
  cantSleep,
  bedtimeRoutine,
  screenTime,
  nap,
  sleepDuration,
  wakeTime,
  sleepTips,
  stressed,
  tired,
  frustrated,
  greeting,
  gratitude,
  help,
  affirmation,
  negation,
  repeat,
  unknown,
}

enum EmotionalTone {
  neutral,
  stressed,
  tired,
  frustrated,
}

// ════════════════════════════════════════════════════════════════
// DATA CLASSES
// ════════════════════════════════════════════════════════════════

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

class SleepResponse {
  final SleepIntent intent;
  final String message;
  final String? voiceKey;
  final EmotionalTone tone;
  final List<SleepTip>? tips;
  final List<String>? routineSteps;
  final List<String>? suggestions;
  final double confidence;
  final bool isCrisis;
  final String? handoffRoute;

  const SleepResponse({
    required this.intent,
    required this.message,
    this.voiceKey,
    this.tone = EmotionalTone.neutral,
    this.tips,
    this.routineSteps,
    this.suggestions,
    this.confidence = 0.0,
    this.isCrisis = false,
    this.handoffRoute,
  });
}

class ChatMessage {
  final bool isUser;
  final String text;
  final SleepIntent? intent;
  final double? confidence;

  const ChatMessage({
    required this.isUser,
    required this.text,
    this.intent,
    this.confidence,
  });
}

class IntentLog {
  final String input;
  final SleepIntent intent;
  final double confidence;
  final EmotionalTone tone;

  const IntentLog({
    required this.input,
    required this.intent,
    required this.confidence,
    required this.tone,
  });

  @override
  String toString() =>
      '[SleepEngine] intent=${intent.name} conf=${confidence.toStringAsFixed(2)} '
          'tone=${tone.name} input="$input"';
}

// ════════════════════════════════════════════════════════════════
// CORPUS
// ════════════════════════════════════════════════════════════════

class SleepCorpus {
  SleepCorpus._();

  static final _rng = Random();

  /// Pick a random item from a list.
  static T pick<T>(List<T> list) => list[_rng.nextInt(list.length)];

  // ── Spoken strings (single source of truth for VoiceRegistry) ──

  static const Map<String, String> all = {

    // ── Entry / exit ──────────────────────────────────────────────────────────
    'sleep.entry':
    "I'm your sleep assistant. Ask me about bedtime routines, "
        "what to do if you can't sleep, screen time, naps, "
        "sleep duration, or general sleep tips.",
    'sleep.exit':
    'Sweet dreams! Come back any time you need sleep support.',
    'sleep.noInput':
    "I didn't hear anything. Please tap the mic and speak clearly.",
    'sleep.nothingToRepeat':
    "There's nothing to repeat yet. Ask me something first.",

    // ── Crisis / handoff ──────────────────────────────────────────────────────
    'sleep.crisis':
    'This sounds serious. Your safety comes first. '
        'I am connecting you to crisis support now.',
    'sleep.handoff.breathing':
    "That sounds like it would be better handled in the "
        "breathing module. Taking you there now.",
    'sleep.handoff.meditation':
    'A guided meditation sounds perfect. Taking you there now.',
    'sleep.handoff.psychoeducation':
    'Connecting you to the psychoeducation module now.',
    'sleep.handoff.default':
    "Let me take you to the right place.",

    // ── Follow-ups ────────────────────────────────────────────────────────────
    'sleep.cantSleep.followUp':
    'Would you like to try a breathing exercise? '
        'It can help calm your nervous system right now.',
    'sleep.stressed.followUp':
    "Since you're still stressed, I can walk you through "
        'box breathing or take you to the breathing module. '
        'Which would you prefer?',

    // ── Greeting ──────────────────────────────────────────────────────────────
    'sleep.greeting.0':
    "Hello! I'm your sleep assistant. You can ask me about bedtime routines, "
        "why you can't sleep, screen time habits, naps, or general sleep tips.",
    'sleep.greeting.1':
    "Hey there! Ready to help with your sleep. What's on your mind — "
        'trouble falling asleep, a bedtime routine, or something else?',
    'sleep.greeting.2':
    "Hi! I'm here to help you sleep better. Ask me anything about sleep hygiene, "
        "routines, naps, or what to do when your mind won't switch off.",

    // ── Gratitude ─────────────────────────────────────────────────────────────
    'sleep.gratitude.0': "You're welcome! Sleep well tonight.",
    'sleep.gratitude.1': 'Glad that helped. Feel free to ask anything else.',
    'sleep.gratitude.2': 'Of course! Come back anytime you need sleep support.',
    'sleep.gratitude.3': 'Happy to help. Wishing you a restful night.',

    // ── Help ──────────────────────────────────────────────────────────────────
    'sleep.help.0':
    "Here's what I can help with: trouble falling asleep, bedtime routines, "
        'screen time before bed, nap advice, how many hours of sleep you need, '
        'and fixing your wake time. Just ask naturally.',
    'sleep.help.1':
    "You can ask me things like: I can't sleep, give me a bedtime routine, "
        'is napping bad, how much sleep do I need, or help with screen time.',
    'sleep.help.2':
    'I specialise in sleep hygiene. Try asking about: insomnia, bedtime wind-down, '
        'blue light, power naps, sleep duration, or wake schedules.',

    // ── Affirmation ───────────────────────────────────────────────────────────
    'sleep.affirmation.0': "Great, let's continue.",
    'sleep.affirmation.1': 'Alright, here we go.',
    'sleep.affirmation.2': 'Sure thing.',
    'sleep.affirmation.3': "Okay, I'll go ahead.",

    // ── Negation ──────────────────────────────────────────────────────────────
    'sleep.negation.0': "No problem, let me know if there's anything else.",
    'sleep.negation.1': "Alright, I'm here whenever you need me.",
    'sleep.negation.2': "Got it. Just say the word if you'd like help with something.",

    // ── Unknown ───────────────────────────────────────────────────────────────
    'sleep.unknown.0':
    "I didn't quite catch that. Try asking about trouble sleeping, "
        'a bedtime routine, screen time, naps, or sleep duration.',
    'sleep.unknown.1':
    "Not sure I understood. You can say things like I can't sleep "
        "or give me sleep tips and I'll help.",
    'sleep.unknown.2':
    "Could you rephrase that? I'm best with questions about sleep — "
        'routines, insomnia, naps, wake times, and screen habits.',
    'sleep.unknown.3':
    "I didn't get that one. Ask me about bedtime routines, "
        "why you can't sleep, or how much sleep you need.",

    // ── Can't sleep ───────────────────────────────────────────────────────────
    'sleep.cantSleep.0':
    'Struggling to sleep is really tough. Try the 20-minute rule: '
        "if you're awake for more than 20 minutes, get up, do something "
        'quiet in dim light, then return when you feel sleepy.',
    'sleep.cantSleep.1':
    "When sleep won't come, the worst thing is lying there fighting it. "
        'Get up, reset, and come back to bed when your body is ready.',
    'sleep.cantSleep.2':
    'Racing thoughts at night are common. The key is to stop trying to force sleep '
        '— your brain needs to feel safe, not pressured.',

    // ── Bedtime routine ───────────────────────────────────────────────────────
    'sleep.bedtimeRoutine.0':
    "A consistent wind-down routine trains your brain to expect sleep. "
        "Here's a simple 30-minute plan for tonight.",
    'sleep.bedtimeRoutine.1':
    'Your pre-sleep routine is a signal to your nervous system. '
        'The same steps each night build a powerful sleep association.',
    'sleep.bedtimeRoutine.2':
    "Routines work because they're predictable. Here's one to try tonight.",

    // ── Screen time ───────────────────────────────────────────────────────────
    'sleep.screenTime.0':
    "Blue light from screens tells your brain it's daytime, "
        'suppressing melatonin for up to 3 hours. '
        'Aim to put devices away 30 to 60 minutes before bed.',
    'sleep.screenTime.1':
    'Every scroll before bed delays your melatonin release. '
        'Even 30 minutes screen-free makes a measurable difference.',
    'sleep.screenTime.2':
    'Screens are the biggest modern enemy of sleep. '
        "The content also keeps your brain alert — not just the light.",

    // ── Nap ───────────────────────────────────────────────────────────────────
    'sleep.nap.0':
    'Naps can be great or harmful depending on how you use them. '
        'The key is keeping them short and early.',
    'sleep.nap.1':
    'A well-timed nap is one of the most effective performance tools. '
        'A badly timed one can ruin your night.',
    'sleep.nap.2':
    'The science on naps is clear: 10 to 20 minutes before 3 PM is the sweet spot.',

    // ── Sleep duration ────────────────────────────────────────────────────────
    'sleep.sleepDuration.0':
    'Most adults need 7 to 9 hours. Consistency matters more than total hours — '
        'the same bedtime every night resets your internal clock.',
    'sleep.sleepDuration.1':
    'Sleep needs vary by person, but the 7 to 9 hour range covers most adults. '
        'Quality matters as much as quantity.',
    'sleep.sleepDuration.2':
    "There's no real way to catch up on sleep. "
        'Chronic short sleep compounds over time.',

    // ── Wake time ─────────────────────────────────────────────────────────────
    'sleep.wakeTime.0':
    'A fixed wake time is the single most powerful sleep habit. '
        'Even on weekends, stay within 30 minutes of your usual time.',
    'sleep.wakeTime.1':
    'Your wake time anchors your entire sleep cycle. '
        "Fixing it is more effective than fixing your bedtime.",
    'sleep.wakeTime.2':
    'Consistency at wake time sets your circadian rhythm. '
        'Irregular wake times cause social jetlag.',

    // ── Sleep tips ────────────────────────────────────────────────────────────
    'sleep.sleepTips.0':
    'Here are the most evidence-based sleep habits. '
        "Pick just one to start — trying everything at once is overwhelming.",
    'sleep.sleepTips.1':
    'Good sleep hygiene comes down to a few key behaviours. '
        "Here are the ones with the strongest evidence.",
    'sleep.sleepTips.2':
    'Sleep science is clear on what works. Here are the top habits to build.',

    // ── Stressed ──────────────────────────────────────────────────────────────
    'sleep.stressed.0':
    'Stress activates your fight-or-flight response — '
        "the opposite of what sleep needs. Let's work on calming your system.",
    'sleep.stressed.1':
    "A stressed mind needs a physical reset before it can sleep. "
        "Here's what actually works.",
    'sleep.stressed.2':
    "When your mind is overloaded, sleep feels impossible. Let's change that.",

    // ── Tired ─────────────────────────────────────────────────────────────────
    'sleep.tired.0':
    "Being this tired and still not sleeping well is genuinely hard. "
        "Let's figure out what's getting in the way.",
    'sleep.tired.1':
    "Exhaustion without good sleep is a cycle we can break. "
        "Here's where to start.",
    'sleep.tired.2':
    "When you're drained, the basics matter most. Let's cover them.",

    // ── Frustrated ────────────────────────────────────────────────────────────
    'sleep.frustrated.0':
    'Sleep frustration is real and valid. '
        'The key is removing the performance pressure around sleep.',
    'sleep.frustrated.1':
    "The more you try to force sleep, the harder it becomes. "
        "Let's take a different approach.",
    'sleep.frustrated.2':
    "I hear you — it's exhausting to be exhausted and still not sleep. "
        "Here's a fresh angle.",

    // ── Tone prefixes ─────────────────────────────────────────────────────────
    'sleep.tone.stressed.0':
    "It sounds like your mind is really busy right now. Let's slow things down.",
    'sleep.tone.stressed.1':
    "I hear you — stress and sleep really don't mix. Here's what can help.",
    'sleep.tone.stressed.2':
    "When stress keeps you awake, your body needs a reset. Let's work on that.",
    'sleep.tone.tired.0':
    "You sound really drained. Let's get you some proper rest.",
    'sleep.tone.tired.1':
    "Exhaustion is rough. Here's what will actually help tonight.",
    'sleep.tone.tired.2':
    "When you're this tired, the right approach matters. Let's cover them.",
    'sleep.tone.frustrated.0':
    "I understand the frustration — it's genuinely hard when sleep doesn't come.",
    'sleep.tone.frustrated.1':
    "That irritation is completely valid. Let's try a different angle.",
    'sleep.tone.frustrated.2':
    "Sleep struggles are exhausting in themselves. Here's something concrete to try.",
  };

  // ── Key-prefix map (intent → key prefix for picking variants) ────────────
  static const Map<SleepIntent, String> intentKeyPrefix = {
    SleepIntent.cantSleep:      'sleep.cantSleep',
    SleepIntent.bedtimeRoutine: 'sleep.bedtimeRoutine',
    SleepIntent.screenTime:     'sleep.screenTime',
    SleepIntent.nap:            'sleep.nap',
    SleepIntent.sleepDuration:  'sleep.sleepDuration',
    SleepIntent.wakeTime:       'sleep.wakeTime',
    SleepIntent.sleepTips:      'sleep.sleepTips',
    SleepIntent.stressed:       'sleep.stressed',
    SleepIntent.tired:          'sleep.tired',
    SleepIntent.frustrated:     'sleep.frustrated',
    SleepIntent.greeting:       'sleep.greeting',
    SleepIntent.gratitude:      'sleep.gratitude',
    SleepIntent.help:           'sleep.help',
    SleepIntent.affirmation:    'sleep.affirmation',
    SleepIntent.negation:       'sleep.negation',
    SleepIntent.unknown:        'sleep.unknown',
  };

  /// Variant counts per key prefix (how many .0/.1/.2 etc exist in [all]).
  static const Map<String, int> variantCounts = {
    'sleep.greeting':       3,
    'sleep.gratitude':      4,
    'sleep.help':           3,
    'sleep.affirmation':    4,
    'sleep.negation':       3,
    'sleep.unknown':        4,
    'sleep.cantSleep':      3,
    'sleep.bedtimeRoutine': 3,
    'sleep.screenTime':     3,
    'sleep.nap':            3,
    'sleep.sleepDuration':  3,
    'sleep.wakeTime':       3,
    'sleep.sleepTips':      3,
    'sleep.stressed':       3,
    'sleep.tired':          3,
    'sleep.frustrated':     3,
    'sleep.tone.stressed':  3,
    'sleep.tone.tired':     3,
    'sleep.tone.frustrated':3,
  };

  /// Pick a random variant key for the given prefix (e.g. 'sleep.cantSleep' → 'sleep.cantSleep.1').
  static String pickKey(String prefix) {
    final count = variantCounts[prefix] ?? 1;
    final index = _rng.nextInt(count);
    return '$prefix.$index';
  }

  /// Look up text by key from [all].
  static String textFor(String key) {
    assert(all.containsKey(key), '[SleepCorpus] Missing key: "$key"');
    return all[key]!;
  }

  // ── NLP data ──────────────────────────────────────────────────────────────

  static const List<String> directEntryKeywords = [
    'sleep', 'insomnia', 'bedtime', 'tired', 'rest',
  ];

  static const List<String> exitKeywords = [
    'exit', 'quit', 'go back', 'leave', 'close', 'done', 'bye', 'goodbye',
  ];

  static const List<String> crisisKeywords = [
    'suicide', 'kill myself', 'end my life', 'self harm', 'hurt myself',
    'don\'t want to live', 'no reason to live',
  ];

  static const Map<String, List<String>> handoffTriggers = {
    '/breathing': [
      'breathing exercise', 'breathe', 'breathing technique', 'deep breath',
    ],
    '/meditation': [
      'meditation', 'meditate', 'guided meditation', 'mindfulness',
    ],
    '/psychoeducation': [
      'learn more', 'explain', 'psychoeducation', 'why does sleep',
    ],
  };

  static const List<String> negationPrefixes = [
    'not', "don't", 'no', 'never', "can't", 'cannot', 'without',
    "doesn't", 'neither', 'nor',
  ];

  static const Map<String, String> synonymMap = {
    'cannot sleep':        'cant sleep',
    "can't sleep":         'cant sleep',
    'falling asleep':      'cant sleep',
    'fall asleep':         'cant sleep',
    'trouble sleeping':    'cant sleep',
    'insomnia':            'cant sleep',
    'wide awake':          'cant sleep',
    'lying awake':         'cant sleep',
    'before bed':          'bedtime',
    'wind down':           'bedtime routine',
    'wind-down':           'bedtime routine',
    'pre-sleep':           'bedtime routine',
    'night routine':       'bedtime routine',
    'phone before bed':    'screen time',
    'blue light':          'screen time',
    'scrolling':           'screen time',
    'social media':        'screen time',
    'power nap':           'nap',
    'daytime sleep':       'nap',
    'afternoon nap':       'nap',
    'how many hours':      'sleep duration',
    'how long should':     'sleep duration',
    'hours of sleep':      'sleep duration',
    'wake up time':        'wake time',
    'alarm time':          'wake time',
    'morning routine':     'wake time',
    'sleep advice':        'sleep tips',
    'sleep hygiene':       'sleep tips',
    'better sleep':        'sleep tips',
    'improve sleep':       'sleep tips',
    'anxious':             'stressed',
    'anxiety':             'stressed',
    'overthinking':        'stressed',
    'racing thoughts':     'stressed',
    'mind won\'t stop':    'stressed',
    'exhausted':           'tired',
    'drained':             'tired',
    'fatigue':             'tired',
    'wiped out':           'tired',
    'frustrated':          'frustrated',
    'annoyed':             'frustrated',
    'angry':               'frustrated',
    'fed up':              'frustrated',
    'thanks':              'thank you',
    'thank you':           'gratitude',
    'cheers':              'gratitude',
    'appreciate':          'gratitude',
    'yes':                 'affirmation',
    'yeah':                'affirmation',
    'sure':                'affirmation',
    'ok':                  'affirmation',
    'okay':                'affirmation',
    'yep':                 'affirmation',
    'no':                  'negation',
    'nope':                'negation',
    'nah':                 'negation',
    'not really':          'negation',
    'repeat':              'repeat',
    'say again':           'repeat',
    'what did you say':    'repeat',
  };

  static const Map<SleepIntent, List<String>> intentKeywords = {
    SleepIntent.cantSleep: [
      'cant sleep', 'sleep', 'awake', 'fall asleep', 'asleep',
      'lying in bed', '20 minute', 'wired', 'alert at night',
    ],
    SleepIntent.bedtimeRoutine: [
      'bedtime', 'routine', 'wind down', 'before bed', 'pre-sleep',
      'night routine', 'schedule', 'prepare for sleep',
    ],
    SleepIntent.screenTime: [
      'screen time', 'phone', 'blue light', 'scrolling', 'device',
      'tv before bed', 'laptop', 'tablet', 'social media',
    ],
    SleepIntent.nap: [
      'nap', 'napping', 'daytime sleep', 'power nap', 'afternoon sleep',
      'siesta', 'sleep during day',
    ],
    SleepIntent.sleepDuration: [
      'sleep duration', 'how many hours', 'enough sleep', 'hours of sleep',
      'how long', 'sleep debt', 'oversleeping', 'too much sleep',
    ],
    SleepIntent.wakeTime: [
      'wake time', 'wake up', 'alarm', 'morning', 'get up',
      'consistent wake', 'same time', 'circadian',
    ],
    SleepIntent.sleepTips: [
      'tips', 'advice', 'help', 'improve', 'sleep hygiene',
      'better sleep', 'suggestions', 'habits',
    ],
    SleepIntent.stressed: [
      'stressed', 'stress', 'anxious', 'anxiety', 'overthinking',
      'racing thoughts', 'worried', 'mind won\'t stop', 'cant relax',
    ],
    SleepIntent.tired: [
      'tired', 'exhausted', 'drained', 'fatigue', 'wiped',
      'no energy', 'sleepy', 'drowsy',
    ],
    SleepIntent.frustrated: [
      'frustrated', 'annoyed', 'angry', 'fed up', 'nothing works',
      'tried everything', 'gives up', 'useless',
    ],
    SleepIntent.greeting: [
      'hello', 'hi', 'hey', 'good morning', 'good evening', 'howdy',
    ],
    SleepIntent.gratitude: [
      'gratitude', 'thank', 'thanks', 'appreciate', 'helpful',
    ],
    SleepIntent.help: [
      'what can you do', 'what do you know', 'help me', 'how do you work',
      'what topics', 'what can you help',
    ],
    SleepIntent.affirmation: [
      'affirmation', 'yes', 'yeah', 'sure', 'ok', 'okay', 'yep',
      'go ahead', 'please do', 'sounds good',
    ],
    SleepIntent.negation: [
      'negation', 'no', 'nope', 'nah', 'not really', 'no thanks',
      'skip', 'never mind',
    ],
    SleepIntent.repeat: [
      'repeat', 'say again', 'what did you say', 'pardon', 'come again',
    ],
  };

  static const Map<SleepIntent, List<String>> bigrams = {
    SleepIntent.cantSleep: [
      'cant sleep', 'cant fall', 'stay awake', 'wide awake', 'lying awake',
    ],
    SleepIntent.bedtimeRoutine: [
      'bedtime routine', 'wind down', 'night routine', 'before sleep',
    ],
    SleepIntent.screenTime: [
      'screen time', 'blue light', 'phone before', 'no screens',
    ],
    SleepIntent.nap: [
      'power nap', 'short nap', 'daytime nap', 'afternoon nap',
    ],
    SleepIntent.sleepDuration: [
      'sleep duration', 'hours sleep', 'enough sleep', 'sleep debt',
    ],
    SleepIntent.wakeTime: [
      'wake time', 'wake up', 'same time', 'consistent wake',
    ],
    SleepIntent.sleepTips: [
      'sleep tips', 'sleep advice', 'sleep hygiene', 'better sleep',
    ],
    SleepIntent.stressed: [
      'racing thoughts', 'cant relax', 'mind racing', 'feel anxious',
    ],
    SleepIntent.tired: [
      'so tired', 'really tired', 'always tired', 'feel exhausted',
    ],
    SleepIntent.frustrated: [
      'nothing works', 'so frustrated', 'tried everything', 'fed up',
    ],
  };

  static const Map<SleepIntent, List<String>> trigrams = {
    SleepIntent.cantSleep: [
      'cant fall asleep', 'lying awake all', 'mind wont stop',
    ],
    SleepIntent.bedtimeRoutine: [
      'bedtime wind down routine', 'routine before bed',
    ],
    SleepIntent.screenTime: [
      'phone before bed', 'screen time before bed',
    ],
    SleepIntent.sleepTips: [
      'tips for better sleep', 'help me sleep better',
    ],
    SleepIntent.stressed: [
      'too stressed to sleep', 'anxiety keeping me awake',
    ],
  };

  static const Map<EmotionalTone, List<String>> toneKeywords = {
    EmotionalTone.stressed: [
      'stressed', 'anxious', 'anxiety', 'overwhelmed', 'worried',
      'racing thoughts', 'overthinking', 'panic',
    ],
    EmotionalTone.tired: [
      'tired', 'exhausted', 'drained', 'fatigue', 'sleepy',
      'wiped out', 'no energy', 'drowsy',
    ],
    EmotionalTone.frustrated: [
      'frustrated', 'annoyed', 'angry', 'fed up', 'nothing works',
      'tried everything', 'useless',
    ],
  };

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

  // ── Response variant lists (used by engine's _buildResponse) ─────────────

  static final Map<SleepIntent, List<String>> intentMessages = {
    SleepIntent.cantSleep: [
      all['sleep.cantSleep.0']!,
      all['sleep.cantSleep.1']!,
      all['sleep.cantSleep.2']!,
    ],
    SleepIntent.bedtimeRoutine: [
      all['sleep.bedtimeRoutine.0']!,
      all['sleep.bedtimeRoutine.1']!,
      all['sleep.bedtimeRoutine.2']!,
    ],
    SleepIntent.screenTime: [
      all['sleep.screenTime.0']!,
      all['sleep.screenTime.1']!,
      all['sleep.screenTime.2']!,
    ],
    SleepIntent.nap: [
      all['sleep.nap.0']!,
      all['sleep.nap.1']!,
      all['sleep.nap.2']!,
    ],
    SleepIntent.sleepDuration: [
      all['sleep.sleepDuration.0']!,
      all['sleep.sleepDuration.1']!,
      all['sleep.sleepDuration.2']!,
    ],
    SleepIntent.wakeTime: [
      all['sleep.wakeTime.0']!,
      all['sleep.wakeTime.1']!,
      all['sleep.wakeTime.2']!,
    ],
    SleepIntent.sleepTips: [
      all['sleep.sleepTips.0']!,
      all['sleep.sleepTips.1']!,
      all['sleep.sleepTips.2']!,
    ],
    SleepIntent.stressed: [
      all['sleep.stressed.0']!,
      all['sleep.stressed.1']!,
      all['sleep.stressed.2']!,
    ],
    SleepIntent.tired: [
      all['sleep.tired.0']!,
      all['sleep.tired.1']!,
      all['sleep.tired.2']!,
    ],
    SleepIntent.frustrated: [
      all['sleep.frustrated.0']!,
      all['sleep.frustrated.1']!,
      all['sleep.frustrated.2']!,
    ],
  };

  static final Map<SleepIntent, List<String>> responseVariants = {
    SleepIntent.greeting: [
      all['sleep.greeting.0']!,
      all['sleep.greeting.1']!,
      all['sleep.greeting.2']!,
    ],
    SleepIntent.gratitude: [
      all['sleep.gratitude.0']!,
      all['sleep.gratitude.1']!,
      all['sleep.gratitude.2']!,
      all['sleep.gratitude.3']!,
    ],
    SleepIntent.help: [
      all['sleep.help.0']!,
      all['sleep.help.1']!,
      all['sleep.help.2']!,
    ],
    SleepIntent.affirmation: [
      all['sleep.affirmation.0']!,
      all['sleep.affirmation.1']!,
      all['sleep.affirmation.2']!,
      all['sleep.affirmation.3']!,
    ],
    SleepIntent.negation: [
      all['sleep.negation.0']!,
      all['sleep.negation.1']!,
      all['sleep.negation.2']!,
    ],
    SleepIntent.unknown: [
      all['sleep.unknown.0']!,
      all['sleep.unknown.1']!,
      all['sleep.unknown.2']!,
      all['sleep.unknown.3']!,
    ],
  };

  // ── Tips ──────────────────────────────────────────────────────────────────

  static const Map<SleepIntent, List<SleepTip>> intentTips = {
    SleepIntent.cantSleep: [
      SleepTip(
        emoji: '🌬️',
        title: '4-7-8 Breathing',
        body: 'Inhale 4s, hold 7s, exhale 8s. Repeat 3 times. '
            'Activates your parasympathetic nervous system immediately.',
      ),
      SleepTip(
        emoji: '🛏️',
        title: '20-Minute Rule',
        body: "Lying awake trains your brain to associate bed with wakefulness. "
            'Get up after 20 minutes and do something quiet.',
      ),
      SleepTip(
        emoji: '❄️',
        title: 'Cool Your Room',
        body: 'Core body temperature must drop to trigger sleep. '
            'Aim for 16–19°C.',
      ),
    ],
    SleepIntent.screenTime: [
      SleepTip(
        emoji: '🌙',
        title: 'Enable Night Mode',
        body: 'Use Night Shift (iPhone) or Night Light (Android) '
            'if you must use your phone.',
      ),
      SleepTip(
        emoji: '📖',
        title: 'Replace With Reading',
        body: 'A physical book relaxes your eyes and slows your thoughts — '
            'the best screen substitute.',
      ),
      SleepTip(
        emoji: '🔌',
        title: 'Charge Outside the Bedroom',
        body: "If your phone is on your nightstand, you will check it. "
            'Charge it in another room.',
      ),
    ],
    SleepIntent.nap: [
      SleepTip(
        emoji: '⏱️',
        title: 'Keep It 10–20 Minutes',
        body: "Short naps boost alertness without deep sleep, "
            'so you wake refreshed, not groggy.',
      ),
      SleepTip(
        emoji: '🕒',
        title: 'Nap Before 3 PM',
        body: 'Late naps reduce sleep pressure, '
            'making it harder to fall asleep at night.',
      ),
      SleepTip(
        emoji: '☕',
        title: 'Caffeine Nap Trick',
        body: 'Drink coffee right before a 20-minute nap. '
            'Caffeine kicks in as you wake — double boost.',
      ),
    ],
    SleepIntent.sleepDuration: [
      SleepTip(
        emoji: '🧬',
        title: 'Sleep Needs by Age',
        body: 'Adults 18–64: 7–9 hrs. '
            'Adults 65+: 7–8 hrs. Teens 14–17: 8–10 hrs.',
      ),
      SleepTip(
        emoji: '💳',
        title: 'Sleep Debt is Real',
        body: "You can't fully recover lost sleep. "
            'Chronic short sleep impairs cognition and immunity.',
      ),
    ],
    SleepIntent.wakeTime: [
      SleepTip(
        emoji: '☀️',
        title: 'Morning Light First',
        body: '5–10 minutes of sunlight within an hour of waking '
            'resets your circadian clock for the day.',
      ),
      SleepTip(
        emoji: '📅',
        title: 'Same Time on Weekends',
        body: 'Social jetlag from sleeping in disrupts your rhythm '
            'just like real jetlag.',
      ),
    ],
    SleepIntent.sleepTips: [
      SleepTip(
        emoji: '☕',
        title: 'Cut Caffeine at 2 PM',
        body: "Caffeine has a 5-hour half-life. "
            "A 4 PM coffee means half is still active at 9 PM.",
      ),
      SleepTip(
        emoji: '🌡️',
        title: 'Cool, Dark, Quiet',
        body: 'Ideal: 16–19°C, blackout curtains, white noise if needed.',
      ),
      SleepTip(
        emoji: '🏃',
        title: 'Exercise, But Not Late',
        body: 'Regular exercise improves sleep quality significantly. '
            'Avoid intense workouts within 2 hours of bedtime.',
      ),
      SleepTip(
        emoji: '🍷',
        title: 'Alcohol Disrupts Sleep',
        body: 'Alcohol helps you fall asleep but fragments sleep '
            'in the second half of the night.',
      ),
    ],
    SleepIntent.stressed: [
      SleepTip(
        emoji: '📝',
        title: 'Brain Dump',
        body: 'Write every worry on paper before bed. '
            'Externalising thoughts reduces mental load.',
      ),
      SleepTip(
        emoji: '📦',
        title: 'Box Breathing',
        body: 'Inhale 4, hold 4, exhale 4, hold 4. '
            'Repeat 4 cycles. Used by the military to calm under pressure.',
      ),
    ],
    SleepIntent.tired: [
      SleepTip(
        emoji: '🔁',
        title: 'Prioritise Consistency',
        body: 'Same bedtime every night matters more than total hours. '
            'Pick a time and protect it.',
      ),
      SleepTip(
        emoji: '💧',
        title: 'Check Hydration',
        body: 'Dehydration causes fatigue. '
            'Drink water through the day, not just at night.',
      ),
    ],
    SleepIntent.frustrated: [
      SleepTip(
        emoji: '🔄',
        title: 'Paradoxical Intention',
        body: 'Try to stay awake with eyes closed. '
            'This removes performance anxiety around sleep.',
      ),
      SleepTip(
        emoji: '🛏️',
        title: 'Bed is Only for Sleep',
        body: 'No phones, TV, or work in bed. '
            'Train your brain that bed equals sleep.',
      ),
    ],
  };

  // ── Bedtime routine steps (display only) ─────────────────────────────────

  static const List<String> bedtimeRoutineSteps = [
    '30 min before — dim all lights',
    '25 min before — put your phone in another room',
    '20 min before — light stretching for 5 minutes',
    '15 min before — warm shower or wash your face',
    '10 min before — read a physical book or journal',
    'Lights off, eyes closed',
  ];

  // ── Follow-up suggestions ─────────────────────────────────────────────────

  static const Map<SleepIntent, List<String>> followUpSuggestions = {
    SleepIntent.cantSleep: [
      "Try a breathing exercise",
      "Give me more tips",
      "What about screen time?",
    ],
    SleepIntent.bedtimeRoutine: [
      "What about screen time?",
      "How many hours do I need?",
      "Tips for falling asleep faster",
    ],
    SleepIntent.screenTime: [
      "Give me a bedtime routine",
      "What else can I do?",
      "Tell me about sleep duration",
    ],
    SleepIntent.nap: [
      "How long should I sleep at night?",
      "Tell me about wake time",
      "More sleep tips",
    ],
    SleepIntent.sleepDuration: [
      "What time should I wake up?",
      "Help with bedtime routine",
      "I can't fall asleep",
    ],
    SleepIntent.wakeTime: [
      "Help with my bedtime routine",
      "General sleep tips",
      "Why can't I fall asleep?",
    ],
    SleepIntent.sleepTips: [
      "I can't fall asleep",
      "Give me a bedtime routine",
      "Help with screen time",
    ],
    SleepIntent.stressed: [
      "Try breathing exercises",
      "Give me sleep tips",
      "Help me wind down",
    ],
    SleepIntent.tired: [
      "Give me a bedtime routine",
      "How many hours do I need?",
      "I can't fall asleep",
    ],
    SleepIntent.frustrated: [
      "Try something different",
      "Tell me about sleep hygiene",
      "Breathing exercises",
    ],
  };
}
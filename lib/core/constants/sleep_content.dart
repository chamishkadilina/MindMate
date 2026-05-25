// sleep_content.dart
// All types, keyword corpus, and response content for the sleep module.
// Pure Dart — no Flutter imports.

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
  final List<String>? suggestions;   // follow-up chips
  final String? handoffRoute;
  final bool isCrisis;
  final double confidence;           // 0.0 – 1.0

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

  // ── Helper ───────────────────────────────────────────────────
  static String pick(List<String> variants) =>
      variants[_random.nextInt(variants.length)];

  // ── Crisis ───────────────────────────────────────────────────
  static const List<String> crisisKeywords = [
    "don't want to wake up", "dont want to wake up", "never wake up",
    "sleep forever", "wish i wouldn't wake", "wish i wouldnt wake",
    "not wake up", "sleep and not wake", "go to sleep forever",
  ];

  // ── Handoff triggers ─────────────────────────────────────────
  static const Map<String, List<String>> handoffTriggers = {
    '/breathing': [
      'i feel anxious', "i'm anxious", 'im anxious', 'help me relax',
      'calm me down', 'i am panicking', 'having a panic', 'panic attack',
      'anxious at night', 'anxiety before bed',
    ],
    '/meditation': [
      'meditate before bed', 'guided meditation',
      'meditation for sleep', 'open meditation',
    ],
    '/psychoeducation': [
      'i feel depressed', "i'm depressed", 'im depressed',
      'depression and sleep',
    ],
  };

  // ── Direct entry ─────────────────────────────────────────────
  static const List<String> directEntryKeywords = [
    'sleep module', 'sleep hygiene', 'sleep tips', 'bedtime help',
    'open sleep', 'go to sleep module', 'help me sleep', 'sleep support',
    'sleep health', 'sleep problems', 'sleeping problems', 'sleep issues',
    'sleeping issues', 'talk about sleep', 'sleep advice',
  ];

  // ── Exit ─────────────────────────────────────────────────────
  static const List<String> exitKeywords = [
    'exit', 'back', 'bye', 'goodbye', 'stop', 'quit',
    'go back', 'home', 'leave', 'done', 'enough', 'close',
  ];

  // ── Intent keyword map ────────────────────────────────────────
  // Each keyword list is used for SCORING — more hits = higher confidence.
  // Order in the map does not affect priority (scoring handles that).
  static const Map<SleepIntent, List<String>> intentKeywords = {

    SleepIntent.greeting: [
      'hi', 'hello', 'hey', 'good morning', 'good evening',
      'good night', 'howdy', 'what\'s up', 'whats up', 'greetings',
      'sup', 'hiya',
    ],

    SleepIntent.gratitude: [
      'thanks', 'thank you', 'thank you so much', 'cheers',
      'appreciate it', 'appreciate that', 'helpful', 'that helped',
      'that was helpful', 'great help',
    ],

    SleepIntent.repeat: [
      'repeat', 'repeat that', 'say again', 'say that again',
      'what did you say', 'pardon', 'come again', 'once more',
      'can you repeat', 'didn\'t catch that', 'didnt catch that',
      'missed that', 'one more time',
    ],

    SleepIntent.help: [
      'what can you do', 'help', 'how does this work', 'what do you do',
      'what can i ask', 'what should i say', 'options', 'commands',
      'features', 'capabilities', 'guide me', 'i don\'t know what to say',
      'i dont know what to say', 'show me what you can do',
    ],

    SleepIntent.affirmation: [
      'yes', 'yeah', 'yep', 'yup', 'sure', 'okay', 'ok',
      'alright', 'go ahead', 'please do', 'sounds good', 'do it',
      'tell me more', 'continue', 'go on', 'i would like that',
      'that sounds good', 'absolutely', 'definitely',
    ],

    SleepIntent.negation: [
      'no', 'nope', 'nah', 'not really', 'no thanks', 'don\'t',
      'dont', 'never mind', 'nevermind', 'skip', 'not interested',
      'forget it', 'not now', 'maybe later',
    ],

    SleepIntent.cantSleep: [
      "can't sleep", "cant sleep", "cannot sleep", "trouble sleeping",
      "hard to sleep", "difficulty sleeping", "lying awake", "awake all night",
      "been awake", "no sleep", "couldn't sleep", "couldnt sleep",
      "couldn't fall asleep", "couldnt fall asleep", "sleepless",
      "sleepless night", "insomnia", "tossing and turning",
      "wake up at night", "waking up at night", "keep waking",
      "waking up middle", "middle of the night", "can't fall asleep",
      "cant fall asleep", "unable to sleep", "not able to sleep",
      "restless at night", "sleep won't come", "mind won't stop",
      "mind wont stop", "racing thoughts at night", "wide awake",
      "staring at ceiling", "lying in bed awake", "can't drift off",
      "sleep deprivation", "no rest", "not rested", "didnt sleep",
      "didn't sleep", "eyes won't close", "hours in bed",
    ],

    SleepIntent.screenTime: [
      "phone before bed", "screen before bed", "blue light",
      "watching tv before bed", "scrolling before bed",
      "social media at night", "phone at night", "laptop before bed",
      "tablet before bed", "screen time at night", "too much screen",
      "phone in bed", "scrolling in bed", "device before sleep",
      "blue light glasses", "screen affecting sleep", "tv in bedroom",
      "computer at night", "doom scrolling", "doomscrolling",
      "tiktok before bed", "instagram before bed", "youtube before bed",
    ],

    SleepIntent.bedtimeRoutine: [
      "bedtime routine", "bed time routine", "before bed routine",
      "night routine", "sleep routine", "going to bed",
      "get ready for sleep", "prepare for sleep", "wind down",
      "winding down", "night time routine", "pre-sleep routine",
      "what to do before bed", "calm down before sleep",
      "relax before bed", "routine for sleep", "habits before bed",
      "bedtime ritual", "evening routine", "nighttime habit",
      "sleep preparation", "how to prepare for bed",
    ],

    SleepIntent.nap: [
      "nap", "napping", "afternoon sleep", "daytime sleep", "power nap",
      "short sleep", "sleep during day", "midday nap", "lunchtime sleep",
      "should i nap", "is napping good", "nap too long", "long nap",
      "cant stop napping", "sleep in afternoon", "daytime napping",
      "siesta", "20 minute nap", "quick nap", "nap affecting sleep",
    ],

    SleepIntent.sleepDuration: [
      "how many hours", "hours of sleep", "8 hours", "7 hours",
      "6 hours", "5 hours", "enough sleep", "how long should i sleep",
      "how much sleep", "too little sleep", "not enough sleep",
      "optimal sleep", "recommended sleep", "sleep needs",
      "sleep requirements", "sleep duration", "sleep amount",
      "sleeping too little", "sleeping too much", "oversleeping",
      "sleep debt", "catching up on sleep", "catch up on sleep",
    ],

    SleepIntent.wakeTime: [
      "wake up time", "wake time", "alarm", "morning routine",
      "consistent wake", "same wake time", "fix wake time",
      "waking up too early", "can't wake up", "cant wake up",
      "hard to wake", "sleeping through alarm", "circadian",
      "circadian rhythm", "body clock", "internal clock",
      "sleep schedule", "irregular sleep", "sleep pattern",
      "consistent bedtime", "fix sleep schedule", "reset sleep",
      "social jetlag", "weekend sleep",
    ],

    SleepIntent.sleepTips: [
      "sleep tips", "sleep advice", "how to sleep", "sleep better",
      "improve sleep", "good sleep", "sleep hygiene tips", "sleep habits",
      "sleep quality", "deep sleep", "better rest", "poor sleep",
      "fix my sleep", "sleeping badly", "bad sleep", "not sleeping well",
      "sleep improvement", "healthy sleep", "what helps sleep",
      "tips for sleeping", "sleep hacks", "sleep suggestions",
      "general sleep advice", "sleep environment", "bedroom for sleep",
      "caffeine and sleep", "alcohol and sleep", "exercise and sleep",
      "melatonin", "cool room", "dark room", "white noise",
    ],

    // ── Emotional tones ──────────────────────────────────────────
    SleepIntent.stressed: [
      "stressed", "stress", "so stressed", "overwhelmed", "can't relax",
      "cant relax", "tense", "wound up", "worked up", "on edge",
      "mind is racing", "too much on my mind", "worried", "worrying",
      "anxious", "anxiety", "nervous", "restless",
    ],

    SleepIntent.tired: [
      "tired", "exhausted", "drained", "worn out", "fatigued",
      "sleepy", "drowsy", "so tired", "really tired", "dead tired",
      "running on empty", "no energy", "low energy", "burned out",
      "burnout", "can't keep eyes open", "cant keep eyes open",
    ],

    SleepIntent.frustrated: [
      "frustrated", "annoyed", "irritated", "fed up", "angry",
      "this isn't working", "this isnt working", "nothing helps",
      "nothing works", "i give up", "sick of this", "hate this",
      "why can't i sleep", "why cant i sleep", "so annoying",
    ],
  };

  // ── Emotional tone keyword map (for fast tone detection) ──────
  static const Map<EmotionalTone, List<String>> toneKeywords = {
    EmotionalTone.stressed: [
      "stressed", "overwhelmed", "anxious", "worried", "worrying",
      "on edge", "tense", "wound up", "mind is racing",
    ],
    EmotionalTone.tired: [
      "tired", "exhausted", "drained", "worn out", "fatigued",
      "sleepy", "drowsy", "burned out", "no energy",
    ],
    EmotionalTone.frustrated: [
      "frustrated", "annoyed", "fed up", "nothing works",
      "nothing helps", "i give up", "sick of this",
    ],
  };

  // ════════════════════════════════════════════════════════════════
  // 3. RESPONSE VARIANTS
  // All responses are lists — engine picks randomly.
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
      "When you're this tired, the right approach matters. Let's sort it out. ",
    ],
    EmotionalTone.frustrated: [
      "I understand the frustration — it's genuinely hard when sleep doesn't come. ",
      "That irritation is completely valid. Let's try a different angle. ",
      "Sleep struggles are exhausting in themselves. Here's something concrete to try. ",
    ],
  };

  // ── Contextual follow-up suggestions ─────────────────────────
  // After an intent is handled, suggest related follow-ups.
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
        emoji: '🌬️', title: '4-7-8 breathing',
        body: 'Inhale 4 sec, hold 7, exhale 8. Repeat 3 times. '
            'Activates your parasympathetic nervous system immediately.',
      ),
      SleepTip(
        emoji: '🧠', title: '20-minute rule',
        body: 'Lying awake trains your brain to associate bed with wakefulness. '
            'Get up after 20 minutes and do something quiet.',
      ),
      SleepTip(
        emoji: '❄️', title: 'Cool your room',
        body: 'Core body temp must drop to trigger sleep. '
            'Aim for 16–19°C (60–67°F).',
      ),
    ],

    SleepIntent.screenTime: [
      SleepTip(
        emoji: '🔅', title: 'Enable night mode',
        body: 'Use Night Shift (iOS) or Night Light (Android) '
            'if you must use your phone.',
      ),
      SleepTip(
        emoji: '📚', title: 'Replace with reading',
        body: 'A physical book relaxes your eyes and slows your thoughts — '
            'the best screen substitute.',
      ),
      SleepTip(
        emoji: '🔌', title: 'Charge outside the bedroom',
        body: 'If your phone is on your nightstand, you will check it. '
            'Charge it in another room.',
      ),
    ],

    SleepIntent.nap: [
      SleepTip(
        emoji: '⏱️', title: 'Keep it 10–20 minutes',
        body: 'Short naps boost alertness without deep sleep, '
            'so you wake refreshed, not groggy.',
      ),
      SleepTip(
        emoji: '🕒', title: 'Nap before 3 PM',
        body: 'Late naps reduce sleep pressure, '
            'making it harder to fall asleep at night.',
      ),
      SleepTip(
        emoji: '☕', title: 'Caffeine nap trick',
        body: 'Drink coffee right before a 20-min nap. '
            'Caffeine kicks in as you wake — double boost.',
      ),
    ],

    SleepIntent.sleepDuration: [
      SleepTip(
        emoji: '📊', title: 'Sleep needs by age',
        body: 'Adults 18–64: 7–9 hrs · Adults 65+: 7–8 hrs · '
            'Teens 14–17: 8–10 hrs.',
      ),
      SleepTip(
        emoji: '⚡', title: 'Sleep debt is real',
        body: "You can't fully recover lost sleep. "
            'Chronic short sleep impairs cognition and immunity.',
      ),
    ],

    SleepIntent.wakeTime: [
      SleepTip(
        emoji: '☀️', title: 'Morning light first',
        body: '5–10 minutes of sunlight within an hour of waking '
            'resets your circadian clock for the day.',
      ),
      SleepTip(
        emoji: '⏰', title: 'Same time on weekends',
        body: 'Social jetlag from sleeping in disrupts your rhythm '
            'just like real jetlag.',
      ),
    ],

    SleepIntent.sleepTips: [
      SleepTip(
        emoji: '☕', title: 'Cut caffeine at 2 PM',
        body: 'Caffeine has a 5-hr half-life. '
            'A 4 PM coffee means half is still active at 9 PM.',
      ),
      SleepTip(
        emoji: '🌡️', title: 'Cool, dark, quiet',
        body: 'Ideal environment: 16–19°C, blackout curtains, '
            'white noise if needed.',
      ),
      SleepTip(
        emoji: '🏃', title: 'Exercise — but not late',
        body: 'Regular exercise improves sleep quality significantly. '
            'Avoid intense workouts within 2 hours of bedtime.',
      ),
      SleepTip(
        emoji: '🍷', title: 'Alcohol disrupts sleep',
        body: 'Alcohol helps you fall asleep but fragments sleep '
            'in the second half of the night.',
      ),
    ],

    SleepIntent.stressed: [
      SleepTip(
        emoji: '📝', title: 'Brain dump',
        body: 'Write every worry on paper before bed. '
            'Externalising thoughts reduces mental load.',
      ),
      SleepTip(
        emoji: '🌬️', title: 'Box breathing',
        body: 'Inhale 4, hold 4, exhale 4, hold 4. '
            'Repeat 4 cycles. Used by military to calm under pressure.',
      ),
    ],

    SleepIntent.tired: [
      SleepTip(
        emoji: '🕗', title: 'Prioritise consistency',
        body: 'Same bedtime every night matters more than total hours. '
            'Pick a time and protect it.',
      ),
      SleepTip(
        emoji: '💧', title: 'Check hydration',
        body: 'Dehydration causes fatigue. Drink water through the day, '
            'not just at night.',
      ),
    ],

    SleepIntent.frustrated: [
      SleepTip(
        emoji: '🧘', title: 'Stop trying to sleep',
        body: 'Paradoxical intention: try to stay awake with eyes closed. '
            'Removes performance anxiety around sleep.',
      ),
      SleepTip(
        emoji: '🛏️', title: 'Bed is only for sleep',
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
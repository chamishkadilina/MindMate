// sleep_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mindmate/features/emergency_support/screens/emergency_support_page.dart';
import 'package:mindmate/features/breathing_exercises/screens/breathing_exercises_page.dart';
import 'package:mindmate/features/mindfulness/screens/mindfulness_page.dart';
import 'package:mindmate/features/mood_tracking/screens/mood_tracking_page.dart';
import '../../../core/services/speech_to_text_service.dart';
import '../../../core/services/tts_service.dart';
import '../models/sleep_record.dart';
import '../repository/sleep_repository.dart';
import '../screens/pmr_screen.dart';
import '../screens/sleep_graph.dart';
import '../screens/wind_down_screen.dart';

/// SleepController holds all business logic, state, and VUI handling
/// for the Sleep Hygiene page. It is a [ChangeNotifier] so the UI can rebuild
/// reactively on state changes.
class SleepController extends ChangeNotifier {
  SleepController({required this.vsync});

  final TickerProvider vsync;

  // ── External services ──────────────────────────────────────────────────────
  final TtsService ttsService = TtsService();
  final SpeechToTextService sttService = SpeechToTextService();

  // ── Exposed state ──────────────────────────────────────────────────────────
  bool isListening  = false;
  bool sttAvailable = false;
  bool isProcessing = false;
  String recognizedText = '';
  String statusLabel    = 'Tap the mic and speak';

  /// VUI dialogue state machine.
  /// Values: 'idle', 'awaiting_nav_confirmation'
  String currentState    = 'idle';
  String pendingNavRoute = '';

  // Tracks consecutive "didn't understand" fallback responses.
  // Resets to 0 whenever any recognizable intent is matched.
  int _consecutiveFallbacks = 0;

  /// Set when a response ends with "want to know about A, B, or C?".
  /// Holds a tag identifying which menu was offered, so a bare "yes"
  /// can be answered with "which one?" and a named topic can be
  /// dispatched directly.
  String pendingTopicContext = '';

  /// The record created at the start of this session.
  SleepRecord? _currentRecord;

  /// True once we have asked "how did you sleep last night?"
  bool _qualityAsked = false;

  /// True while we are waiting for the 1–5 rating reply.
  bool _awaitingQualityRating = false;

  // ── Intake state ──────────────────────────────────────────────────────────
  // Phases: 'ask_issue' → 'ask_bedtime' → 'ask_waketime' → 'done'
  String intakePhase  = 'ask_issue';
  String userIssue    = ''; // 'onset' | 'maintenance' | 'early' | 'quality'
  String userBedtime  = '';
  String userWakeTime = '';

  final List<SleepMessage> chatHistory = [];

  // ── BuildContext for navigation ────────────────────────────────────────────
  BuildContext? _context;
  void attachContext(BuildContext ctx) => _context = ctx;

  // ── Initialisation ─────────────────────────────────────────────────────────
  Future<void> init() async {
    await ttsService.initialise();
    await sttService.initialise();
    await sttService.forceReset();

    sttAvailable = sttService.isAvailable;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 200));

    intakePhase = 'ask_issue';
    const greeting =
        "Hi! I'm your Sleep Hygiene assistant. "
        "What's your main sleep concern - trouble falling asleep, "
        "waking during the night, waking too early, or feeling unrefreshed?";

    chatHistory.add(const SleepMessage(greeting, isUser: false));
    notifyListeners();

    await ttsService.speak(greeting);
    await ttsService.awaitCompletion();

    statusLabel = 'Tap the mic and speak';
    notifyListeners();
  }


  // ── STT / Mic ──────────────────────────────────────────────────────────────

  Future<void> onMicTap() async {
    isListening ? await stopListening() : await startListening();
  }

  Future<void> startListening() async {
    if (!sttService.isAvailable) {
      await ttsService.speak('Speech recognition is not available on this device.');
      await ttsService.awaitCompletion();
      return;
    }

    await ttsService.stop();
    await ttsService.awaitCompletion();

    isListening    = true;
    isProcessing   = false;
    recognizedText = '';
    statusLabel    = 'Listening…';
    notifyListeners();

    String result = '';
    try {
      result = await sttService.listen();
    } on SpeechException catch (e) {
      statusLabel = e.message;
      result = '';
    }

    print('DEBUG STT result: "$result"');          // ← add this
    print('DEBUG _awaitingQualityRating: $_awaitingQualityRating'); // ← add this

    await sttService.stop();
    isListening  = false;
    isProcessing = true;
    statusLabel  = 'Processing…';

    if (result.isNotEmpty) {
      chatHistory.add(SleepMessage(result, isUser: true));
      notifyListeners();
      await _handleVoiceCommand(result.toLowerCase());
    } else {
      print('DEBUG result was empty — skipping _handleVoiceCommand'); // ← add this
      notifyListeners();
    }

    isProcessing = false;
    statusLabel  = 'Tap the mic and speak';
    notifyListeners();
  }

  Future<void> stopListening() async {
    if (isProcessing) return;
    isProcessing = true;
    await sttService.stop();
    isListening = false;
    statusLabel = 'Processing…';

    if (recognizedText.isNotEmpty) {
      chatHistory.add(SleepMessage(recognizedText, isUser: true));
      notifyListeners();
      final textToProcess = recognizedText.toLowerCase();
      recognizedText = '';
      await _handleVoiceCommand(textToProcess);
    } else {
      notifyListeners();
    }

    isProcessing = false;
    notifyListeners();
  }

  // ── Public entry point for chip taps ──────────────────────────────────────
  Future<void> sendTextCommand(String displayLabel, String command) async {
    if (isProcessing || isListening) return;
    isProcessing = true;
    statusLabel  = 'Processing…';
    chatHistory.add(SleepMessage(displayLabel, isUser: true));
    notifyListeners();
    await _handleTopicCommand(command.toLowerCase()); // ← bypass intake
    isProcessing = false;
    notifyListeners();
  }

  // ── Conversational helper ──────────────────────────────────────────────────
  Future<void> _speak(String response) async {
    chatHistory.add(SleepMessage(response, isUser: false));
    statusLabel = 'Speaking…';
    notifyListeners();

    await ttsService.speak(response);
    await ttsService.awaitCompletion();

    statusLabel = 'Tap the mic and speak';
    notifyListeners();
  }

  // ── Word-boundary matching helper ──────────────────────────────────────────
  //
  // text.contains('tired') would match "untired" or "retired".
  // This ensures we only match the word as a standalone token.
  bool _hasWord(String text, String word) {
    return RegExp(r'\b' + RegExp.escape(word) + r'\b').hasMatch(text);
  }


  Future<void> _openWindDownScreen() async {
    if (_context == null || !_context!.mounted) return;
    await Navigator.push(
      _context!,
      PageRouteBuilder(
        pageBuilder:        (_, __, ___) => WindDownScreen(ttsService: ttsService),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
    await SleepRepository.logToolUsed('winddown');
  }

  Future<void> _openPmrScreen() async {
    if (_context == null || !_context!.mounted) return;
    await Navigator.push(
      _context!,
      PageRouteBuilder(
        pageBuilder:        (_, __, ___) => PmrScreen(ttsService: ttsService),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 600),
      ),
    );
    await SleepRepository.logToolUsed('pmr');
  }


  // ── Question-form pre-check ────────────────────────────────────────────────
  //
  // Returns true if the utterance is clearly informational in nature.
  // Used to short-circuit emotional-state intents for definitional queries.
  bool _isQuestion(String text) {
    return text.startsWith('what')   ||
        text.startsWith('how')    ||
        text.startsWith('why')    ||
        text.startsWith('when')   ||
        text.startsWith('which')  ||
        text.startsWith('who')    ||
        text.startsWith('define') ||
        text.startsWith('explain')||
        text.startsWith('tell me about') ||
        text.startsWith('describe');
  }

  // ── FAQ keyword-set matcher ─────────────────────────────────────────────
  // Returns the matched FAQ id, or null if no FAQ matches confidently.
  // Each FAQ has a set of keywords; if enough keywords are present
  // (regardless of order/phrasing), it's considered a match.
  String? _matchFaq(String text) {
    // Normalize common variants so keyword lists don't need every form
    final normalized = text
        .replaceAll('asleep', 'sleep')
        .replaceAll('drift off', 'sleep')
        .replaceAll('doze off', 'sleep')
        .replaceAll('nod off', 'sleep')
        .replaceAll('pass out', 'sleep')
        .replaceAll('knock out', 'sleep');

    final faqs = <String, List<String>>{
      'sleep_hygiene': [
        'hygiene', 'sleep habit', 'healthy sleep', 'good sleep habit',
        'sleep routine and environment', 'sleep hygiene', 'sleeping habits',
        'good sleeping', 'clean sleep', 'sleep cleanliness', 'sleep practices',
      ],
      'fall_asleep_faster': [
        'fall sleep faster', 'sleep faster', 'get to sleep faster',
        'go to sleep faster', 'how to sleep faster', 'cant sleep fast',
        "can't sleep fast", 'sleep quicker', 'sleep sooner',
        'tips to sleep', 'ways to sleep', 'help me sleep faster',
      ],
      'bedtime_routine': [
        'bedtime routine', 'night routine', 'wind down', 'wind-down',
        'routine before bed', 'routine look like', 'prepare for bed',
        'prepare for sleep', 'before bed routine', 'steps before bed',
        'before i go to bed', 'before sleeping', 'getting ready for bed',
        'pre bed', 'night time routine', 'evening routine', 'sleep ritual',
        'things to do before bed', 'what to do before sleeping',
      ],
      'phone_before_bed': [
        'phone', 'screen', 'blue light', 'mobile', 'device',
        'scrolling', 'social media', 'tv', 'television', 'tablet', 'laptop',
        'using my phone', 'on my phone', 'checking my phone', 'texting before bed',
        'instagram before bed', 'youtube before bed', 'gaming before bed',
        'browsing before bed', 'on social media',
      ],
      'sleep_duration': [
        'how many hours', 'how much sleep', 'hours of sleep',
        'how long sleep', 'sleep duration', 'enough sleep',
        'hours do i need', 'hours should i sleep', 'right amount of sleep',
        'normal amount of sleep', 'ideal sleep', 'recommended sleep',
        'sleep requirement', 'optimal sleep', '8 hours enough',
        '6 hours enough', 'is 5 hours enough',
      ],
      'napping': [
        'nap', 'napping', 'power nap', 'afternoon sleep', 'daytime sleep',
        'daytime nap', 'should i nap', 'is napping good', 'how long to nap',
        'best time to nap', 'nap too long', 'nap affect night sleep',
      ],
      'sleep_environment': [
        'bedroom', 'sleep environment', 'room temperature', 'dark room',
        'blackout curtains', 'white noise', 'noise and sleep', 'mattress',
        'pillow', 'too hot to sleep', 'too cold to sleep', 'light in bedroom',
        'sleep setup', 'ideal bedroom', 'bedroom temperature',
      ],
      'caffeine_sleep': [
        'caffeine and sleep', 'coffee and sleep', 'tea and sleep',
        'caffeine before bed', 'coffee before bed', 'caffeine affect sleep',
        'how long caffeine last', 'caffeine half life', 'when to stop coffee',
        'cut off caffeine', 'does caffeine affect sleep',
      ],
      'exercise_sleep': [
        'exercise and sleep', 'workout and sleep', 'gym and sleep',
        'exercise before bed', 'working out at night', 'does exercise help sleep',
        'best time to exercise for sleep', 'running and sleep', 'sport and sleep',
        'physical activity and sleep', 'exercise improve sleep',
      ],
      'melatonin': [
        'melatonin', 'sleep supplement', 'sleeping pill', 'sleep aid',
        'should i take melatonin', 'does melatonin work', 'melatonin dose',
        'valerian', 'magnesium for sleep', 'natural sleep aid',
        'medication for sleep', 'sleep tablet',
      ],
      'sleep_stages': [
        'sleep stages', 'rem sleep', 'deep sleep', 'light sleep',
        'sleep cycle', 'what is rem', 'what is deep sleep', 'what is light sleep',
        'how many sleep cycles', 'sleep stage', 'nrem',
        'what happens when i sleep', 'stages of sleep',
      ],
      'circadian_rhythm': [
        'circadian rhythm', 'body clock', 'internal clock', 'sleep wake cycle',
        'circadian', 'biological clock', 'what is circadian', 'reset body clock',
        'how does body clock work', 'sleep wake rhythm',
      ],
      'insomnia': [
        'insomnia', 'sleep disorder', 'chronic sleep problem',
        'never sleep well', 'sleep problem every night', 'cant sleep most nights',
        "can't sleep most nights", 'cbt i', 'cognitive behavioural therapy sleep',
        'do i have insomnia', 'what is insomnia', 'treat insomnia',
      ],
      'stress_sleep': [
        'stress and sleep', 'anxiety and sleep', 'worried cant sleep',
        'stressed cant sleep', 'overthinking at night', 'mind racing at night',
        'anxious at bedtime', 'stress affect sleep', 'anxiety affect sleep',
        'cant switch off', "can't switch off", 'racing thoughts at night',
      ],
      'sleep_schedule': [
        'sleep schedule', 'consistent sleep time', 'same bedtime', 'same wake time',
        'consistent wake time', 'fix sleep schedule', 'irregular sleep',
        'sleep at different times', 'sleep consistency', 'regular bedtime',
        'set sleep time', 'sleep routine schedule',
      ],
      'alcohol_sleep': [
        'alcohol and sleep', 'drinking and sleep', 'alcohol before bed',
        'does alcohol help sleep', 'alcohol affect sleep', 'wine before bed',
        'beer before bed', 'drinking affect sleep', 'alcohol make you sleep',
        'alcohol ruin sleep', 'alcohol sleep quality',
      ],
      'morning_grogginess': [
        'wake up tired', 'groggy in the morning', 'sleep inertia',
        'still tired after sleep', 'exhausted in the morning', 'not refreshed after sleep',
        'why am i tired after sleeping', 'tired when i wake', 'morning fatigue',
        'why do i feel groggy', 'heavy when i wake up', 'feel terrible in morning',
      ],
      'sleep_debt': [
        'sleep debt', 'catch up on sleep', 'catching up sleep', 'sleep deprivation',
        'can i catch up sleep', 'make up sleep', 'weekend sleep',
        'sleeping in on weekend', 'sleep less during week', 'sleep deficit',
        'cumulative sleep loss', 'not enough sleep for days',
      ],
      'dreams_nightmares': [
        'dream', 'nightmare', 'bad dream', 'vivid dream', 'why do i dream',
        'what causes nightmares', 'recurring dream', 'dreaming a lot',
        'not dreaming', 'remember dreams', 'lucid dream', 'night terror',
        'does dreaming mean good sleep',
      ],
      'waking_night': [
        'wake up at night', 'waking up at night', 'middle of night',
        'keep waking up', 'wake up multiple times', 'cant stay asleep',
        "can't stay asleep", 'light sleeper', 'sleep is broken',
        'wake up 3am', 'wake up 2am', 'wake up during night',
      ],
      'sleep_paralysis': [
        'sleep paralysis', 'cant move when waking', "can't move when waking",
        'frozen when waking', 'paralysed when waking', 'paralyzed when waking',
        'wake up and cant move', "wake up and can't move",
        'feel stuck when waking', 'body wont move when i wake',
        'shadow when sleeping', 'presence in room sleep',
        'hallucination waking up', 'scary waking experience',
      ],
    };

    final hasSleepContext = normalized.contains('sleep') ||
        normalized.contains('bed') || normalized.contains('night');

    final mentionsGettingToSleep = normalized.contains('to sleep') ||
        normalized.contains('fall sleep') || normalized.contains('get sleep');
    final mentionsSpeed = normalized.contains('fast') || normalized.contains('quick') ||
        normalized.contains('sooner') || normalized.contains('faster');

    if (mentionsGettingToSleep && mentionsSpeed) {
      return 'fall_asleep_faster';
    }

    String? best;
    int bestScore = 0;

    for (final entry in faqs.entries) {
      final id = entry.key;
      final keywords = entry.value;
      int score = 0;

      for (final kw in keywords) {
        final matched = kw.contains(' ')
            ? normalized.contains(kw)
            : _hasWord(normalized, kw);
        if (matched) score++;
      }

      if (id == 'phone_before_bed' && score > 0 && !hasSleepContext) {
        score = 0;
      }

      if (score > bestScore) {
        bestScore = score;
        best = id;
      }
    }

    return bestScore > 0 ? best : null;
  }

  // ── Connector helper ────────────────────────────────────────────────────
  String _join(String a, String b, {String type = 'reason'}) {
    const connectors = {
      'reason':      ['So ', "That's why ", 'This means '],
      'contrast':    ['That said, ', 'But ', 'Even so, '],
      'elaboration': ['Because of this, ', 'Which means ', 'In other words, '],
      'addition':    ['And ', 'Also, ', 'On top of that, '],
    };
    final pick = connectors[type]!;
    final connector = pick[a.length % pick.length];
    return '$a $connector${b[0].toLowerCase()}${b.substring(1)}';
  }

  // ── Topic dispatch helper ───────────────────────────────────────────────
  //
  // Given a follow-up utterance and the context tag of the menu that was
  // just offered, speaks the matching topic's info. Returns true if a topic
  // was matched and handled, false otherwise (caller should ask again).
  Future<bool> _dispatchTopicChoice(String text, String context) async {
    switch (context) {
      case 'sleep_concepts': // offered by 4a
        if (text.contains('stage') || text.contains('rem') || text.contains('deep') || text.contains('cycle')) {
          await _speakSleepStages();
          return true;
        }
        if (text.contains('hygiene')) {
          await _speakSleepHygiene();
          return true;
        }
        if (text.contains('tip') || text.contains('better')) {
          await _speakGeneralTips();
          return true;
        }
        return false;

      case 'hygiene_areas': // offered by 4b
        if (text.contains('screen') || text.contains('phone') || text.contains('blue light')) {
          await _speakScreenTime();
          return true;
        }
        if (text.contains('caffeine') || text.contains('coffee') || text.contains('alcohol')) {
          await _speakCaffeineAlcohol();
          return true;
        }
        if (text.contains('routine') || text.contains('wind down') || text.contains('wind-down')) {
          await _speakWindDown();
          return true;
        }
        if (text.contains('environment') || text.contains('bedroom') || text.contains('room')) {
          await _speakSleepEnvironment();
          return true;
        }
        return false;

      default:
        return false;
    }
  }

  // ── Topic content (extracted so they're reusable from menus) ───────────

  Future<void> _speakSleepStages() async {
    final ack  = "Sleep actually cycles through stages roughly every 90 minutes.";
    final core = "Light sleep is the drift-off phase, deep sleep is when your body repairs itself and locks in memories, and REM is when most dreaming happens - key for emotional regulation and learning.";
    final bridge = _join(core,
        "cutting sleep short hits mood and memory the hardest, since you don't get to cycle through everything.",
        type: 'reason');
    await _speak('$ack $bridge');
  }

  Future<void> _speakSleepHygiene() async {
    final ack  = "Sleep hygiene is basically your sleep habits as a whole.";
    final core = "It covers your bedtime routine, your sleep environment, and daytime habits like caffeine, exercise, and screen time.";
    final bridge = _join(core,
        "it works by reinforcing your circadian rhythm - the internal clock that decides when you feel sleepy or alert.",
        type: 'elaboration');
    currentState = 'awaiting_topic_choice';
    pendingTopicContext = 'hygiene_areas';
    notifyListeners();
    final cta = "Want specific tips on screen time, caffeine and alcohol, your bedtime routine, or your sleep environment?";
    await _speak('$ack $bridge $cta');
  }

  Future<void> _speakGeneralTips() async {
    final ack  = "Happy to help - here's what I can talk about.";
    final core = "Bedtime routines, trouble falling asleep, screen time, naps, sleep duration, your sleep environment, caffeine and alcohol, exercise, or melatonin.";
    final cta  = "You can also say 'go back' to head home, or ask for Breathing Exercises, Mindfulness, or Mood Tracking. What sounds good?";
    await _speak('$ack $core $cta');
  }

  Future<void> _speakScreenTime() async {
    final ack  = "Screens before bed are genuinely one of the hardest habits to break.";
    final core = "Blue light blocks melatonin - the hormone that makes you feel sleepy.";
    final bridge = _join(core,
        "even 30 minutes off screens before bed makes a measurable difference.",
        type: 'reason');
    final cta = "Try switching to a book, light stretching, or a podcast instead.";
    await _speak('$ack $bridge $cta');
  }

  Future<void> _speakCaffeineAlcohol() async {
    final ack  = "What you eat and drink in the evening matters more than most people realise.";
    final core = "Caffeine has a 6-hour half-life - a 3pm coffee is still half-strength at 9pm.";
    final bridge = _join(core,
        "cutting off around 2pm is the single easiest win.",
        type: 'reason');
    final alcohol = "Alcohol's the other one - it helps you fall asleep faster but wrecks deep and REM sleep later in the night.";
    await _speak('$ack $bridge $alcohol');
  }

  Future<void> _speakWindDown() async {
    final ack  = "A solid wind-down routine makes a real difference.";
    final core = "Dim lights an hour before bed, stop screens at 30 minutes, then read or stretch.";
    final tip  = "At 10 minutes, jot down any worries and focus on slow breathing once you're in bed.";
    await _speak('$ack $core $tip');
  }

  Future<void> _speakSleepEnvironment() async {
    final ack  = "Your bedroom setup matters more than people think.";
    final core = "The ideal room is cool, around 16 to 19 degrees, dark, and quiet - blackout curtains and white noise or earplugs help a lot.";
    final bridge = _join("Try to keep your bed for sleep only",
        "your brain builds a strong association between bed and sleep that way.",
        type: 'reason');
    await _speak('$ack $core $bridge');
  }

  // ── Intake handler ─────────────────────────────────────────────────────────
  // Returns true if the utterance was consumed by the intake flow.

  Future<bool> _handleIntake(String text) async {
    switch (intakePhase) {
      case 'ask_issue':
        if (text.contains('fall') || text.contains('onset') ||
            text.contains('cannot sleep') || text.contains("can't sleep") ||
            text.contains('drift off') || text.contains('get to sleep')) {
          userIssue = 'onset';
        } else if (text.contains('wak') ||
            text.contains('stay asleep')         ||
            text.contains('middle of the night') ||
            text.contains('during the night')    ||
            text.contains('through the night')   ||
            text.contains('night waking')        ||
            text.contains('wake up at night')) {
          userIssue = 'maintenance';
        } else if (text.contains('early') || text.contains('too soon') ||
            text.contains('before alarm')) {
          userIssue = 'early';
        } else if (text.contains('unrefreshed') || text.contains('tired') ||
            text.contains('groggy') || text.contains('quality') ||
            text.contains('rested')) {
          userIssue = 'quality';
        } else {
          // Doesn't match an issue keyword — likely an FAQ question.
          // Don't consume it; fall through to normal intent matching.
          return false;
        }
        intakePhase = 'done';
        notifyListeners();
        return false;
    }
    return false;
  }

  String _issueSummary() {
    switch (userIssue) {
      case 'onset':       return 'trouble falling asleep';
      case 'maintenance': return 'waking during the night';
      case 'early':       return 'waking too early';
      case 'quality':     return 'feeling unrefreshed';
      default:            return 'sleep quality';
    }
  }

  /// Returns a personalised context line to prepend to advice, based on
  /// what the user told us during intake.
  String _contextPrefix() {
    if (userIssue.isEmpty) return '';
    switch (userIssue) {
      case 'onset':
        return "Since your main issue is falling asleep, this is especially relevant for you. ";
      case 'maintenance':
        return "Given that you're waking during the night, pay extra attention to this. ";
      case 'early':
        return "For someone waking too early, this is worth noting. ";
      case 'quality':
        return "Since you're feeling unrefreshed, sleep quality is key here. ";
      default:
        return '';
    }
  }

  // ── Chip tap handler — always goes to intent engine, skips intake ──────────
  Future<void> _handleTopicCommand(String text) async {
    // Save and temporarily mark intake as done so intents fire correctly
    final savedPhase = intakePhase;
    intakePhase = 'done';
    await _handleVoiceCommand(text);
    // Restore intake phase only if it wasn't completed during the call
    if (intakePhase == 'done' && savedPhase != 'done') {
      intakePhase = savedPhase;
    }
  }

  // ── Voice command handler ──────────────────────────────────────────────────
  Future<void> _handleVoiceCommand(String text) async {
    if (text.isEmpty) {
      statusLabel = "I didn't catch that. Try again.";
      notifyListeners();
      await ttsService.speak("I didn't catch that. Please try again.");
      await ttsService.awaitCompletion();
      return;
    }

    // ── 0. Crisis detection — always first, even during intake ────────────────
    if (text.contains('kill myself')  ||
        text.contains('suicide')      ||
        text.contains('hurt myself')  ||
        text.contains('end my life')  ||
        text.contains('crisis')       ||
        text.contains('emergency')    ||
        text.contains('self harm')    ||
        text.contains('cutting')      ||
        text.contains('harming')      ||
        text.contains("don't want to wake up") ||
        text.contains("dont want to wake up")  ||
        text.contains("don't want to be here") ||
        text.contains("dont want to be here")  ||
        text.contains('want to disappear')     ||
        text.contains("can't go on")           ||
        text.contains("cant go on")) {
      _consecutiveFallbacks = 0;
      statusLabel = 'Redirecting to Emergency Support…';
      notifyListeners();
      const msg =
          'I hear how much pain you are in, and I want you to be safe. '
          'I am redirecting you to our emergency support page immediately. '
          'Please connect with a professional. You are not alone.';
      await _speak(msg);
      if (_context != null && _context!.mounted) {
        Navigator.push(
          _context!,
          MaterialPageRoute(builder: (_) => const EmergencySupportPage()),
        );
      }
      return;
    }

    // 0.3. Action-intent: open wind-down screen - MUST run before FAQ matcher
    if ((text.contains('start') || text.contains('begin') ||
        text.contains('do my') || text.contains('open') ||
        text.contains('launch') || text.contains('let\'s do') ||
        text.contains('lets do') || text.contains('begin my')) &&
        (text.contains('bedtime routine') ||
            text.contains('wind down')        ||
            text.contains('wind-down')        ||
            text.contains('night routine')    ||
            text.contains('sleep routine'))) {
      _consecutiveFallbacks = 0;
      await _speak("Starting your bedtime routine now.");
      await _openWindDownScreen();
      return;
    }


    if (text.contains('going to bed')        ||
        text.contains("i'm going to bed")    ||
        text.contains('im going to bed')     ||
        text.contains('i want to sleep now') ||
        text.contains('ready for bed')       ||
        text.contains('ready to sleep')      ||
        text.contains('time for bed')        ||
        text.contains('help me wind down')   ||
        text.contains('help me sleep')       ||
        text.contains('i need to relax')) {
      _consecutiveFallbacks = 0;
      await _speak("Starting your bedtime routine now.");
      await _openWindDownScreen();
      return;
    }

    // ── 0.5. FAQ keyword-set matching — catches any phrasing of the 5 core questions
    final faqMatch = _matchFaq(text);
    if (faqMatch != null) {
      _consecutiveFallbacks = 0;
      switch (faqMatch) {
        case 'sleep_hygiene':
          await _speak(
            "Sleep hygiene is your habits, routine, and environment around sleep - "
                "things like screen time, your wind-down routine, and keeping your room cool and dark.",
          );
          return;
        case 'fall_asleep_faster':
          if (text.startsWith('what is') || text.startsWith('what are') ||
              text.startsWith('define')   || text.startsWith('explain')) {
            await _speak(
              "Falling asleep faster is about calming your body and mind so they're "
                  "ready to switch off - mainly through breathing, reducing stimulation, "
                  "and a consistent wind-down.",
            );
          } else {
            final prefix = _contextPrefix();
            await _speak(
              '${prefix}Try 4-7-8 breathing: in for 4, hold for 7, out for 8. '
                  'Cutting screens 30 minutes before bed and a bit of light stretching also help.',
            );
          }
          return;
        case 'bedtime_routine':
          if (text.startsWith('what is') || text.startsWith('what are') ||
              text.startsWith('define')   || text.startsWith('explain') ||
              (text.contains('what') && text.contains('mean'))) {
            await _speak(
              "A bedtime routine is a set of calming activities you do each night "
                  "to help your body and mind wind down before sleep.",
            );
          } else {
            await _speak(
              "Dim the lights an hour before bed, stop screens about 30 minutes before, "
                  "then read or stretch to wind down.",
            );
          }
          return;
        case 'phone_before_bed':
          if (text.startsWith('what is') || text.startsWith('what are') ||
              text.startsWith('define')   || text.startsWith('explain')) {
            await _speak(
              "Using your phone before bed exposes you to blue light, which suppresses "
                  "melatonin and makes it harder for your body to feel sleepy.",
            );
          } else {
            await _speak(
              "Yes - blue light from screens blocks melatonin, the hormone that makes you sleepy. "
                  "Try going screen-free for the last 30 minutes before bed.",
            );
          }
          return;

        case 'sleep_duration':
          await _speak("For adults aged 18 to 30, 7 to 9 hours a night is the recommended range.");
          return;
        case 'napping':
          await _speak(
            "Naps can help - but timing is everything. "
                "The sweet spot is 10 to 20 minutes, before 3pm. "
                "Any longer and you risk waking up groggy - "
                "and late naps make it harder to fall asleep at night.",
          );
          return;

        case 'sleep_environment':
          await _speak(
            "Your bedroom setup matters more than most people think - "
                "cool temperature around 16 to 19 degrees - "
                "as dark as possible with blackout curtains if you can - "
                "and quiet, or use white noise to block out sounds. "
                "Try to keep your bed for sleep only.",
          );
          return;

        case 'caffeine_sleep':
          await _speak(
            "Caffeine has a half-life of around 6 hours - "
                "so a 3pm coffee is still half-strength at 9pm. "
                "Cutting off around 2pm is the single easiest win for better sleep.",
          );
          return;

        case 'exercise_sleep':
          await _speak(
            "Exercise is one of the best things you can do for sleep - "
                "it deepens sleep and helps you fall asleep faster. "
                "Timing matters though - "
                "vigorous workouts within 2 hours of bed raise your heart rate "
                "and make it harder to wind down. "
                "Morning or early afternoon is the sweet spot.",
          );
          return;

        case 'melatonin':
          await _speak(
            "Melatonin is a hormone your body already makes when it gets dark. "
                "A small dose - around 0.5 to 1 milligram - an hour before bed can help, "
                "especially for jet lag or shift work. "
                "It works best paired with good sleep habits and a dark room - "
                "and check with your doctor before starting any supplement.",
          );
          return;

        case 'sleep_stages':
          await _speak(
            "Sleep cycles through stages roughly every 90 minutes - "
                "light sleep is the drift-off phase - "
                "deep sleep is when your body repairs itself and locks in memories - "
                "and REM is when most dreaming happens, key for emotional regulation and learning. "
                "Cutting sleep short hits mood and memory the hardest.",
          );
          return;

        case 'circadian_rhythm':
          await _speak(
            "Your circadian rhythm is your body's internal clock - "
                "driven mainly by light. "
                "Morning sunlight is the strongest signal that resets it each day. "
                "The fix for a disrupted clock is simple - "
                "wake at the same time daily and get outside in the morning.",
          );
          return;

        case 'insomnia':
          await _speak(
            "Insomnia is when sleep problems happen most nights for months on end. "
                "The best treatment is CBT-I - cognitive behavioural therapy for insomnia - "
                "it works better than sleeping pills with no side effects. "
                "If this sounds like you, a GP or sleep specialist is worth seeing.",
          );
          return;

        case 'stress_sleep':
          await _speak(
            "Stress and anxiety are among the biggest reasons people can't switch off at night. "
                "A brain dump before bed - writing your worries down - "
                "helps get them out of your head. "
                "Slow breathing and a consistent wind-down routine "
                "also calm the nervous system over time.",
          );
          return;

        case 'sleep_schedule':
          await _speak(
            "Consistency is the biggest lever for sleep quality - "
                "going to bed and waking at the same time every day, weekends included, "
                "trains your circadian rhythm to feel sleepy on cue. "
                "Even one late night can set you back for a few days.",
          );
          return;

        case 'alcohol_sleep':
          await _speak(
            "Alcohol is a tricky one - "
                "it helps you fall asleep faster but fragments sleep later in the night, "
                "suppressing deep and REM sleep. "
                "You might drift off easily but wake up feeling unrefreshed. "
                "Even one or two drinks can affect sleep quality.",
          );
          return;

        case 'morning_grogginess':
          await _speak(
            "Waking up groggy is often sleep inertia - "
                "your body being pulled out of a deep sleep stage. "
                "A consistent wake time helps your body time it better. "
                "Natural light within 30 minutes of waking "
                "and some light movement also speed up how quickly you feel alert.",
          );
          return;

        case 'sleep_debt':
          await _speak(
            "Sleep debt is real - but you can't fully recover it in one weekend. "
                "Sleeping in helps short-term but disrupts your schedule for the week ahead. "
                "The better fix is gradually shifting your bedtime earlier by 15 minutes each night "
                "until you're consistently getting 7 to 9 hours.",
          );
          return;

        case 'dreams_nightmares':
          await _speak(
            "Dreams mostly happen during REM sleep - "
                "they're linked to emotional processing and memory consolidation. "
                "Vivid dreams or nightmares often spike with stress, alcohol, or disrupted sleep. "
                "A consistent wind-down and reducing stress before bed usually helps.",
          );
          return;

        case 'waking_night':
          await _speak(
            "Waking during the night is usually linked to light sleep cycles, "
                "room temperature, or stress. "
                "Keep your room around 18 degrees - "
                "and if you wake up, skip the phone. "
                "Slow breathing and progressive muscle relaxation "
                "work better than scrolling.",
          );
          return;

        case 'sleep_paralysis':
          await _speak(
            "Sleep paralysis is your brain waking up while your body is still in REM - "
                "temporarily keeping muscles still. "
                "Harmless, but can feel frightening. "
                "Better sleep consistency and lower stress reduces how often it happens.",
          );
          return;

      }
    }

    // ── 0.7. Explicit module navigation — only on clear "open/start X" intent
    if ((text.contains('open') || text.contains('start') || text.contains('go to') ||
        text.contains('take me') || text.contains('switch to')) &&
        (text.contains('breathing') || text.contains('breath exercise'))) {
      _consecutiveFallbacks = 0;
      await _speak('Opening Breathing Exercises.');
      if (_context != null && _context!.mounted) {
        Navigator.push(_context!, MaterialPageRoute(builder: (_) => const BreathingExercisesPage()));
      }
      return;
    }

    if ((text.contains('open') || text.contains('start') || text.contains('go to') ||
        text.contains('take me') || text.contains('switch to')) &&
        (text.contains('mindfulness') || text.contains('meditation'))) {
      _consecutiveFallbacks = 0;
      await _speak('Opening Mindfulness.');
      if (_context != null && _context!.mounted) {
        Navigator.push(_context!, MaterialPageRoute(builder: (_) => const MindfulnessPage()));
      }
      return;
    }

    if ((text.contains('open') || text.contains('start') || text.contains('go to') ||
        text.contains('take me') || text.contains('switch to')) &&
        (text.contains('mood'))) {
      _consecutiveFallbacks = 0;
      await _speak('Opening Mood Tracking.');
      if (_context != null && _context!.mounted) {
        Navigator.push(_context!, MaterialPageRoute(builder: (_) => const MoodTrackingPage()));
      }
      return;
    }

    // ── 1. Intake phase (runs until intake is complete) ───────────────────────
    if (intakePhase != 'done') {
      final handled = await _handleIntake(text);
      if (handled) return;
    }

    // ── 2. Awaiting nav confirmation ───────────────────────────────────────
    if (currentState == 'awaiting_nav_confirmation') {
      final isYes = text.contains('yes')     || text.contains('sure')    ||
          text.contains('okay')    || text.contains('ok')      ||
          text.contains('please')  || text.contains('yep')     ||
          text.contains('yup')     || text.contains('alright') ||
          text.contains('go')      || text.contains('fine');
      final isNo  = text.contains('no')      || text.contains('nah')     ||
          text.contains('nope')    || text.contains('cancel')  ||
          text.contains('not now') || text.contains('later');

      if (isYes) {
        _consecutiveFallbacks = 0;
        currentState = 'idle';
        await _navigateTo(pendingNavRoute);
        pendingNavRoute = '';
      } else if (isNo) {
        _consecutiveFallbacks = 0;
        currentState    = 'idle';
        pendingNavRoute = '';
        notifyListeners();
        await _speak(
          "No problem. I'm here whenever you need anything else. "
              "Just ask me about sleep tips, bedtime routines, or anything related to better sleep.",
        );
      } else {
        _consecutiveFallbacks = 0;
        await _speak('Just say yes to continue, or no if you prefer to stay here.');
      }
      return;
    }

    // ── 2.5. Awaiting topic choice ─────────────────────────────────────────
    if (currentState == 'awaiting_topic_choice') {
      final context = pendingTopicContext;
      currentState = 'idle';
      // Don't clear pendingTopicContext here yet

      final isYes = text.contains('yes')  || text.contains('sure') ||
          text.contains('okay') || text.contains('ok')   ||
          text.contains('please') || text.contains('yep')  ||
          text.contains('yup')  || text.contains('alright');
      final isNo  = text.contains('no')   || text.contains('nah')  ||
          text.contains('nope') || text.contains('not now') ||
          text.contains('later');

      if (isNo) {
        pendingTopicContext = ''; // Clear only on definitive exit
        _consecutiveFallbacks = 0;
        await _speak(
          "No problem. I'm here whenever you need anything else. "
              "Just ask me about sleep tips, bedtime routines, or anything related to better sleep.",
        );
        return;
      }

      final handled = await _dispatchTopicChoice(text, context);
      if (handled) {
        pendingTopicContext = ''; // Clear only on definitive exit
        _consecutiveFallbacks = 0;
        return;
      }

      if (isYes) {
        _consecutiveFallbacks = 0;
        currentState = 'awaiting_topic_choice';
        pendingTopicContext = context; // Restore (was never cleared)
        notifyListeners();
        await _speak("Sure - which one would you like to hear about?");
        return;
      }

      pendingTopicContext = ''; // Clear only when falling through
      // Unrecognised reply: fall through to normal intent matching below.
    }

    // ── 2.8. Section voice triggers ───────────────────────────────────────────
    if (text.contains('question') || text.contains('ask something') ||
        text.contains('i have a question') || text.contains('learn about')) {
      _consecutiveFallbacks = 0;
      await _speak(
        "Sure! You can ask me about trouble falling asleep, sleep stages, "
            "caffeine and sleep, screen time, or how many hours of sleep you need. "
            "Just say whichever one you'd like.",
      );
      return;
    }

    if (text.contains('activit') || text.contains('something to do') ||
        text.contains('exercise') && text.contains('sleep') ||
        text.contains('relax') && text.contains('now')) {
      _consecutiveFallbacks = 0;
      await _speak(
        "Happy to help you wind down. "
            "Just say 'start bedtime routine' to begin your wind-down session.",
      );
      return;
    }

    // ── 3. Back / exit / stop — checked before any topic intents ──────────
    if (_hasWord(text, 'back') || _hasWord(text, 'home') ||
        _hasWord(text, 'exit') || _hasWord(text, 'quit') ||
        _hasWord(text, 'leave')) {
      _consecutiveFallbacks = 0;
      statusLabel = 'Going back…';
      notifyListeners();
      await ttsService.speak('Going back to the home page. Sweet dreams!');
      await ttsService.awaitCompletion();
      if (_context != null && _context!.mounted) Navigator.pop(_context!);
      return;
    }

    if (_hasWord(text, 'stop')  || _hasWord(text, 'pause') ||
        _hasWord(text, 'quiet') || _hasWord(text, 'mute')) {
      _consecutiveFallbacks = 0;
      await ttsService.stop();
      await ttsService.awaitCompletion();
      statusLabel = 'Tap the mic and speak';
      notifyListeners();
      return;
    }

    // ── 4. DEFINITIONAL / INFORMATIONAL intents ────────────────────────────
    // utterances ("what is sleep", "explain REM") are never misrouted to an
    // emotional-state rule that happens to share a keyword.

    // 4a. What is sleep (bare concept — not "sleep hygiene", handled below)
    if (_isQuestion(text) &&
        (text.contains('what is sleep') ||
            text.contains('define sleep')  ||
            text.contains('explain sleep') ||
            (text.contains('what does sleep') && !text.contains('hygiene'))) &&
        !text.contains('hygiene') &&
        !text.contains('stage')   &&
        !text.contains('rem')     &&
        !text.contains('cycle')) {
      _consecutiveFallbacks = 0;

      final ack  = "Good question - sleep is more than just rest.";
      final core = "It's a recurring state where your brain consolidates memories and your body repairs itself, with growth hormone released along the way.";
      currentState = 'awaiting_topic_choice';
      pendingTopicContext = 'sleep_concepts';
      notifyListeners();
      final cta  = "Want to know about sleep stages, sleep hygiene, or tips for sleeping better?";
      await _speak('$ack $core $cta');
      return;
    }

    // 4b. What is sleep hygiene
    if (text.contains('what is sleep hygiene')  ||
        text.contains('explain sleep hygiene')  ||
        text.contains('sleep hygiene meaning')  ||
        text.contains('define sleep hygiene')   ||
        text.contains('sleep hygiene refers')   ||
        text.contains('sleep hygiene is')       ||
        text.contains('sleep hygiene means')    ||
        text.contains('sleep hygiene')          ||
        text.contains('healthy sleep habit')    ||
        text.contains('good sleep habit')       ||
        text.contains('hygiene'))
    {
      _consecutiveFallbacks = 0;
      await _speak(
        "Sleep hygiene is your habits, routine, and environment around sleep - "
            "things like screen time, your wind-down routine, and keeping your room cool and dark.",
      );
      return;
    }

    // 4c. Circadian rhythm
    if (text.contains('circadian')       ||
        text.contains('body clock')      ||
        text.contains('internal clock')  ||
        text.contains('sleep wake cycle')) {
      _consecutiveFallbacks = 0;
      final ack  = "Your circadian rhythm is basically your body's internal clock.";
      final core = "It's driven mainly by light - morning sunlight is the strongest signal that resets it each day.";
      final bridge = _join(core,
          "shift work, late nights, or jet lag throw it off and lead to poor sleep and daytime fatigue.",
          type: 'reason');
      final tip = "The fix is simple: wake at the same time daily and get outside in the morning.";
      await _speak('$ack $bridge $tip');
      return;
    }

    // 4d. REM / sleep stages
    if (text.contains('rem sleep')                 || text.contains('sleep stages')        ||
        text.contains('deep sleep')                || text.contains('light sleep')         ||
        text.contains('sleep cycle')               || text.contains('what is rem')         ||
        text.contains('what are sleep stages')     || text.contains('explain sleep stage') ||
        text.contains('tell me about sleep stages')|| text.contains('sleep stage')         ||
        text.contains('what happens when i sleep')) {
      _consecutiveFallbacks = 0;
      final ack  = "Sleep cycles through stages roughly every 90 minutes."; // ← no "Good question"
      final core = "Light sleep is the drift-off phase, deep sleep is when your body repairs itself "
          "and locks in memories, and REM is when most dreaming happens — key for emotional regulation and learning.";
      final bridge = _join(core,
          "cutting sleep short hits mood and memory the hardest, since you don't get to cycle through everything.",
          type: 'reason');
      await _speak('$ack $bridge');
      return;
    }

    // 4e. Insomnia (informational framing)
    if (text.contains('insomnia')                     ||
        text.contains('chronic sleep problem')        ||
        text.contains('always have trouble sleeping') ||
        text.contains('never sleep well')             ||
        text.contains('sleep disorder')) {
      _consecutiveFallbacks = 0;
      final ack  = "Insomnia is when sleep problems happen most nights for months on end.";
      final core = "The best treatment is CBT-I - it works better than sleeping pills, no side effects.";
      final cta  = "If this sounds like you, a GP or sleep specialist is worth seeing.";
      await _speak('$ack $core $cta');
      return;
    }

    // 4f. Sleep duration (informational — "how many hours", "how long")
    if (text.contains('how many hours')            ||
        text.contains('how long should i sleep')   ||
        text.contains('sleep duration')            ||
        text.contains('enough sleep')              ||
        text.contains('too much sleep')            ||
        text.contains('oversleeping')              ||
        text.contains('8 hours')                   ||
        text.contains('7 hours')                   ||
        text.contains('9 hours')                   ||
        text.contains('how much sleep')            ||
        text.contains('how many hours do i need')  ||
        text.contains('hours of sleep do i need')) {
      _consecutiveFallbacks = 0;
      await _speak("For adults aged 18 to 30, 7 to 9 hours a night is the recommended range.");
      return;
    }


    // 4f.8. Bedtime routine STRUCTURE (what should I do, step by step)
    if (text.contains('what should my bedtime routine') ||
        text.contains('what should my routine')         ||
        text.contains('bedtime routine look like')      ||
        text.contains('routine look like')              ||
        text.contains('steps for my bedtime')           ||
        text.contains('what should i do before bed')) {
      _consecutiveFallbacks = 0;
      await _speak(
        "Dim the lights an hour before bed, stop screens about 30 minutes before, "
            "then read or stretch to wind down.",
      );
      return;
    }

    // 4g. Sleep schedule / consistency (informational)
    if (text.contains('sleep schedule')              ||
        text.contains('sleep time')                  ||
        text.contains('consistent sleep')            ||
        text.contains('same sleep time')             ||
        text.contains('wake time')                   ||
        text.contains('bedtime routine')             ||
        text.contains('sleep routine')               ||
        text.contains('nighttime routine')           ||
        text.contains('what should my bedtime')      ||
        text.contains('what should i do at night')   ||
        text.contains('before i sleep')              ||
        (text.contains('before bed') &&
            !text.contains('phone') && !text.contains('screen') &&
            !text.contains('tv') && !text.contains('television') &&
            !text.contains('tablet') && !text.contains('laptop'))  ||
        (text.contains('what time') && (text.contains('sleep') || text.contains('bed') || text.contains('wake'))) ||
        (text.contains('consistent') && (text.contains('sleep') || text.contains('bed') || text.contains('wake'))) ||
        (text.contains('same time') && (text.contains('sleep') || text.contains('bed') || text.contains('wake')))) {
      _consecutiveFallbacks = 0;
      final ack  = "Consistency is honestly the biggest lever for sleep quality.";
      final core = "Going to bed and waking at the same time every day, weekends included, trains your circadian rhythm to feel sleepy at the right time.";
      final bridge = _join(core,
          "work backwards from your wake time and build a 30-minute wind-down before it - dim lights, no screens, something calming.",
          type: 'addition');
      await _speak('$ack $bridge');
      return;
    }


    // ── 5. CROSS-MODULE MENTIONS — stay in scope ──────────────────────────────
    // We don't navigate away. We answer the sleep-relevant part inline.

    if (text.contains('breathing')       ||
        text.contains('breathe')         ||
        text.contains('breath exercise') ||
        text.contains('box breathing')) {
      _consecutiveFallbacks = 0;
      await _speak("Opening Breathing Exercises for you now.");
      if (_context != null && _context!.mounted) {
        await Navigator.push(_context!, MaterialPageRoute(builder: (_) => const BreathingExercisesPage()));
      }
      return;
    }

    if (text.contains('mindfulness')        ||
        text.contains('meditation')         ||
        text.contains('meditate')           ||
        text.contains('body scan')          ||
        text.contains('guided meditation')) {
      _consecutiveFallbacks = 0;
      final prefix = _contextPrefix();
      final ack  = "A short mindfulness practice before bed is one of the best things for sleep.";
      final core = "Try a body scan: lie down, close your eyes, and slowly move attention from your toes upward, releasing tension in each part.";
      final bridge = _join(core,
          "doing this nightly trains your nervous system to associate bed with relaxation.",
          type: 'reason');
      await _speak('$prefix$ack $bridge');
      return;
    }

    if (text.contains('track my mood')      ||
        text.contains('log my mood')         ||
        text.contains('mood and sleep')      ||
        text.contains('mood affect sleep')   ||
        text.contains('sleep affect mood')   ||
        text.contains('mood tracker')        ||
        text.contains('how am i feeling')) {
      _consecutiveFallbacks = 0;
      await _speak(
        "Mood and sleep are deeply linked. Poor sleep raises cortisol and lowers emotional resilience, "
            "while stress and low mood make it harder to switch off at night. "
            "If you notice you're struggling emotionally, a consistent bedtime routine helps stabilise both.",
      );
      return;
    }

    // ── 6. SYMPTOM / STATE intents ─────────────────────────────────────────
    // These use _hasWord() for short emotional keywords so that a bare word
    // like "tired" in "what is sleep" can never fire here if the question-form
    // pre-check above catches it first. For multi-word phrases, contains() is
    // still fine since there is no ambiguity.

    // 6a. Can't fall asleep / sleep onset
    if (text.contains('cannot fall asleep')     ||
        text.contains("can't fall asleep")      ||
        text.contains('trouble falling asleep') ||
        text.contains('hard to fall asleep')    ||
        text.contains('falling asleep')         ||
        text.contains('cannot sleep')           ||
        text.contains("can't sleep")            ||
        text.contains('lying awake')            ||
        text.contains('wide awake')             ||
        text.contains('mind is racing')         ||
        text.contains('racing thoughts')        ||
        text.contains('thoughts keep me awake') ||
        text.contains('why cant i sleep')       ||
        text.contains("why can't i sleep")      ||
        text.contains('why am i not sleeping')  ||
        text.contains('why do i not sleep')     ||
        text.contains('why is it hard to sleep')||
        text.contains('why do i wake up')       ||
        text.contains('cannot get to sleep')    ||
        text.contains("can't get to sleep")     ||
        text.contains('unable to sleep')        ||
        text.contains('having trouble sleeping')    ||
        text.contains('fall asleep faster')         ||
        text.contains('sleep faster')               ||
        text.contains('how to fall asleep')         ||
        text.contains('how do i fall asleep')) {

      _consecutiveFallbacks = 0;
      final prefix = _contextPrefix();
      await _speak(
        '${prefix}Try 4-7-8 breathing: in for 4, hold for 7, out for 8. '
            'Cutting screens 30 minutes before bed and a bit of light stretching also help.',
      );
      return;
    }

    // 6b. Waking during the night
    if (text.contains('keep waking')          ||
        text.contains('wake up at night')     ||
        text.contains('waking up')            ||
        text.contains('wake in the middle')   ||
        text.contains('middle of the night')  ||
        text.contains('cannot stay asleep')   ||
        text.contains("can't stay asleep")    ||
        text.contains('sleep is broken')      ||
        text.contains('light sleeper')) {
      _consecutiveFallbacks = 0;
      final ack  = "Waking mid-night is frustrating.";
      final core = "Keep your room around 18 degrees - your body drops temperature during deep sleep.";
      final tip  = "If you wake up, skip the phone. Slow breathing and relaxing each muscle works better.";
      await _speak('$ack $core $tip');
      return;
    }

    // 6c. Feeling unrefreshed
    if (text.contains('unrefreshed')              ||
        text.contains('still tired')              ||
        _hasWord(text, 'groggy')                  ||
        text.contains('tired in the morning')     ||
        text.contains('wake up tired')            ||
        text.contains('not rested')               ||
        text.contains('exhausted in the morning') ||
        text.contains('sleep is not helping')     ||
        text.contains('sleep does not help')) {
      _consecutiveFallbacks = 0;
      final ack  = "Waking up tired even after a full night usually points to sleep quality, not just quantity.";
      final core = "A consistent wake time, even on weekends, anchors your internal clock.";
      final bridge = _join(core,
          "limiting caffeine after 2pm helps too, since it has about a 6-hour half-life.",
          type: 'addition');
      final tip = "Getting natural light within 30 minutes of waking also resets your rhythm for the next night.";
      await _speak('$ack $bridge $tip');
      return;
    }

    // 6d. Anxiety / stress affecting sleep
    if (_hasWord(text, 'anxious')      || _hasWord(text, 'anxiety')      ||
        _hasWord(text, 'stressed')     || _hasWord(text, 'stress')       ||
        _hasWord(text, 'worried')      || _hasWord(text, 'worry')        ||
        _hasWord(text, 'nervous')      || _hasWord(text, 'overthinking') ||
        _hasWord(text, 'overthink')    || _hasWord(text, 'restless')     ||
        _hasWord(text, 'panicking')    || _hasWord(text, 'panic')) {
      _consecutiveFallbacks = 0;
      final prefix = _contextPrefix();
      await _speak(
        '${prefix}Anxiety is one of the biggest reasons people can\'t switch off at night. '
            'Opening Mindfulness for you now.',
      );
      if (_context != null && _context!.mounted) {
        await Navigator.push(_context!, MaterialPageRoute(builder: (_) => const MindfulnessPage()));
      }
      return;
    }

    // 6e. Feeling tired / sleepy RIGHT NOW
    // Uses _hasWord() so "what is sleep" or "sleep tips" never matches here.
    // Also guarded by NOT _isQuestion() as a secondary safety net.
    if (!_isQuestion(text) &&
        (_hasWord(text, 'tired')         ||
            _hasWord(text, 'sleepy')        ||
            _hasWord(text, 'drowsy')        ||
            _hasWord(text, 'exhausted')     ||
            text.contains('need to sleep'))) {

      _consecutiveFallbacks = 0;
      final prefix = _contextPrefix();
      final ack  = "Sounds like your body's ready for rest — that's a good sign.";
      final core = "Head to bed now rather than pushing through it; that sleepy window can pass quickly.";
      final tip  = "Phone down, lights dim, and give yourself permission to actually sleep.";
      final extra = "If your mind starts racing, try 4-7-8 breathing until it settles.";
      await _speak('$prefix$ack $core $tip $extra');
      return;

    }

    // ── 7. TOPIC intents ───────────────────────────────────────────────────

    // 7a. Naps
    if (_hasWord(text, 'nap')          || text.contains('napping')       ||
        text.contains('afternoon sleep')|| text.contains('daytime sleep') ||
        text.contains('power nap')) {
      _consecutiveFallbacks = 0;
      final ack  = "Naps can actually help if you time them right.";
      final core = "The sweet spot is 10 to 20 minutes, before 3pm - long enough for a boost, short enough to skip deep sleep.";
      final bridge = _join(core,
          "needing naps over 30 minutes regularly often means your night sleep isn't enough.",
          type: 'contrast');
      await _speak('$ack $bridge');
      return;
    }

    // 7b. Screen time / blue light
    if (_hasWord(text, 'screen')              || _hasWord(text, 'phone')         ||
        text.contains('blue light')           || text.contains('social media')   ||
        text.contains('scrolling')            || _hasWord(text, 'laptop')        ||
        _hasWord(text, 'tablet')              || text.contains('tv before bed')  ||
        text.contains('television before bed')|| text.contains('watching before bed')       ||
        text.contains('phone before bed')          ||
        text.contains('phone affect sleep')        ||
        text.contains('does screen affect sleep')  ||
        text.contains('does phone affect sleep')) {
      _consecutiveFallbacks = 0;
      await _speak(
        "Yes - blue light from screens blocks melatonin, the hormone that makes you sleepy. "
            "Try going screen-free for the last 30 minutes before bed.",
      );
      return;
    }

    // 7c. Sleep environment / bedroom
    if (_hasWord(text, 'bedroom')          || text.contains('environment')      ||
        text.contains('room temperature')  || text.contains('too hot')          ||
        text.contains('too cold')          || _hasWord(text, 'noise')           ||
        _hasWord(text, 'noisy')            || text.contains('dark room')        ||
        text.contains('light in my room')  || _hasWord(text, 'mattress')        ||
        _hasWord(text, 'pillow')) {
      _consecutiveFallbacks = 0;
      final ack  = "Your bedroom setup matters more than people think.";
      final core = "The ideal room is cool, around 16 to 19 degrees, dark, and quiet - blackout curtains and white noise or earplugs help a lot.";
      final bridge = _join("Try to keep your bed for sleep only",
          "your brain builds a strong association between bed and sleep that way.",
          type: 'reason');
      await _speak('$ack $core $bridge');
      return;
    }

    // 7d. Caffeine / alcohol / food
    if (_hasWord(text, 'caffeine')            || _hasWord(text, 'coffee')          ||
        _hasWord(text, 'tea')                 || _hasWord(text, 'alcohol')         ||
        text.contains('drinking before bed')  ||
        text.contains('drinking alcohol')     ||
        text.contains('eating before bed')    ||
        text.contains('food before bed')      ||
        text.contains('late meal')            ||
        text.contains('snack before bed')) {
      _consecutiveFallbacks = 0;
      await _speak(
        'Caffeine has a half-life of around 6 hours, so a 3pm coffee is still '
            'half-strength at 9pm - cut off around 2pm. '
            'Alcohol helps you fall asleep faster but wrecks deep and REM sleep later. '
            'Avoid heavy meals within 2 hours of bed.',
      );
      return;
    }

    // 7e. Exercise and sleep
    if (_hasWord(text, 'exercise')         || _hasWord(text, 'workout')         ||
        _hasWord(text, 'gym')              || text.contains('physical activity') ||
        _hasWord(text, 'running')          || _hasWord(text, 'sport')) {
      _consecutiveFallbacks = 0;
      final ack  = "Exercise is one of the best things you can do for sleep.";
      final core = "It deepens sleep and helps you fall asleep faster.";
      final bridge = _join("Timing matters though",
          "vigorous workouts within 2 hours of bed raise your heart rate and temperature, making it harder to wind down.",
          type: 'contrast');
      final tip = "Morning or early afternoon sessions tend to work best.";
      await _speak('$ack $core $bridge $tip');
      return;
    }

    // 7f. Melatonin / supplements
    if (_hasWord(text, 'melatonin')         || _hasWord(text, 'supplement')      ||
        text.contains('sleeping pill')       || text.contains('sleep aid')        ||
        text.contains('medication for sleep')|| _hasWord(text, 'valerian')        ||
        _hasWord(text, 'magnesium')) {
      _consecutiveFallbacks = 0;
      final ack  = "Melatonin is a hormone your body already makes when it gets dark.";
      final core = "A small dose, around 0.5 to 1 milligram, an hour before bed can help shift your timing - especially for jet lag or shift work.";
      final bridge = _join(core,
          "it's not a sedative, so it works best paired with good habits and a dark room.",
          type: 'contrast');
      final cta = "For any sleep meds or supplements, check with your doctor first.";
      await _speak('$ack $bridge $cta');
      return;
    }

    // 7g. Bedtime routine / wind down
    if (text.contains('wind down')                   ||
        text.contains('wind-down')                   ||
        text.contains('what should i do before bed') ||
        text.contains('pre-sleep')                   ||
        text.contains('prepare for sleep')           ||
        text.contains('get ready for sleep')         ||
        text.contains('relax before bed')            ||
        text.contains('before bed routine')          ||
        text.contains('bedtime routine session')     ||
        text.contains('wind down session')           ||
        text.contains('wind-down session')) {
      _consecutiveFallbacks = 0;
      await _speak("Starting your bedtime routine now.");
      await _openWindDownScreen();
      return;
    }

    // 7j. Sleep progress / chart
    if (text.contains('my progress')             ||
        text.contains('how am i doing')          ||
        text.contains('sleep progress')          ||
        text.contains('sleep history')           ||
        text.contains('sleep graph')             ||
        text.contains('sleep chart')             ||
        text.contains('show my sleep')           ||
        text.contains('how has my sleep been')   ||
        text.contains('is my sleep improving')   ||
        text.contains('sleep trend')             ||
        text.contains('am i getting better')) {
      _consecutiveFallbacks = 0;
      await _speak(
        "Sure — here's your sleep progress chart. "
            "It shows your quality ratings over the last 14 nights "
            "plus a trend line so you can see how things are moving.",
      );
      if (_context != null && _context!.mounted) {
        await Navigator.push(
          _context!,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SleepGraphScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
            transitionDuration: const Duration(milliseconds: 500),
          ),
        );
      }
      return;
    }

    // 7h. General tips / help
    // 7h. Greetings / small talk
    if (_hasWord(text, 'hello')      || _hasWord(text, 'hi')         ||
        _hasWord(text, 'hey')        || _hasWord(text, 'yo')         ||
        text.contains("what's up")   || text.contains('whats up')    ||
        text.contains("what's good") || text.contains('sup')) {
      _consecutiveFallbacks = 0;
      const responses = [
        'Hello! How can I help with your sleep tonight?',
        'Hey there! Got a sleep question for me?',
        'Hi! What can I help you with?',
      ];
      await _speak(responses[text.length % responses.length]);
      return;
    }

    // 7i. General tips / help / capability queries
    if (text.contains('sleep tips')         ||
        text.contains('improve my sleep')    || text.contains('sleep better')        ||
        text.contains('how to sleep')        || text.contains('what can you')        ||
        text.contains('what you can')        || text.contains('what can i say')      ||
        text.contains('what can i ask')      || text.contains('tell me what you')    ||
        text.contains('what do you know')    || text.contains('what do you offer')   ||
        text.contains('what do you cover')   || text.contains('what else')           ||
        text.contains('what should i ask')   || text.contains('what topics')         ||
        text.contains('tell me what you can')|| text.contains('what can you give')   ||
        text.contains('what can you tell')   || text.contains('what can you help')   ||
        text.contains('features')            || text.contains('capabilities')        ||
        _hasWord(text, 'help')) {
      _consecutiveFallbacks = 0;
      final ack  = "Happy to help - here's what I can talk about.";
      final core = "Bedtime routines, trouble falling asleep, screen time, naps, sleep duration, your sleep environment, caffeine and alcohol, exercise, or melatonin.";
      final cta  = "You can also say 'go back' to head home, or ask for Breathing Exercises, Mindfulness, or Mood Tracking. What sounds good?";
      await _speak('$ack $core $cta');
      return;
    }

    if (text.contains('thank you')  || text.contains('thanks')     ||
        text.contains('thank u')    || text.contains('cheers')     ||
        _hasWord(text, 'ty')) {
      _consecutiveFallbacks = 0;
      final hour = DateTime.now().hour;
      final closing = (hour >= 18 || hour < 6) ? 'great sleep' : 'great day';
      await _speak("You're welcome! Have a $closing.");
      return;
    }

    if (text.contains('gotcha')        || text.contains('got it')      ||
        text.contains('i see')         || _hasWord(text, 'okay')       ||
        _hasWord(text, 'alright')      || _hasWord(text, 'ok')         ||
        text.contains('likewise')      || text.contains('same to you')) {
      _consecutiveFallbacks = 0;
      const responses = ["Great! Just ask whenever you're ready.",
        "Sounds good! What else can I help with?",
        "Perfect. I'm here if you need anything."];
      await _speak(responses[text.length % responses.length]);
      return;
    }

    // ── 8. Fallback ────────────────────────────────────────────────────────
    statusLabel = 'Waiting for input';
    notifyListeners();

    _consecutiveFallbacks++;

    if (_consecutiveFallbacks > 2) {
      _consecutiveFallbacks = 0;
      const msg =
          "I don't have anything on that one. Try asking about sleep tips, screen time, caffeine, or say 'help' to see what I can do.";
      chatHistory.add(const SleepMessage(msg, isUser: false));
      notifyListeners();
      await ttsService.speak(msg);
      await ttsService.awaitCompletion();
    } else {
      const msg =
          "Sorry, didn't catch that. Try asking about sleep tips, screen time, naps, or say 'help'.";
      chatHistory.add(const SleepMessage(msg, isUser: false));
      notifyListeners();
      await ttsService.speak("Sorry, didn't catch that. Could you say that again?");
      await ttsService.awaitCompletion();
    }
  }

  // ── Navigation helper ──────────────────────────────────────────────────────

  Future<void> _navigateTo(String route) async {
    if (_context == null || !_context!.mounted) return;
    Widget? page;
    String  msg  = '';
    switch (route) {
      case '/emergency':
        page = const EmergencySupportPage();
        msg  = 'Opening Emergency Support now.';
        break;
      case '/breathing':
        page = const BreathingExercisesPage();
        msg  = 'Opening Breathing Exercises for you now.';
        break;
      case '/mindfulness':
        page = const MindfulnessPage();
        msg  = 'Taking you to Mindfulness now.';
        break;
      case '/mood':
        page = const MoodTrackingPage();
        msg  = 'Opening Mood Tracking for you now.';
        break;
    }
    if (page != null) {
      chatHistory.add(SleepMessage(msg, isUser: false));
      notifyListeners();
      await ttsService.speak(msg);
      await ttsService.awaitCompletion();
      Navigator.push(_context!, MaterialPageRoute(builder: (_) => page!));
    }
  }

  // ── Dispose ────────────────────────────────────────────────────────────────

  @override
  void dispose() {
    ttsService.stop();
    sttService.cancel();
    super.dispose();
  }
}

// ── Message model ──────────────────────────────────────────────────────────────

class SleepMessage {
  final String text;
  final bool   isUser;
  const SleepMessage(this.text, {required this.isUser});
}

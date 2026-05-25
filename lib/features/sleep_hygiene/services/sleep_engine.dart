// sleep_engine.dart
// Polished rule-based engine + Riverpod notifier for the sleep module.
// Includes: semantic scoring, tone detection, context tracking,
// conversation history, repeat, follow-ups, and debug logging.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/sleep_content.dart';
import 'speech_to_text_service.dart';
import 'tts_service.dart';

// ════════════════════════════════════════════════════════════════
// 1. ENGINE  (pure Dart)
// ════════════════════════════════════════════════════════════════

class SleepEngine {
  // ── Gateway interface ────────────────────────────────────────
  String get moduleId => 'sleep';

  String get entryMessage =>
      "I'm your sleep assistant. Ask me about bedtime routines, "
          "what to do if you can't sleep, screen time, naps, "
          "sleep duration, or general sleep tips.";

  String get exitMessage =>
      'Sweet dreams! Come back any time you need sleep support.';

  // ── Internal context ─────────────────────────────────────────
  SleepIntent? _previousIntent;
  String _lastResponse = '';
  final List<IntentLog> _intentLog = [];

  // Public accessors for debug
  List<IntentLog> get intentLog => List.unmodifiable(_intentLog);
  SleepIntent? get previousIntent => _previousIntent;

  // ── Main entry point ─────────────────────────────────────────
  SleepResponse process(String input) {
    final text = _normalise(input);

    // Empty / no speech
    if (text.isEmpty) {
      return _staticResponse(
        "I didn't hear anything. Please tap the mic and speak clearly.",
        SleepIntent.unknown,
      );
    }

    // 1. Crisis — always first, no scoring needed
    if (_isCrisis(text)) {
      final msg = 'This sounds serious. Your safety comes first. '
          'I am connecting you to crisis support now.';
      _log(input, SleepIntent.unknown, 1.0, EmotionalTone.neutral);
      return SleepResponse(
        intent: SleepIntent.unknown,
        message: msg,
        isCrisis: true,
        confidence: 1.0,
      );
    }

    // 2. Handoff check
    final handoff = _checkHandoff(text);
    if (handoff != null) {
      final msg = _handoffMessage(handoff);
      _log(input, SleepIntent.unknown, 1.0, EmotionalTone.neutral);
      return SleepResponse(
        intent: SleepIntent.unknown,
        message: msg,
        handoffRoute: handoff,
        confidence: 1.0,
      );
    }

    // 3. Detect emotional tone
    final tone = _detectTone(text);

    // 4. Semantic scoring — score every intent
    final scores = _scoreAllIntents(text);
    final topIntent = scores.keys.first;
    final topScore = scores[topIntent]!;

    // Confidence: normalise raw score to 0–1 (cap at 5 keyword hits = 1.0)
    final confidence = (topScore / 5.0).clamp(0.0, 1.0);

    // 5. Log for debug
    _log(input, topIntent, confidence, tone);

    // 6. Handle meta-intents that need engine state
    if (topIntent == SleepIntent.repeat) {
      return _handleRepeat();
    }

    if (topIntent == SleepIntent.affirmation) {
      return _handleAffirmation();
    }

    if (topIntent == SleepIntent.negation) {
      return _handleNegation();
    }

    // 7. Below confidence threshold → unknown
    if (confidence < 0.1) {
      final msg = SleepCorpus.pick(
          SleepCorpus.responseVariants[SleepIntent.unknown]!);
      _lastResponse = msg;
      return SleepResponse(
        intent: SleepIntent.unknown,
        message: msg,
        confidence: confidence,
      );
    }

    // 8. Build full response
    final response = _buildResponse(topIntent, tone, confidence);
    _previousIntent = topIntent;
    _lastResponse = response.message;
    return response;
  }

  bool isDirectEntry(String input) => SleepCorpus.directEntryKeywords
      .any((kw) => _normalise(input).contains(kw));

  bool isExit(String input) => SleepCorpus.exitKeywords
      .any((kw) => _normalise(input).contains(kw));

  // ── Normalisation ────────────────────────────────────────────
  // Lowercase, trim, collapse whitespace, strip punctuation.
  String _normalise(String input) => input
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r"[^\w\s']"), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  // ── Crisis ───────────────────────────────────────────────────
  bool _isCrisis(String t) =>
      SleepCorpus.crisisKeywords.any((kw) => t.contains(kw));

  // ── Handoff ──────────────────────────────────────────────────
  String? _checkHandoff(String t) {
    for (final e in SleepCorpus.handoffTriggers.entries) {
      if (e.value.any((kw) => t.contains(kw))) return e.key;
    }
    return null;
  }

  // ── Tone detection ───────────────────────────────────────────
  EmotionalTone _detectTone(String t) {
    int best = 0;
    EmotionalTone result = EmotionalTone.neutral;
    for (final e in SleepCorpus.toneKeywords.entries) {
      final hits = e.value.where((kw) => t.contains(kw)).length;
      if (hits > best) {
        best = hits;
        result = e.key;
      }
    }
    return result;
  }

  // ── Semantic scoring ─────────────────────────────────────────
  // Count how many keywords from each intent appear in the input.
  // Returns intents sorted by score descending.
  Map<SleepIntent, int> _scoreAllIntents(String t) {
    final scores = <SleepIntent, int>{};
    for (final e in SleepCorpus.intentKeywords.entries) {
      final hits = e.value.where((kw) => t.contains(kw)).length;
      if (hits > 0) scores[e.key] = hits;
    }
    if (scores.isEmpty) return {SleepIntent.unknown: 0};

    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  // ── Meta-intent handlers ─────────────────────────────────────

  SleepResponse _handleRepeat() {
    if (_lastResponse.isEmpty) {
      return _staticResponse(
        "There's nothing to repeat yet. Ask me something first.",
        SleepIntent.repeat,
      );
    }
    return _staticResponse(_lastResponse, SleepIntent.repeat);
  }

  SleepResponse _handleAffirmation() {
    // If previous intent had a natural follow-up, continue it
    if (_previousIntent != null) {
      final followUp = _buildFollowUp(_previousIntent!);
      if (followUp != null) return followUp;
    }
    final msg = SleepCorpus.pick(
        SleepCorpus.responseVariants[SleepIntent.affirmation]!);
    _lastResponse = msg;
    return _staticResponse(msg, SleepIntent.affirmation);
  }

  SleepResponse _handleNegation() {
    final msg = SleepCorpus.pick(
        SleepCorpus.responseVariants[SleepIntent.negation]!);
    _lastResponse = msg;
    _previousIntent = null;
    return _staticResponse(msg, SleepIntent.negation);
  }

  // After affirmation, provide a deeper follow-up for some intents
  SleepResponse? _buildFollowUp(SleepIntent intent) {
    switch (intent) {
      case SleepIntent.cantSleep:
      // Suggest breathing handoff
        return SleepResponse(
          intent: SleepIntent.cantSleep,
          message: 'Would you like to try a breathing exercise? '
              'It can help calm your nervous system right now.',
          suggestions: const ['Yes, try breathing', 'Give me more tips', 'No thanks'],
          confidence: 1.0,
        );
      case SleepIntent.stressed:
        return SleepResponse(
          intent: SleepIntent.stressed,
          message: 'Since you\'re still stressed, I can walk you through '
              'box breathing or take you to the breathing module. '
              'Which would you prefer?',
          suggestions: const ['Box breathing', 'Breathing module', 'Something else'],
          confidence: 1.0,
        );
      default:
        return null;
    }
  }

  // ── Response builder ─────────────────────────────────────────
  SleepResponse _buildResponse(
      SleepIntent intent, EmotionalTone tone, double confidence) {

    // For emotional tone intents, map to their response content
    final effectiveIntent = _resolveEffectiveIntent(intent, tone);

    // Pick message
    final messages = SleepCorpus.intentMessages[effectiveIntent];
    String message = messages != null
        ? SleepCorpus.pick(messages)
        : SleepCorpus.pick(SleepCorpus.responseVariants[SleepIntent.unknown]!);

    // Prepend tone prefix if tone is non-neutral and intent is a content intent
    if (tone != EmotionalTone.neutral) {
      final prefixes = SleepCorpus.tonePrefixes[tone];
      if (prefixes != null) {
        message = SleepCorpus.pick(prefixes) + message;
      }
    }

    // Special cases: greeting, gratitude, help use responseVariants only
    if ([SleepIntent.greeting, SleepIntent.gratitude, SleepIntent.help]
        .contains(intent)) {
      message = SleepCorpus.pick(SleepCorpus.responseVariants[intent]!);
    }

    final tips = SleepCorpus.intentTips[effectiveIntent];
    final routineSteps = effectiveIntent == SleepIntent.bedtimeRoutine
        ? SleepCorpus.bedtimeRoutineSteps
        : null;
    final suggestions = SleepCorpus.followUpSuggestions[effectiveIntent];

    _lastResponse = message;

    return SleepResponse(
      intent: effectiveIntent,
      message: message,
      tone: tone,
      tips: tips,
      routineSteps: routineSteps,
      suggestions: suggestions,
      confidence: confidence,
    );
  }

  // Map emotional intents + cross-intent tone blending
  SleepIntent _resolveEffectiveIntent(SleepIntent intent, EmotionalTone tone) {
    // If intent is directly an emotional one, use it
    if ([SleepIntent.stressed, SleepIntent.tired, SleepIntent.frustrated]
        .contains(intent)) {
      return intent;
    }
    // If tone is strong and intent is generic, blend in tone
    if (tone == EmotionalTone.stressed && intent == SleepIntent.cantSleep) {
      return SleepIntent.stressed;
    }
    return intent;
  }

  // ── Helpers ──────────────────────────────────────────────────

  SleepResponse _staticResponse(String message, SleepIntent intent) {
    _lastResponse = message;
    return SleepResponse(
      intent: intent,
      message: message,
      confidence: 1.0,
    );
  }

  String _handoffMessage(String route) {
    switch (route) {
      case '/breathing':
        return 'That sounds like it would be better handled in the '
            'breathing module. Taking you there now.';
      case '/meditation':
        return 'A guided meditation sounds perfect. Taking you there now.';
      case '/psychoeducation':
        return 'Connecting you to the psychoeducation module now.';
      default:
        return 'Let me take you to the right place.';
    }
  }

  void _log(String input, SleepIntent intent, double confidence, EmotionalTone tone) {
    final entry = IntentLog(
      input: input,
      intent: intent,
      confidence: confidence,
      tone: tone,
    );
    _intentLog.add(entry);
    // ignore: avoid_print
    print(entry.toString());
  }
}

// ════════════════════════════════════════════════════════════════
// 2. VUI STATE + NOTIFIER
// ════════════════════════════════════════════════════════════════

enum SleepVuiStatus { idle, listening, processing, speaking, error }

class SleepVuiState {
  final SleepVuiStatus status;
  final List<ChatMessage> history;      // full conversation
  final List<SleepTip>? tips;
  final List<String>? routineSteps;
  final List<String>? suggestions;      // follow-up chips
  final String? errorMessage;
  final bool hasMicPermission;
  final String? pendingRoute;
  final SleepIntent? lastIntent;
  final double lastConfidence;

  const SleepVuiState({
    this.status = SleepVuiStatus.idle,
    this.history = const [],
    this.tips,
    this.routineSteps,
    this.suggestions,
    this.errorMessage,
    this.hasMicPermission = false,
    this.pendingRoute,
    this.lastIntent,
    this.lastConfidence = 0.0,
  });

  SleepVuiState copyWith({
    SleepVuiStatus? status,
    List<ChatMessage>? history,
    List<SleepTip>? tips,
    List<String>? routineSteps,
    List<String>? suggestions,
    String? errorMessage,
    bool? hasMicPermission,
    String? pendingRoute,
    SleepIntent? lastIntent,
    double? lastConfidence,
    bool clearCards = false,
    bool clearRoute = false,
  }) {
    return SleepVuiState(
      status: status ?? this.status,
      history: history ?? this.history,
      tips: clearCards ? null : (tips ?? this.tips),
      routineSteps: clearCards ? null : (routineSteps ?? this.routineSteps),
      suggestions: clearCards ? null : (suggestions ?? this.suggestions),
      errorMessage: errorMessage ?? this.errorMessage,
      hasMicPermission: hasMicPermission ?? this.hasMicPermission,
      pendingRoute: clearRoute ? null : (pendingRoute ?? this.pendingRoute),
      lastIntent: lastIntent ?? this.lastIntent,
      lastConfidence: lastConfidence ?? this.lastConfidence,
    );
  }

  // Convenience: add a message to history immutably
  SleepVuiState withMessage(ChatMessage msg) =>
      copyWith(history: [...history, msg]);
}

// ── Notifier ─────────────────────────────────────────────────────

class SleepVuiNotifier extends StateNotifier<SleepVuiState> {
  final SleepEngine _engine;
  final SpeechToTextService _stt;
  final TtsService _tts;

  SleepVuiNotifier(this._engine, this._stt, this._tts)
      : super(const SleepVuiState()) {
    _init();
  }

  Future<void> _init() async {
    final micStatus = await Permission.microphone.status;
    state = state.copyWith(hasMicPermission: micStatus.isGranted);

    try {
      await _tts.initialise();
      await _tts.speak(_engine.entryMessage);
    } catch (_) {}

    // Add entry message to history
    state = state.withMessage(ChatMessage(
      isUser: false,
      text: _engine.entryMessage,
    ));
    state = state.copyWith(status: SleepVuiStatus.idle);
  }

  // ── Voice turn ───────────────────────────────────────────────
  Future<void> startVoiceTurn() async {
    if (!state.hasMicPermission) {
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        state = state.copyWith(
          status: SleepVuiStatus.error,
          errorMessage: 'Microphone permission is required for voice input.',
        );
        return;
      }
      state = state.copyWith(hasMicPermission: true);
    }

    // Interrupt TTS if speaking
    await _tts.stop();

    state = state.copyWith(
      status: SleepVuiStatus.listening,
      errorMessage: null,
    );

    String userText;
    try {
      userText = await _stt.listen();
    } catch (e) {
      state = state.copyWith(
        status: SleepVuiStatus.error,
        errorMessage: e.toString().replaceFirst('SpeechException: ', ''),
      );
      return;
    }

    await _handleInput(userText, isVoice: true);
  }

  // ── Text fallback ────────────────────────────────────────────
  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _handleInput(text.trim(), isVoice: false);
  }

  // ── Suggestion chip tapped ───────────────────────────────────
  Future<void> sendSuggestion(String suggestion) async {
    await sendTextMessage(suggestion);
  }

  Future<void> stopListening() async {
    await _stt.stop();
    state = state.copyWith(status: SleepVuiStatus.idle);
  }

  void clearPendingRoute() => state = state.copyWith(clearRoute: true);

  // ── Core input handler ───────────────────────────────────────
  Future<void> _handleInput(String input, {required bool isVoice}) async {
    // Add user message to history
    state = state
        .withMessage(ChatMessage(isUser: true, text: input))
        .copyWith(status: SleepVuiStatus.processing, clearCards: true);

    final engineResponse = _engine.process(input);

    // Navigation: crisis or handoff
    if (engineResponse.isCrisis || engineResponse.handoffRoute != null) {
      final route = engineResponse.isCrisis
          ? '/crisis'
          : engineResponse.handoffRoute!;

      state = state
          .withMessage(ChatMessage(
        isUser: false,
        text: engineResponse.message,
        intent: engineResponse.intent,
        confidence: engineResponse.confidence,
      ))
          .copyWith(
        status: SleepVuiStatus.speaking,
        pendingRoute: route,
        clearCards: true,
      );

      await _tts.speak(engineResponse.message);
      state = state.copyWith(status: SleepVuiStatus.idle);
      return;
    }

    // Normal response
    state = state
        .withMessage(ChatMessage(
      isUser: false,
      text: engineResponse.message,
      intent: engineResponse.intent,
      confidence: engineResponse.confidence,
    ))
        .copyWith(
      status: SleepVuiStatus.speaking,
      tips: engineResponse.tips,
      routineSteps: engineResponse.routineSteps,
      suggestions: engineResponse.suggestions,
      lastIntent: engineResponse.intent,
      lastConfidence: engineResponse.confidence,
    );

    await _tts.speak(engineResponse.message);
    state = state.copyWith(status: SleepVuiStatus.idle);
  }
}

// ════════════════════════════════════════════════════════════════
// 3. PROVIDERS
// ════════════════════════════════════════════════════════════════

final speechToTextServiceProvider =
Provider<SpeechToTextService>((_) => SpeechToTextService());

final ttsServiceProvider =
Provider<TtsService>((_) => TtsService());

final sleepEngineProvider =
Provider<SleepEngine>((_) => SleepEngine());

final sleepVuiNotifierProvider =
StateNotifierProvider<SleepVuiNotifier, SleepVuiState>(
      (ref) => SleepVuiNotifier(
    ref.read(sleepEngineProvider),
    ref.read(speechToTextServiceProvider),
    ref.read(ttsServiceProvider),
  ),
);
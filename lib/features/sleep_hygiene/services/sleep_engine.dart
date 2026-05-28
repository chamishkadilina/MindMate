// sleep_engine.dart
// Polished rule-based engine + Riverpod notifier for the sleep module.
//
// IMPROVEMENTS APPLIED vs original:
//  1. Negation-aware scoring   — keywords following a negation prefix
//                                are discounted (score × 0) for that intent.
//  2. Input length normalisation — raw hit count is divided by √(wordCount)
//                                  so short precise inputs beat long rambling ones.
//  3. History-influenced scoring — the previous intent gets a +1 recency boost,
//                                  keeping the conversation contextually coherent.
//  4. Synonym expansion        — applied in _normalise() via SleepCorpus.synonymMap
//                                before any scoring; all variants collapse to their
//                                canonical form automatically.
//  5. N-gram matching          — bigrams (×2) and trigrams (×3) are scored
//                                separately from unigrams and merged, so precise
//                                multi-word phrases dominate accidental hits.

import 'dart:math';

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

  // Public accessors for debug / testing
  List<IntentLog> get intentLog => List.unmodifiable(_intentLog);
  SleepIntent? get previousIntent => _previousIntent;

  // ── Main entry point ─────────────────────────────────────────
  SleepResponse process(String input, {String context = ''}) {

    // IMPROVEMENT 4: synonym expansion happens inside _normalise()
    final text = _normalise(input);
    final contextText = context.isNotEmpty ? _normalise(context) : '';

    // Empty / no speech
    if (text.isEmpty) {
      return _staticResponse(
        "I didn't hear anything. Please tap the mic and speak clearly.",
        SleepIntent.unknown,
      );
    }

    // 1. Crisis — always first, no scoring needed
    if (_isCrisis(text)) {
      const msg = 'This sounds serious. Your safety comes first. '
          'I am connecting you to crisis support now.';
      _log(input, SleepIntent.unknown, 1.0, EmotionalTone.neutral);
      return const SleepResponse(
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

    // 3. Detect emotional tone (uses expanded/normalised text)
    final tone = _detectTone(text);

    // 4. Full scoring pipeline (all 5 improvements feed in here)
    final scores = _scoreAllIntents(text);
    final topIntent = scores.keys.first;
    final topScore = scores[topIntent]!;

    // Confidence: normalise to 0–1; cap at 5.0 weighted score = 1.0
    final confidence = (topScore / 5.0).clamp(0.0, 1.0);

    // 5. Log for debug
    _log(input, topIntent, confidence, tone);

    // 6. Handle meta-intents that need engine state
    if (topIntent == SleepIntent.repeat) return _handleRepeat();
    if (topIntent == SleepIntent.affirmation) return _handleAffirmation();
    if (topIntent == SleepIntent.negation) return _handleNegation();

    // 7. IMPROVEMENT 2 (single-word inputs): lower threshold for 1-token queries
    final wordCount = text.split(' ').length;
    final threshold = wordCount == 1 ? 0.05 : 0.10;

    if (confidence < threshold) {
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

  // ════════════════════════════════════════════════════════════════
  // IMPROVEMENT 4 — SYNONYM EXPANSION
  // Replaces every synonym with its canonical form so the rest of
  // the engine only needs to know canonical words.
  // ════════════════════════════════════════════════════════════════
  String _normalise(String input) {
    // Step 1: lowercase, trim, strip punctuation, collapse whitespace
    String text = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    // Step 2: apply synonym map (longest match first to avoid partial clobbers)
    final sortedSynonyms = SleepCorpus.synonymMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    for (final synonym in sortedSynonyms) {
      if (text.contains(synonym)) {
        text = text.replaceAll(synonym, SleepCorpus.synonymMap[synonym]!);
      }
    }

    // Strip question framing before scoring
    text = _stripQuestionFrame(text);

    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  // ── Question frame stripping ──────────────────────────────────
  // IMPROVEMENT: strips conversational question wrappers before scoring
  // so "how can you give me tips" reduces to "tips" for clean intent match.
  static const List<String> _questionFrames = [
    'how can you give me',
    'how can i get',
    'can you give me',
    'can you show me',
    'can you tell me',
    'could you give me',
    'would you give me',
    'do you have any',
    'give me some',
    'show me some',
    'tell me some',
    'what are some',
    'how do i get',
    'how to get',
    'i want to know about',
    'i would like to know',
    'i need help with',
    'help me with',
    'help me understand',
  ];

  String _stripQuestionFrame(String text) {
    final sorted = List<String>.from(_questionFrames)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final frame in sorted) {
      if (text.startsWith(frame)) {
        return text.substring(frame.length).trim();
      }
      text = text.replaceAll(frame, '').trim();
    }
    return text;
  }


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

  // ════════════════════════════════════════════════════════════════
  // IMPROVEMENT 1 — NEGATION-AWARE SCORING
  // Returns true if the keyword appears immediately after a negation
  // prefix in the text, meaning the user is explicitly rejecting it.
  // ════════════════════════════════════════════════════════════════
  bool _isNegated(String text, String keyword) {
    for (final prefix in SleepCorpus.negationPrefixes) {
      // Check if "<prefix> <keyword>" or "<prefix> ... <keyword>" within 4 words
      final prefixIdx = text.indexOf(prefix);
      if (prefixIdx == -1) continue;

      final afterPrefix = text.substring(prefixIdx + prefix.length).trim();
      final wordsAfter = afterPrefix.split(' ').take(4).join(' ');
      if (wordsAfter.contains(keyword)) return true;
    }
    return false;
  }

  // ════════════════════════════════════════════════════════════════
  // IMPROVEMENT 2 + 3 + 5 — UNIFIED SCORING PIPELINE
  //
  //  Step A: Score unigrams (weight ×1), with negation discounting.
  //  Step B: Score bigrams  (weight ×2), with negation discounting.
  //  Step C: Score trigrams (weight ×3), with negation discounting.
  //  Step D: Apply input-length normalisation  ÷ √(wordCount).
  //  Step E: Apply history recency boost       +1 to _previousIntent.
  //  Step F: Sort descending and return.
  // ════════════════════════════════════════════════════════════════
  Map<SleepIntent, double> _scoreAllIntents(String text, {String contextText = ''}) {
    final scores = <SleepIntent, double>{};
    final wordCount = text.split(' ').length.clamp(1, 999);

    // ── Step A: Unigrams (weight 1) ──────────────────────────────
    for (final entry in SleepCorpus.intentKeywords.entries) {
      double intentScore = 0;
      for (final kw in entry.value) {
        if (!text.contains(kw)) continue;
        // IMPROVEMENT 1: skip if negated
        if (_isNegated(text, kw)) continue;
        intentScore += 1.0;
      }
      if (intentScore > 0) {
        scores[entry.key] = (scores[entry.key] ?? 0) + intentScore;
      }
    }

    // ── Step B: Bigrams (weight 2) ───────────────────────────────
    for (final entry in SleepCorpus.bigrams.entries) {
      double intentScore = 0;
      for (final kw in entry.value) {
        if (!text.contains(kw)) continue;
        if (_isNegated(text, kw)) continue;
        intentScore += 2.0; // IMPROVEMENT 5: bigram weight
      }
      if (intentScore > 0) {
        scores[entry.key] = (scores[entry.key] ?? 0) + intentScore;
      }
    }

    // ── Step C: Trigrams (weight 3) ──────────────────────────────
    for (final entry in SleepCorpus.trigrams.entries) {
      double intentScore = 0;
      for (final kw in entry.value) {
        if (!text.contains(kw)) continue;
        if (_isNegated(text, kw)) continue;
        intentScore += 3.0; // IMPROVEMENT 5: trigram weight
      }
      if (intentScore > 0) {
        scores[entry.key] = (scores[entry.key] ?? 0) + intentScore;
      }
    }

    if (scores.isEmpty) return {SleepIntent.unknown: 0.0};

    // ── Step D: Input-length normalisation ───────────────────────
    // IMPROVEMENT 2: divide by √(wordCount) so long inputs don't
    // win purely by having more words that accidentally match.
    final normFactor = sqrt(wordCount.toDouble());
    final normScores = scores.map(
          (intent, raw) => MapEntry(intent, raw / normFactor),
    );

    // ── Step E: History recency boost ────────────────────────────
    // IMPROVEMENT 3: give the previously matched intent a small
    // contextual nudge (+1 raw point before normalisation equivalent).
    if (_previousIntent != null && normScores.containsKey(_previousIntent)) {
      normScores[_previousIntent!] =
          normScores[_previousIntent!]! + (1.0 / normFactor);
    }

    // ── Step F: Multi-turn context scoring (weight 0.3×) ─────────
    // Scores the last 3 user turns at reduced weight and merges
    // into current scores so conversation history influences intent.
    if (contextText.isNotEmpty) {
      final contextWordCount =
      contextText.split(' ').length.clamp(1, 999);
      final contextNormFactor = sqrt(contextWordCount.toDouble());

      // Unigrams from context
      for (final entry in SleepCorpus.intentKeywords.entries) {
        double ctxScore = 0;
        for (final kw in entry.value) {
          if (!contextText.contains(kw)) continue;
          if (_isNegated(contextText, kw)) continue;
          ctxScore += 1.0;
        }
        if (ctxScore > 0) {
          final normalised = (ctxScore / contextNormFactor) * 0.3;
          normScores[entry.key] =
              (normScores[entry.key] ?? 0) + normalised;
        }
      }

      // Bigrams from context
      for (final entry in SleepCorpus.bigrams.entries) {
        double ctxScore = 0;
        for (final kw in entry.value) {
          if (!contextText.contains(kw)) continue;
          if (_isNegated(contextText, kw)) continue;
          ctxScore += 2.0;
        }
        if (ctxScore > 0) {
          final normalised = (ctxScore / contextNormFactor) * 0.3;
          normScores[entry.key] =
              (normScores[entry.key] ?? 0) + normalised;
        }
      }

      // Trigrams from context
      for (final entry in SleepCorpus.trigrams.entries) {
        double ctxScore = 0;
        for (final kw in entry.value) {
          if (!contextText.contains(kw)) continue;
          if (_isNegated(contextText, kw)) continue;
          ctxScore += 3.0;
        }
        if (ctxScore > 0) {
          final normalised = (ctxScore / contextNormFactor) * 0.3;
          normScores[entry.key] =
              (normScores[entry.key] ?? 0) + normalised;
        }
      }
    }

    // ── Step F: Sort descending ───────────────────────────────────
    final sorted = normScores.entries.toList()
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

  SleepResponse? _buildFollowUp(SleepIntent intent) {
    switch (intent) {
      case SleepIntent.cantSleep:
        return const SleepResponse(
          intent: SleepIntent.cantSleep,
          message: 'Would you like to try a breathing exercise? '
              'It can help calm your nervous system right now.',
          suggestions: ['Yes, try breathing', 'Give me more tips', 'No thanks'],
          confidence: 1.0,
        );
      case SleepIntent.stressed:
        return const SleepResponse(
          intent: SleepIntent.stressed,
          message: "Since you're still stressed, I can walk you through "
              'box breathing or take you to the breathing module. '
              'Which would you prefer?',
          suggestions: ['Box breathing', 'Breathing module', 'Something else'],
          confidence: 1.0,
        );
      default:
        return null;
    }
  }

  // ── Response builder ─────────────────────────────────────────
  SleepResponse _buildResponse(
      SleepIntent intent,
      EmotionalTone tone,
      double confidence,
      ) {
    final effectiveIntent = _resolveEffectiveIntent(intent, tone);

    final messages = SleepCorpus.intentMessages[effectiveIntent];
    String message = messages != null
        ? SleepCorpus.pick(messages)
        : SleepCorpus.pick(
        SleepCorpus.responseVariants[SleepIntent.unknown]!);

    // Prepend tone prefix for emotional context
    if (tone != EmotionalTone.neutral) {
      final prefixes = SleepCorpus.tonePrefixes[tone];
      if (prefixes != null) {
        message = SleepCorpus.pick(prefixes) + message;
      }
    }

    // Greeting / gratitude / help use responseVariants only
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

  SleepIntent _resolveEffectiveIntent(SleepIntent intent, EmotionalTone tone) {
    if ([SleepIntent.stressed, SleepIntent.tired, SleepIntent.frustrated]
        .contains(intent)) {
      return intent;
    }
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

  void _log(
      String input,
      SleepIntent intent,
      double confidence,
      EmotionalTone tone,
      ) {
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
  final List<ChatMessage> history;
  final List<SleepTip>? tips;
  final List<String>? routineSteps;
  final List<String>? suggestions;
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
    state = state
        .withMessage(ChatMessage(isUser: true, text: input))
        .copyWith(status: SleepVuiStatus.processing, clearCards: true);

    // Build context string from last 3 user messages (excluding current)
    final recentContext = state.history
        .where((m) => m.isUser)
        .toList()
        .reversed
        .skip(1)          // skip current turn already added above
        .take(3)
        .map((m) => m.text)
        .join(' ');

    final engineResponse = _engine.process(input, context: recentContext);

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
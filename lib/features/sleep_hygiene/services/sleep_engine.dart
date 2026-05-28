// lib/features/sleep_hygiene/services/sleep_engine.dart
// Polished rule-based engine + Riverpod notifier for the sleep module.

import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/constants/sleep_content.dart';
import 'speech_to_text_service.dart';
import '../../../core/services/tts_service.dart';

// ════════════════════════════════════════════════════════════════
// 1. ENGINE  (pure Dart — unchanged)
// ════════════════════════════════════════════════════════════════

class SleepEngine {
  String get moduleId => 'sleep';

  // Keys for entry/exit — notifier uses tts.speak(key)
  String get entryKey  => 'sleep.entry';
  String get exitKey   => 'sleep.exit';

  SleepIntent? _previousIntent;
  String _lastResponse = '';
  String? _lastResponseKey;
  final List<IntentLog> _intentLog = [];

  List<IntentLog> get intentLog => List.unmodifiable(_intentLog);
  SleepIntent? get previousIntent => _previousIntent;

  SleepResponse process(String input, {String context = ''}) {
    final text = _normalise(input);
    final contextText = context.isNotEmpty ? _normalise(context) : '';

    if (text.isEmpty) {
      return SleepResponse(
        intent: SleepIntent.unknown,
        message: SleepCorpus.all['sleep.noInput']!,
        voiceKey: 'sleep.noInput',
        confidence: 1.0,
      );
    }

    if (_isCrisis(text)) {
      _log(input, SleepIntent.unknown, 1.0, EmotionalTone.neutral);
      return SleepResponse(
        intent: SleepIntent.unknown,
        message: SleepCorpus.all['sleep.crisis']!,
        voiceKey: 'sleep.crisis',
        isCrisis: true,
        confidence: 1.0,
      );
    }

    final handoff = _checkHandoff(text);
    if (handoff != null) {
      final key = _handoffKey(handoff);
      _log(input, SleepIntent.unknown, 1.0, EmotionalTone.neutral);
      return SleepResponse(
        intent: SleepIntent.unknown,
        message: SleepCorpus.all[key]!,
        voiceKey: key,
        handoffRoute: handoff,
        confidence: 1.0,
      );
    }

    final tone   = _detectTone(text);
    final scores = _scoreAllIntents(text, contextText: contextText);
    final topIntent = scores.keys.first;
    final topScore  = scores[topIntent]!;
    final confidence = (topScore / 5.0).clamp(0.0, 1.0);

    _log(input, topIntent, confidence, tone);

    if (topIntent == SleepIntent.repeat)      return _handleRepeat();
    if (topIntent == SleepIntent.affirmation) return _handleAffirmation();
    if (topIntent == SleepIntent.negation)    return _handleNegation();

    final wordCount = text.split(' ').length;
    final threshold = wordCount == 1 ? 0.05 : 0.10;

    if (confidence < threshold) {
      final key = SleepCorpus.pickKey('sleep.unknown');
      final msg = SleepCorpus.all[key]!;
      _lastResponse    = msg;
      _lastResponseKey = key;
      return SleepResponse(
        intent: SleepIntent.unknown,
        message: msg,
        voiceKey: key,
        confidence: confidence,
      );
    }

    final response = _buildResponse(topIntent, tone, confidence);
    _previousIntent  = topIntent;
    _lastResponse    = response.message;
    _lastResponseKey = response.voiceKey;
    return response;
  }

  bool isDirectEntry(String input) => SleepCorpus.directEntryKeywords
      .any((kw) => _normalise(input).contains(kw));

  bool isExit(String input) => SleepCorpus.exitKeywords
      .any((kw) => _normalise(input).contains(kw));

  // ── Normalisation ─────────────────────────────────────────────
  String _normalise(String input) {
    String text = input
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r"[^\w\s']"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    final sortedSynonyms = SleepCorpus.synonymMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final s in sortedSynonyms) {
      if (text.contains(s)) {
        text = text.replaceAll(s, SleepCorpus.synonymMap[s]!);
      }
    }
    text = _stripQuestionFrame(text);
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static const List<String> _questionFrames = [
    'how can you give me', 'how can i get', 'can you give me',
    'can you show me', 'can you tell me', 'could you give me',
    'would you give me', 'do you have any', 'give me some',
    'show me some', 'tell me some', 'what are some', 'how do i get',
    'how to get', 'i want to know about', 'i would like to know',
    'i need help with', 'help me with', 'help me understand',
  ];

  String _stripQuestionFrame(String text) {
    final sorted = List<String>.from(_questionFrames)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final frame in sorted) {
      if (text.startsWith(frame)) return text.substring(frame.length).trim();
      text = text.replaceAll(frame, '').trim();
    }
    return text;
  }

  // ── Crisis / handoff ──────────────────────────────────────────
  bool _isCrisis(String t) =>
      SleepCorpus.crisisKeywords.any((kw) => t.contains(kw));

  String? _checkHandoff(String t) {
    for (final e in SleepCorpus.handoffTriggers.entries) {
      if (e.value.any((kw) => t.contains(kw))) return e.key;
    }
    return null;
  }

  String _handoffKey(String route) {
    switch (route) {
      case '/breathing':       return 'sleep.handoff.breathing';
      case '/meditation':      return 'sleep.handoff.meditation';
      case '/psychoeducation': return 'sleep.handoff.psychoeducation';
      default:                 return 'sleep.handoff.default';
    }
  }

  // ── Tone detection ────────────────────────────────────────────
  EmotionalTone _detectTone(String t) {
    int best = 0;
    EmotionalTone result = EmotionalTone.neutral;
    for (final e in SleepCorpus.toneKeywords.entries) {
      final hits = e.value.where((kw) => t.contains(kw)).length;
      if (hits > best) { best = hits; result = e.key; }
    }
    return result;
  }

  // ── Negation check ────────────────────────────────────────────
  bool _isNegated(String text, String keyword) {
    for (final prefix in SleepCorpus.negationPrefixes) {
      final idx = text.indexOf(prefix);
      if (idx == -1) continue;
      final after = text.substring(idx + prefix.length).trim();
      if (after.split(' ').take(4).join(' ').contains(keyword)) return true;
    }
    return false;
  }

  // ── Scoring pipeline ──────────────────────────────────────────
  Map<SleepIntent, double> _scoreAllIntents(String text,
      {String contextText = ''}) {
    final scores    = <SleepIntent, double>{};
    final wordCount = text.split(' ').length.clamp(1, 999);

    void addScore(Map<SleepIntent, List<String>> map, double weight) {
      for (final e in map.entries) {
        double s = 0;
        for (final kw in e.value) {
          if (!text.contains(kw) || _isNegated(text, kw)) continue;
          s += weight;
        }
        if (s > 0) scores[e.key] = (scores[e.key] ?? 0) + s;
      }
    }

    addScore(SleepCorpus.intentKeywords, 1.0);
    addScore(SleepCorpus.bigrams,  2.0);
    addScore(SleepCorpus.trigrams, 3.0);

    if (scores.isEmpty) return {SleepIntent.unknown: 0.0};

    final normFactor = sqrt(wordCount.toDouble());
    final norm = scores.map((i, v) => MapEntry(i, v / normFactor));

    if (_previousIntent != null && norm.containsKey(_previousIntent)) {
      norm[_previousIntent!] = norm[_previousIntent!]! + (1.0 / normFactor);
    }

    if (contextText.isNotEmpty) {
      final ctxFactor = sqrt(contextText.split(' ').length.clamp(1, 999).toDouble());
      void addCtx(Map<SleepIntent, List<String>> map, double w) {
        for (final e in map.entries) {
          double s = 0;
          for (final kw in e.value) {
            if (!contextText.contains(kw) || _isNegated(contextText, kw)) continue;
            s += w;
          }
          if (s > 0) norm[e.key] = (norm[e.key] ?? 0) + (s / ctxFactor) * 0.3;
        }
      }
      addCtx(SleepCorpus.intentKeywords, 1.0);
      addCtx(SleepCorpus.bigrams,  2.0);
      addCtx(SleepCorpus.trigrams, 3.0);
    }

    final sorted = norm.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Map.fromEntries(sorted);
  }

  // ── Meta-intent handlers ──────────────────────────────────────

  SleepResponse _handleRepeat() {
    if (_lastResponse.isEmpty) {
      return SleepResponse(
        intent: SleepIntent.repeat,
        message: SleepCorpus.all['sleep.nothingToRepeat']!,
        voiceKey: 'sleep.nothingToRepeat',
        confidence: 1.0,
      );
    }
    return SleepResponse(
      intent: SleepIntent.repeat,
      message: _lastResponse,
      voiceKey: _lastResponseKey,
      confidence: 1.0,
    );
  }

  SleepResponse _handleAffirmation() {
    if (_previousIntent != null) {
      final followUp = _buildFollowUp(_previousIntent!);
      if (followUp != null) return followUp;
    }
    final key = SleepCorpus.pickKey('sleep.affirmation');
    final msg = SleepCorpus.all[key]!;
    _lastResponse    = msg;
    _lastResponseKey = key;
    return SleepResponse(
      intent: SleepIntent.affirmation,
      message: msg,
      voiceKey: key,
      confidence: 1.0,
    );
  }

  SleepResponse _handleNegation() {
    final key = SleepCorpus.pickKey('sleep.negation');
    final msg = SleepCorpus.all[key]!;
    _lastResponse    = msg;
    _lastResponseKey = key;
    _previousIntent  = null;
    return SleepResponse(
      intent: SleepIntent.negation,
      message: msg,
      voiceKey: key,
      confidence: 1.0,
    );
  }

  SleepResponse? _buildFollowUp(SleepIntent intent) {
    switch (intent) {
      case SleepIntent.cantSleep:
        return SleepResponse(
          intent: SleepIntent.cantSleep,
          message: SleepCorpus.all['sleep.cantSleep.followUp']!,
          voiceKey: 'sleep.cantSleep.followUp',
          suggestions: ['Yes, try breathing', 'Give me more tips', 'No thanks'],
          confidence: 1.0,
        );
      case SleepIntent.stressed:
        return SleepResponse(
          intent: SleepIntent.stressed,
          message: SleepCorpus.all['sleep.stressed.followUp']!,
          voiceKey: 'sleep.stressed.followUp',
          suggestions: ['Box breathing', 'Breathing module', 'Something else'],
          confidence: 1.0,
        );
      default:
        return null;
    }
  }

  // ── Response builder ──────────────────────────────────────────
  SleepResponse _buildResponse(
      SleepIntent intent, EmotionalTone tone, double confidence) {
    final effectiveIntent = _resolveEffectiveIntent(intent, tone);

    String? voiceKey;
    String message;

    // Greeting / gratitude / help use responseVariants
    if ([SleepIntent.greeting, SleepIntent.gratitude, SleepIntent.help]
        .contains(intent)) {
      final prefix = SleepCorpus.intentKeyPrefix[intent]!;
      voiceKey = SleepCorpus.pickKey(prefix);
      message  = SleepCorpus.all[voiceKey]!;
    } else {
      final prefix = SleepCorpus.intentKeyPrefix[effectiveIntent];
      if (prefix != null) {
        voiceKey = SleepCorpus.pickKey(prefix);
        message  = SleepCorpus.all[voiceKey]!;
      } else {
        voiceKey = SleepCorpus.pickKey('sleep.unknown');
        message  = SleepCorpus.all[voiceKey]!;
      }

      // Tone prefix — concatenate raw text; voiceKey becomes null (speakRaw fallback)
      if (tone != EmotionalTone.neutral) {
        final prefixes = SleepCorpus.tonePrefixes[tone];
        if (prefixes != null) {
          message  = SleepCorpus.pick(prefixes) + message;
          voiceKey = null; // dynamic concat → speakRaw
        }
      }
    }

    final tips         = SleepCorpus.intentTips[effectiveIntent];
    final routineSteps = effectiveIntent == SleepIntent.bedtimeRoutine
        ? SleepCorpus.bedtimeRoutineSteps
        : null;
    final suggestions  = SleepCorpus.followUpSuggestions[effectiveIntent];

    return SleepResponse(
      intent: effectiveIntent,
      message: message,
      voiceKey: voiceKey,
      tone: tone,
      tips: tips,
      routineSteps: routineSteps,
      suggestions: suggestions,
      confidence: confidence,
    );
  }

  SleepIntent _resolveEffectiveIntent(SleepIntent intent, EmotionalTone tone) {
    if ([SleepIntent.stressed, SleepIntent.tired, SleepIntent.frustrated]
        .contains(intent)) return intent;
    if (tone == EmotionalTone.stressed && intent == SleepIntent.cantSleep) {
      return SleepIntent.stressed;
    }
    return intent;
  }

  void _log(String input, SleepIntent intent, double confidence,
      EmotionalTone tone) {
    final entry = IntentLog(
        input: input, intent: intent, confidence: confidence, tone: tone);
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
  final bool isExiting;

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
    this.isExiting = false,
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
    bool? isExiting,
    bool clearCards = false,
    bool clearRoute = false,
  }) {
    return SleepVuiState(
      status: status ?? this.status,
      history: history ?? this.history,
      isExiting: isExiting ?? this.isExiting,
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

// ── Notifier ──────────────────────────────────────────────────────────────────

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
      await _tts.speak(_engine.entryKey);         // ← key, not raw text
    } catch (_) {}

    state = state.withMessage(ChatMessage(
      isUser: false,
      text: SleepCorpus.all[_engine.entryKey]!,
    ));
    state = state.copyWith(status: SleepVuiStatus.idle);
  }

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
    state = state.copyWith(status: SleepVuiStatus.listening, errorMessage: null);

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

  Future<void> sendTextMessage(String text) async {
    if (text.trim().isEmpty) return;
    await _tts.stop();
    await _handleInput(text.trim(), isVoice: false);
  }

  Future<void> sendSuggestion(String suggestion) =>
      sendTextMessage(suggestion);

  Future<void> stopListening() async {
    await _stt.stop();
    state = state.copyWith(status: SleepVuiStatus.idle);
  }

  void clearPendingRoute() => state = state.copyWith(clearRoute: true);

  // ── Core input handler ────────────────────────────────────────
  Future<void> _handleInput(String input, {required bool isVoice}) async {
    if (_engine.isExit(input)) {
      await _tts.speak(_engine.exitKey);           // ← key, not raw text
      state = state.copyWith(isExiting: true);
      return;
    }

    state = state
        .withMessage(ChatMessage(isUser: true, text: input))
        .copyWith(status: SleepVuiStatus.processing, clearCards: true);

    final recentContext = state.history
        .where((m) => m.isUser)
        .toList()
        .reversed
        .skip(1)
        .take(3)
        .map((m) => m.text)
        .join(' ');

    final response = _engine.process(input, context: recentContext);

    if (response.isCrisis || response.handoffRoute != null) {
      final route = response.isCrisis ? '/crisis' : response.handoffRoute!;

      state = state
          .withMessage(ChatMessage(
        isUser: false,
        text: response.message,
        intent: response.intent,
        confidence: response.confidence,
      ))
          .copyWith(
        status: SleepVuiStatus.speaking,
        pendingRoute: route,
        clearCards: true,
      );

      await _speak(response);
      state = state.copyWith(status: SleepVuiStatus.idle);
      return;
    }

    state = state
        .withMessage(ChatMessage(
      isUser: false,
      text: response.message,
      intent: response.intent,
      confidence: response.confidence,
    ))
        .copyWith(
      status: SleepVuiStatus.speaking,
      tips: response.tips,
      routineSteps: response.routineSteps,
      suggestions: response.suggestions,
      lastIntent: response.intent,
      lastConfidence: response.confidence,
    );

    await _speak(response);
    state = state.copyWith(status: SleepVuiStatus.idle);
  }

  /// Dispatch to tts.speak(key) when key exists, speakRaw(text) otherwise.
  Future<void> _speak(SleepResponse response) async {
    if (response.voiceKey != null) {
      await _tts.speak(response.voiceKey!);
    } else {
      await _tts.speakRaw(response.message);
    }
  }
}

// ════════════════════════════════════════════════════════════════
// 3. PROVIDERS
// ════════════════════════════════════════════════════════════════

final speechToTextServiceProvider =
Provider<SpeechToTextService>((_) => SpeechToTextService());

final ttsServiceProvider =
Provider<TtsService>((_) => TtsService.instance);

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
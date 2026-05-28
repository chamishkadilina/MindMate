// lib/home_page.dart

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mindmate/core/services/tts_service.dart';
import 'package:mindmate/features/breathing_exercises/screens/breathing_exercises_page.dart';
import 'package:mindmate/features/emergency_support/screens/emergency_support_page.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import 'features/mindfulness/screens/mindfulness_page.dart';
import 'features/mood_tracking/screens/mood_tracking_page.dart';
import 'features/sleep_hygiene/screens/sleep_vui_screen.dart';

// ── Instruction steps shown one at a time, fading in/out ──────────────────────
const List<String> _kInstructions = [
  'Say "Breathing" to open Breathing Exercises',
  'Say "Sleep" for Sleep Hygiene tips',
  'Say "Mindfulness" to begin a session',
  'Say "Mood" to track how you feel',
  'Say "Emergency" for immediate support',
];

// Matching voice keys — spoken once in order, then silent
const List<String> _kInstructionKeys = [
  'home.instruction.0',
  'home.instruction.1',
  'home.instruction.2',
  'home.instruction.3',
  'home.instruction.4',
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  final TtsService _tts = TtsService();
  final stt.SpeechToText _stt = stt.SpeechToText();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isListening = false;
  bool _sttAvailable = false;
  bool _isNavigating = false;
  String _recognizedText = '';

  // ── Warm-up / instruction state ────────────────────────────────────────────
  // phases: 'warmingUp' | 'ready'
  String _phase = 'warmingUp';
  int _instructionIndex = 0;
  bool _instructionVisible = false;

  // Whether the one-time voice cycle is still running
  bool _voiceCycleDone = false;

  Timer? _instructionTimer;
  final Duration _fadeDuration = const Duration(milliseconds: 700);

  // ── Pulse animation (mic) ──────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initStt();
    _runIntroSequence();
  }

  // ── Intro sequence ────────────────────────────────────────────────────────
  Future<void> _runIntroSequence() async {
    setState(() => _phase = 'warmingUp');

    // 1. Initialise + preload (absorbs cold-start delay, shows progress bar)
    await _tts.initialise();
    await _tts.preloadAll();

    if (!mounted) return;

    // 2. Switch to ready FIRST — warm-up UI is gone before any audio plays
    setState(() => _phase = 'ready');

    // Small pause so the UI transition is visible before audio starts
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;

    // 3. Speak welcome — instant from cache
    await _tts.speak('home.welcome');
    if (!mounted) return;

    // 4. Start instruction text loop + one-time voice cycle together
    _startInstructionCycle(speakOnce: true);
  }

  // ── Instruction cycle ─────────────────────────────────────────────────────
  // speakOnce: true  → speaks each instruction key exactly once, then goes silent
  // speakOnce: false → text loops only, no voice (used after first cycle or replay)
  void _startInstructionCycle({bool speakOnce = false}) {
    _instructionTimer?.cancel();
    if (!mounted) return;

    _voiceCycleDone = !speakOnce;

    setState(() {
      _instructionIndex = 0;
      _instructionVisible = true;
    });

    if (speakOnce) {
      _speakAndAdvance(0);
    } else {
      _scheduleNextInstruction();
    }
  }

  // Speak instruction at [index], wait for it, then advance to next.
  // After all 5 are spoken, falls back to silent text loop.
  Future<void> _speakAndAdvance(int index) async {
    if (!mounted) return;

    // Speak the current instruction
    await _tts.speak(_kInstructionKeys[index]);
    if (!mounted) return;

    final nextIndex = index + 1;

    if (nextIndex >= _kInstructions.length) {
      // Voice cycle complete — switch to silent looping text
      _voiceCycleDone = true;
      _scheduleNextInstruction();
      return;
    }

    // Fade out, update index, fade in, then speak next
    setState(() => _instructionVisible = false);
    await Future.delayed(_fadeDuration + const Duration(milliseconds: 100));
    if (!mounted) return;

    setState(() {
      _instructionIndex = nextIndex;
      _instructionVisible = true;
    });

    _speakAndAdvance(nextIndex);
  }

  // Silent text loop (used after voice cycle is done)
  void _scheduleNextInstruction() {
    _instructionTimer?.cancel();
    _instructionTimer = Timer(const Duration(milliseconds: 2800), () async {
      if (!mounted) return;
      setState(() => _instructionVisible = false);
      await Future.delayed(_fadeDuration + const Duration(milliseconds: 100));
      if (!mounted) return;
      setState(() {
        _instructionIndex = (_instructionIndex + 1) % _kInstructions.length;
        _instructionVisible = true;
      });
      _scheduleNextInstruction();
    });
  }

  // ── Replay ────────────────────────────────────────────────────────────────
  Future<void> _replayInstructions() async {
    _instructionTimer?.cancel();
    await _tts.stop();

    setState(() => _instructionVisible = false);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    // Welcome is cached — instant
    await _tts.speak('home.welcome');
    if (!mounted) return;

    // Replay voice cycle once more
    _startInstructionCycle(speakOnce: true);
  }

  // ── STT ───────────────────────────────────────────────────────────────────
  Future<void> _initStt() async {
    _sttAvailable = await _stt.initialize(
      onError: (error) {
        debugPrint('STT error: $error');
        if (mounted) {
          setState(() => _isListening = false);
          _pulseController.stop();
          _pulseController.reset();
        }
      },
      onStatus: (status) {
        if ((status == 'done' || status == 'notListening') && _isListening) {
          if (mounted) _stopListening();
        }
      },
    );
    if (mounted) setState(() {});
  }

  // ── Mic ───────────────────────────────────────────────────────────────────
  Future<void> _onMicTap() async {
    if (_phase == 'warmingUp') return;
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_sttAvailable) {
      await _tts.speakRaw('Speech recognition is not available on this device.');
      return;
    }

    _instructionTimer?.cancel();
    await _tts.stop();

    setState(() {
      _isListening = true;
      _recognizedText = '';
      _instructionVisible = false;
    });

    _pulseController.repeat(reverse: true);

    await _stt.listen(
      onResult: (result) {
        if (mounted) setState(() => _recognizedText = result.recognizedWords);
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 4),
      localeId: 'en_US',
      cancelOnError: true,
      partialResults: true,
    );
  }

  Future<void> _stopListening() async {
    if (_isNavigating) return;
    _isNavigating = true;

    await _stt.stop();
    _pulseController.stop();
    _pulseController.reset();

    if (mounted) setState(() => _isListening = false);

    await _navigate(_recognizedText.toLowerCase());
    _isNavigating = false;
  }

  // ── Navigation ────────────────────────────────────────────────────────────
  Future<void> _navigate(String text) async {
    if (text.isEmpty) {
      await _tts.speak('home.notHeard');
      // Resume silent text loop after notHeard
      _startInstructionCycle(speakOnce: false);
      return;
    }

    final isBreathing   = text.contains('breath') || text.contains('relax') ||
        text.contains('calm') || text.contains('exercise');
    final isEmergency   = text.contains('emergency') || text.contains('crisis') ||
        text.contains('urgent') || text.contains('support');
    final isSleep       = text.contains('sleep') || text.contains('rest') ||
        text.contains('bedtime') || text.contains('hygiene') ||
        text.contains('insomnia');
    final isMindfulness = text.contains('mindful') || text.contains('meditat') ||
        text.contains('aware') || text.contains('present');
    final isMood        = text.contains('mood') || text.contains('feeling') ||
        text.contains('emotion') || text.contains('track');

    Future<void> push(String navKey, Widget page) async {
      if (!mounted) return;
      await _tts.speak(navKey);
      await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
      await _tts.speak('home.back');
      if (mounted) _startInstructionCycle(speakOnce: false);
    }

    if (isBreathing) {
      await push('nav.breathing', const BreathingExercisesPage());
    } else if (isEmergency) {
      await push('nav.emergency', const EmergencySupportPage());
    } else if (isSleep) {
      await push('nav.sleep', const SleepVuiScreen());
    } else if (isMindfulness) {
      await push('nav.mindfulness', const MindfulnessPage());
    } else if (isMood) {
      await push('nav.mood', const MoodTrackingPage());
    } else {
      await _tts.speakRaw(
        'I heard "$_recognizedText" but I\'m not sure where to navigate. '
            'Try saying Breathing, Sleep, Mindfulness, Mood, or Emergency.',
      );
      _startInstructionCycle(speakOnce: false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _instructionTimer?.cancel();
    _pulseController.dispose();
    _tts.dispose();
    _stt.stop();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = _phase == 'ready';

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // ── App name ───────────────────────────────────────────────────
            Positioned(
              top: 20,
              left: 20,
              child: Text(
                'MindMate',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                  letterSpacing: 0.5,
                ),
              ),
            ),

            // ── Replay button ──────────────────────────────────────────────
            Positioned(
              top: 12,
              right: 16,
              child: AnimatedOpacity(
                opacity: isReady && !_isListening ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 400),
                child: Tooltip(
                  message: 'Replay instructions',
                  child: IconButton(
                    onPressed: isReady && !_isListening
                        ? _replayInstructions
                        : null,
                    icon: Icon(
                      Icons.replay_rounded,
                      color: colorScheme.primary,
                      size: 26,
                    ),
                  ),
                ),
              ),
            ),

            // ── Main layout ────────────────────────────────────────────────
            Column(
              children: [
                const Spacer(flex: 2),

                // ── Instruction / status area ──────────────────────────────
                SizedBox(
                  height: 160,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36),
                      child: _buildInstructionArea(colorScheme),
                    ),
                  ),
                ),

                const Spacer(flex: 3),

                // ── Mic button ─────────────────────────────────────────────
                ScaleTransition(
                  scale: _pulseAnim,
                  child: GestureDetector(
                    onTap: _onMicTap,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _phase == 'warmingUp'
                            ? colorScheme.primary.withOpacity(0.4)
                            : _isListening
                            ? colorScheme.error
                            : colorScheme.primary,
                        boxShadow: [
                          BoxShadow(
                            color: (_isListening
                                ? colorScheme.error
                                : colorScheme.primary)
                                .withOpacity(
                                _phase == 'warmingUp' ? 0.15 : 0.38),
                            blurRadius: 32,
                            spreadRadius: 6,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isListening
                            ? Icons.stop_rounded
                            : Icons.mic_rounded,
                        size: 50,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                // ── Mic label ──────────────────────────────────────────────
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: Text(
                    key: ValueKey('$_phase$_isListening'),
                    _phase == 'warmingUp'
                        ? 'Please wait…'
                        : _isListening
                        ? 'Listening…'
                        : 'Tap to speak',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),

                const Spacer(flex: 2),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Instruction area ──────────────────────────────────────────────────────
  Widget _buildInstructionArea(ColorScheme colorScheme) {
    if (_phase == 'warmingUp') {
      return ValueListenableBuilder<double>(
        valueListenable: _tts.preloadProgress,
        builder: (_, progress, __) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Warming Up…',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: 200,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress > 0 ? progress : null,
                    minHeight: 3,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary.withOpacity(0.6),
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    if (_isListening) {
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: Text(
          key: ValueKey(
              _recognizedText.isEmpty ? '__empty__' : _recognizedText),
          _recognizedText.isEmpty ? '…' : '"$_recognizedText"',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 22,
            fontStyle: FontStyle.italic,
            color: colorScheme.onSurface.withOpacity(0.75),
            height: 1.4,
          ),
        ),
      );
    }

    return AnimatedOpacity(
      opacity: _instructionVisible ? 1.0 : 0.0,
      duration: _fadeDuration,
      curve: Curves.easeInOut,
      child: Text(
        _kInstructions[_instructionIndex],
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w500,
          color: colorScheme.onSurface,
          height: 1.4,
          letterSpacing: 0.1,
        ),
      ),
    );
  }
}
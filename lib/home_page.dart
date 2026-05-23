import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mindmate/features/breathing_exercises/screens/breathing_exercises_page.dart';
import 'package:mindmate/features/emergency_support/screens/emergency_support_page.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // ── Services ──────────────────────────────────────────────────────────────
  final FlutterTts _tts = FlutterTts();
  final stt.SpeechToText _stt = stt.SpeechToText();

  // ── State ─────────────────────────────────────────────────────────────────
  bool _isListening = false;
  bool _sttAvailable = false;
  String _recognizedText = '';
  String _statusLabel = 'Tap the mic and speak';

  // ── Pulse animation ───────────────────────────────────────────────────────
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();

    // Pulse animation (only plays while listening)
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.25).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _initStt();
    _initTts();
  }

  // ── TTS setup & welcome ───────────────────────────────────────────────────
  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    // Brief delay so the screen is ready before speaking
    await Future.delayed(const Duration(milliseconds: 600));
    await _speak(
      'Welcome to MindMate. Tap the microphone and tell me where you want to go.',
    );
  }

  // ── STT setup ─────────────────────────────────────────────────────────────
  Future<void> _initStt() async {
    _sttAvailable = await _stt.initialize(
      onError: (error) {
        debugPrint('STT error: $error');
        if (mounted) {
          setState(() {
            _isListening = false;
            _statusLabel = 'Error. Try again.';
          });
          _pulseController.stop();
          _pulseController.reset();
        }
      },
      onStatus: (status) {
        debugPrint('STT status: $status');
        // speech_to_text stops automatically after a pause; sync our state
        if (status == 'done' || status == 'notListening') {
          if (_isListening && mounted) {
            _stopListening();
          }
        }
      },
    );

    if (mounted) setState(() {});
  }

  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _speak(String text) async {
    await _tts.stop();
    await _tts.speak(text);
  }

  // ── Mic button handler ────────────────────────────────────────────────────
  Future<void> _onMicTap() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (!_sttAvailable) {
      await _speak('Speech recognition is not available on this device.');
      return;
    }

    await _tts.stop(); // stop any ongoing TTS before listening
    setState(() {
      _isListening = true;
      _recognizedText = '';
      _statusLabel = 'Listening…';
    });

    _pulseController.repeat(reverse: true);

    await _stt.listen(
      onResult: (result) {
        if (mounted) {
          setState(() {
            _recognizedText = result.recognizedWords;
          });
        }
      },
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 4),
      localeId: 'en_US',
      cancelOnError: true,
      partialResults: true,
    );
  }

  Future<void> _stopListening() async {
    await _stt.stop();
    _pulseController.stop();
    _pulseController.reset();

    if (mounted) {
      setState(() {
        _isListening = false;
        _statusLabel = 'Processing…';
      });
    }

    await _navigate(_recognizedText.toLowerCase());
  }

  // ── Intent matching & navigation ──────────────────────────────────────────
  Future<void> _navigate(String text) async {
    if (text.isEmpty) {
      setState(() => _statusLabel = 'I didn\'t catch that. Try again.');
      await _speak('I didn\'t catch that. Please try again.');
      return;
    }

    final isBreathing =
        text.contains('breath') ||
        text.contains('breathing') ||
        text.contains('relax') ||
        text.contains('calm') ||
        text.contains('exercise');

    final isEmergency =
        text.contains('emergency') ||
        text.contains('help') ||
        text.contains('crisis') ||
        text.contains('urgent') ||
        text.contains('support');

    if (isBreathing) {
      setState(() => _statusLabel = 'Going to Breathing Exercises…');
      await _speak('Opening Breathing Exercises.');
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const BreathingExercisesPage()),
        );
        // Speak when returning to home
        await _speak('You are back on the home page.');
        if (mounted) setState(() => _statusLabel = 'Tap the mic and speak');
      }
    } else if (isEmergency) {
      setState(() => _statusLabel = 'Going to Emergency Support…');
      await _speak('Opening Emergency Support.');
      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const EmergencySupportPage()),
        );
        await _speak('You are back on the home page.');
        if (mounted) setState(() => _statusLabel = 'Tap the mic and speak');
      }
    } else {
      setState(
        () => _statusLabel =
            'Not sure where to go. Try "Emergency" or "Breathing".',
      );
      await _speak(
        'I heard "$_recognizedText" but I\'m not sure where to navigate. '
        'Try saying Emergency Support or Breathing Exercises.',
      );
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    _pulseController.dispose();
    _tts.stop();
    _stt.stop();
    super.dispose();
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MindMate',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Your voice-guided companion',
                    style: TextStyle(
                      fontSize: 15,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            // ── Quick-nav cards ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
              child: Row(
                children: [
                  _NavCard(
                    icon: Icons.air,
                    label: 'Breathing\nExercises',
                    color: const Color(0xFF4CAF82),
                    onTap: () async {
                      await _speak('Opening Breathing Exercises.');
                      if (mounted) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const BreathingExercisesPage(),
                          ),
                        );
                        await _speak('You are back on the home page.');
                      }
                    },
                  ),
                  const SizedBox(width: 14),
                  _NavCard(
                    icon: Icons.local_hospital_rounded,
                    label: 'Emergency\nSupport',
                    color: const Color(0xFFE05C5C),
                    onTap: () async {
                      await _speak('Opening Emergency Support.');
                      if (mounted) {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const EmergencySupportPage(),
                          ),
                        );
                        await _speak('You are back on the home page.');
                      }
                    },
                  ),
                ],
              ),
            ),

            // ── Centre mic area ──────────────────────────────────────────
            const Spacer(),

            // Recognized text
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _recognizedText.isNotEmpty
                  ? Padding(
                      key: const ValueKey('text'),
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Text(
                        '"$_recognizedText"',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontStyle: FontStyle.italic,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : const SizedBox(key: ValueKey('empty')),
            ),

            const SizedBox(height: 20),

            // Pulsing mic button
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
                    color: _isListening
                        ? colorScheme.error
                        : colorScheme.primary,
                    boxShadow: [
                      BoxShadow(
                        color:
                            (_isListening
                                    ? colorScheme.error
                                    : colorScheme.primary)
                                .withOpacity(0.35),
                        blurRadius: 28,
                        spreadRadius: 4,
                      ),
                    ],
                  ),
                  child: Icon(
                    _isListening ? Icons.stop_rounded : Icons.mic_rounded,
                    size: 52,
                    color: Colors.white,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Status label
            Text(
              _statusLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 12),

            // Hint chips
            if (!_isListening)
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  _HintChip(label: '"Go to Emergency"'),
                  _HintChip(label: '"Breathing Exercises"'),
                ],
              ),

            const Spacer(),
          ],
        ),
      ),
    );
  }
}

// ── Supporting widgets ────────────────────────────────────────────────────────

class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(
            children: [
              Icon(icon, color: color, size: 26),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HintChip extends StatelessWidget {
  const _HintChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
    );
  }
}

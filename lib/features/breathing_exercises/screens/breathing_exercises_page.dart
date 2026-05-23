import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

class BreathingExercisesPage extends StatefulWidget {
  const BreathingExercisesPage({super.key});

  @override
  State<BreathingExercisesPage> createState() => _BreathingExercisesPageState();
}

class _BreathingExercisesPageState extends State<BreathingExercisesPage>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  late AnimationController _circleController;
  late Animation<double> _circleAnim;
  bool _isAnimating = false;
  String _phaseLabel = 'Press Start to begin';

  final List<Map<String, dynamic>> _exercises = [
    {
      'title': '4-7-8 Breathing',
      'subtitle': 'Inhale 4s · Hold 7s · Exhale 8s',
      'icon': Icons.self_improvement_rounded,
      'color': const Color(0xFF4CAF82),
    },
    {
      'title': 'Box Breathing',
      'subtitle': 'Inhale · Hold · Exhale · Hold — 4s each',
      'icon': Icons.crop_square_rounded,
      'color': const Color(0xFF6C63FF),
    },
    {
      'title': 'Deep Belly Breathing',
      'subtitle': 'Slow diaphragmatic breaths',
      'icon': Icons.air_rounded,
      'color': const Color(0xFF2196F3),
    },
  ];

  @override
  void initState() {
    super.initState();

    _circleController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _circleAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _circleController, curve: Curves.easeInOut),
    );

    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);
    await _tts.setVolume(1.0);

    // Short delay then announce page
    await Future.delayed(const Duration(milliseconds: 300));
    await _tts.speak(
      'You are in the Breathing Exercises page. Choose an exercise to get started.',
    );
  }

  Future<void> _runGuided4_7_8() async {
    setState(() {
      _isAnimating = true;
      _phaseLabel = 'Inhale…';
    });

    // Inhale – 4 seconds
    await _tts.speak('Inhale slowly through your nose');
    _circleController.duration = const Duration(seconds: 4);
    await _circleController.forward();

    // Hold – 7 seconds
    setState(() => _phaseLabel = 'Hold…');
    await _tts.speak('Hold your breath');
    await Future.delayed(const Duration(seconds: 7));

    // Exhale – 8 seconds
    setState(() => _phaseLabel = 'Exhale…');
    await _tts.speak('Exhale slowly through your mouth');
    _circleController.duration = const Duration(seconds: 8);
    await _circleController.reverse();

    setState(() {
      _isAnimating = false;
      _phaseLabel = 'Great! Press Start again for another round.';
    });
    await _tts.speak('Well done. Press start for another round.');
  }

  @override
  void dispose() {
    _circleController.dispose();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Breathing Exercises'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Guided visual ────────────────────────────────────────────
            Center(
              child: Column(
                children: [
                  ScaleTransition(
                    scale: _circleAnim,
                    child: Container(
                      width: 160,
                      height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [
                            const Color(0xFF4CAF82).withOpacity(0.6),
                            const Color(0xFF4CAF82).withOpacity(0.15),
                          ],
                        ),
                      ),
                      child: const Icon(
                        Icons.air_rounded,
                        size: 64,
                        color: Color(0xFF4CAF82),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _phaseLabel,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _isAnimating ? null : _runGuided4_7_8,
                    icon: Icon(
                      _isAnimating
                          ? Icons.hourglass_top_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    label: Text(_isAnimating ? 'Breathing…' : 'Start 4-7-8'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF82),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            Text(
              'All Exercises',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 12),

            // ── Exercise cards ───────────────────────────────────────────
            ...List.generate(_exercises.length, (i) {
              final ex = _exercises[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (ex['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (ex['color'] as Color).withOpacity(0.25),
                  ),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: (ex['color'] as Color).withOpacity(0.2),
                      child: Icon(
                        ex['icon'] as IconData,
                        color: ex['color'] as Color,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            ex['title'] as String,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            ex['subtitle'] as String,
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

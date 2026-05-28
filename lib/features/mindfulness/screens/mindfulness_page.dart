import 'package:flutter/material.dart';
import 'package:mindmate/features/sleep_hygiene/services/tts_service.dart';

class MindfulnessPage extends StatefulWidget {
  const MindfulnessPage({super.key});

  @override
  State<MindfulnessPage> createState() => _MindfulnessPageState();
}

class _MindfulnessPageState extends State<MindfulnessPage> {
  final TtsService _tts = TtsService();
  bool _isPlaying = false;
  String _sessionLabel = 'Tap a session to begin';

  final List<Map<String, dynamic>> _sessions = [
    {
      'title': 'Body Scan',
      'subtitle': '5 min · Full-body awareness',
      'icon': Icons.accessibility_new_rounded,
      'color': const Color(0xFF9C6FDE),
    },
    {
      'title': 'Mindful Observation',
      'subtitle': '3 min · Focus on the present',
      'icon': Icons.visibility_rounded,
      'color': const Color(0xFF4CAF82),
    },
    {
      'title': 'Loving Kindness',
      'subtitle': '5 min · Compassion meditation',
      'icon': Icons.favorite_rounded,
      'color': const Color(0xFFE05C5C),
    },
  ];

  final List<Map<String, String>> _tips = [
    {
      'icon': '🧠',
      'title': 'Notice your thoughts',
      'body': 'Observe thoughts without judgment — let them pass like clouds.',
    },
    {
      'icon': '👁️',
      'title': 'Stay present',
      'body': 'Gently bring your attention back whenever your mind wanders.',
    },
    {
      'icon': '🌿',
      'title': 'Be kind to yourself',
      'body': 'There is no right or wrong way — every moment of awareness counts.',
    },
  ];

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.initialise();
    await Future.delayed(const Duration(milliseconds: 300));
    await _tts.speak(
      'You are in the Mindfulness page. Choose a session to begin your practice.',
    );
  }

  Future<void> _runBodyScan() async {
    if (_isPlaying) return;
    setState(() {
      _isPlaying = true;
      _sessionLabel = 'Body Scan in progress…';
    });

    await _tts.speak(
      'Close your eyes and take a deep breath. '
          'Slowly bring your attention to the top of your head. '
          'Notice any tension and let it melt away. '
          'Move your awareness gently down to your shoulders, arms, and hands. '
          'Continue down through your chest, belly, and legs. '
          'You are fully present. Well done.',
    );

    setState(() {
      _isPlaying = false;
      _sessionLabel = 'Session complete. Tap to repeat.';
    });
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFF9C6FDE);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Mindfulness'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: cs.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accent.withOpacity(0.85), accent.withOpacity(0.50)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🧘  Be here, now',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 6),
                  Text('A few mindful minutes can reset your entire day.',
                      style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Center(
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 600),
                    width: 140,
                    height: 140,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(_isPlaying ? 0.25 : 0.12),
                      border: Border.all(
                          color: accent.withOpacity(_isPlaying ? 0.7 : 0.3), width: 2),
                    ),
                    child: Icon(Icons.self_improvement_rounded,
                        size: 64, color: accent.withOpacity(_isPlaying ? 1.0 : 0.6)),
                  ),
                  const SizedBox(height: 12),
                  Text(_sessionLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 14, color: cs.onSurfaceVariant, fontStyle: FontStyle.italic)),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    onPressed: _isPlaying ? null : _runBodyScan,
                    icon: Icon(_isPlaying ? Icons.hourglass_top_rounded : Icons.play_arrow_rounded),
                    label: Text(_isPlaying ? 'Playing…' : 'Start Body Scan'),
                    style: FilledButton.styleFrom(backgroundColor: accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Text('All Sessions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 12),
            ...List.generate(_sessions.length, (i) {
              final s = _sessions[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (s['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (s['color'] as Color).withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: (s['color'] as Color).withOpacity(0.2),
                      child: Icon(s['icon'] as IconData, color: s['color'] as Color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s['title'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                          const SizedBox(height: 3),
                          Text(s['subtitle'] as String,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 28),
            Text('Mindfulness Tips',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 12),
            ...List.generate(_tips.length, (i) {
              final t = _tips[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['icon']!, style: const TextStyle(fontSize: 26)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(t['title']!,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 3),
                          Text(t['body']!,
                              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4)),
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
import 'package:flutter/material.dart';
import 'package:mindmate/features/sleep_hygiene/services/tts_service.dart';

class MoodTrackingPage extends StatefulWidget {
  const MoodTrackingPage({super.key});

  @override
  State<MoodTrackingPage> createState() => _MoodTrackingPageState();
}

class _MoodTrackingPageState extends State<MoodTrackingPage> {
  final TtsService _tts = TtsService();
  int? _selectedMoodIndex;

  final List<Map<String, dynamic>> _moods = [
    {'emoji': '😄', 'label': 'Great',     'color': const Color(0xFF4CAF82)},
    {'emoji': '🙂', 'label': 'Good',      'color': const Color(0xFF6C63FF)},
    {'emoji': '😐', 'label': 'Okay',      'color': const Color(0xFFFFA726)},
    {'emoji': '😔', 'label': 'Low',       'color': const Color(0xFF2196F3)},
    {'emoji': '😞', 'label': 'Struggling','color': const Color(0xFFE05C5C)},
  ];

  final List<Map<String, String>> _tips = [
    {
      'icon': '📓',
      'title': 'Journal it',
      'body': 'Write 3 sentences about how you feel — it helps process emotions.',
    },
    {
      'icon': '🌤️',
      'title': 'Identify triggers',
      'body': 'Notice what events or thoughts shifted your mood today.',
    },
    {
      'icon': '💬',
      'title': 'Talk about it',
      'body': 'Sharing how you feel with someone trusted can lighten the load.',
    },
  ];

  final List<Map<String, dynamic>> _log = [];

  @override
  void initState() {
    super.initState();
    _initTts();
  }

  Future<void> _initTts() async {
    await _tts.initialise();
    await Future.delayed(const Duration(milliseconds: 300));
    await _tts.speak(
      'You are in the Mood Tracking page. '
          'Tap how you are feeling right now to log your mood.',
    );
  }

  Future<void> _selectMood(int index) async {
    setState(() => _selectedMoodIndex = index);
    final mood = _moods[index];
    _log.insert(0, {
      'emoji': mood['emoji'],
      'label': mood['label'],
      'time': TimeOfDay.now().format(context),
    });
    await _tts.speak('You selected ${mood['label']}. Your mood has been logged.');
    setState(() {});
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const accent = Color(0xFF6C63FF);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Mood Tracking'),
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
                  Text('💜  How are you feeling?',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 6),
                  Text('Tracking your mood daily helps you understand your emotional patterns.',
                      style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text('Log Today\'s Mood',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(_moods.length, (i) {
                final m = _moods[i];
                final isSelected = _selectedMoodIndex == i;
                return GestureDetector(
                  onTap: () => _selectMood(i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? (m['color'] as Color).withOpacity(0.2)
                          : cs.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isSelected ? m['color'] as Color : Colors.transparent,
                        width: 2,
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(m['emoji'] as String, style: const TextStyle(fontSize: 28)),
                        const SizedBox(height: 4),
                        Text(m['label'] as String,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? m['color'] as Color : cs.onSurfaceVariant,
                            )),
                      ],
                    ),
                  ),
                );
              }),
            ),
            if (_log.isNotEmpty) ...[
              const SizedBox(height: 28),
              Text('Recent Entries',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface)),
              const SizedBox(height: 12),
              ..._log.take(5).map((entry) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Text(entry['emoji'] as String, style: const TextStyle(fontSize: 22)),
                    const SizedBox(width: 12),
                    Text(entry['label'] as String,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const Spacer(),
                    Text(entry['time'] as String,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                  ],
                ),
              )),
            ],
            const SizedBox(height: 28),
            Text('Mood Tips',
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
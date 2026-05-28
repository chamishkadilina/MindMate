import 'package:flutter/material.dart';
import 'package:mindmate/features/sleep_hygiene/services/tts_service.dart';

class EmergencySupportPage extends StatefulWidget {
  const EmergencySupportPage({super.key});

  @override
  State<EmergencySupportPage> createState() => _EmergencySupportPageState();
}

class _EmergencySupportPageState extends State<EmergencySupportPage> {
  final TtsService _tts = TtsService();

  final List<Map<String, dynamic>> _contacts = [
    {
      'title': 'Mental Health Hotline',
      'number': '1926',
      'subtitle': 'Available 24/7 — Sri Lanka',
      'icon': Icons.phone_in_talk_rounded,
      'color': const Color(0xFFE05C5C),
    },
    {
      'title': 'Crisis Text Line',
      'number': 'Text HOME to 741741',
      'subtitle': 'Free, confidential support',
      'icon': Icons.chat_bubble_rounded,
      'color': const Color(0xFF6C63FF),
    },
    {
      'title': 'Emergency Services',
      'number': '119',
      'subtitle': 'Police / Ambulance / Fire',
      'icon': Icons.local_hospital_rounded,
      'color': const Color(0xFF2196F3),
    },
  ];

  final List<Map<String, String>> _tips = [
    {
      'icon': '🫁',
      'title': 'Breathe slowly',
      'body': 'Inhale for 4 counts, hold for 4, exhale for 4.',
    },
    {
      'icon': '👣',
      'title': 'Ground yourself',
      'body': 'Name 5 things you can see, 4 you can touch, 3 you can hear.',
    },
    {
      'icon': '🤝',
      'title': 'Reach out',
      'body': 'You are not alone. Call a friend, family member, or a helpline.',
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
      'You are in the Emergency Support page. '
          'Help is available. Please reach out to one of the contacts shown.',
    );
  }

  @override
  void dispose() {
    _tts.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Emergency Support'),
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
                  colors: [
                    const Color(0xFFE05C5C).withOpacity(0.85),
                    const Color(0xFFE05C5C).withOpacity(0.55),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🆘  You are not alone',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                  SizedBox(height: 6),
                  Text('Help is always available. Reach out to a helpline or a trusted person.',
                      style: TextStyle(color: Colors.white, fontSize: 13, height: 1.4)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            Text('Emergency Contacts',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: cs.onSurface)),
            const SizedBox(height: 12),
            ...List.generate(_contacts.length, (i) {
              final c = _contacts[i];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: (c['color'] as Color).withOpacity(0.09),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: (c['color'] as Color).withOpacity(0.25)),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: (c['color'] as Color).withOpacity(0.18),
                      child: Icon(c['icon'] as IconData, color: c['color'] as Color),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c['title'] as String,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(c['number'] as String,
                              style: TextStyle(
                                  color: c['color'] as Color,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15)),
                          Text(c['subtitle'] as String,
                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 14, color: cs.outlineVariant),
                  ],
                ),
              );
            }),
            const SizedBox(height: 28),
            Text('Immediate Coping Tips',
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
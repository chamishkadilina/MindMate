// sleep_vui_screen.dart

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mindmate/core/widgets/voice_mic_button.dart';
import 'package:mindmate/features/sleep_hygiene/screens/sleep_graph.dart';
import '../controller/sleep_hygine_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Topic chip data
// Each chip fires sendTextCommand(displayLabel, command) on the controller.
// ─────────────────────────────────────────────────────────────────────────────

class _Topic {
  const _Topic({
    required this.emoji,
    required this.label,
    required this.command,
  });
  final String emoji;
  final String label;
  final String command; // keyword string routed through the rule engine
}

const _kTopics = [
  _Topic(emoji: '😴', label: "Can't sleep",     command: "i can't fall asleep"),
  _Topic(emoji: '🌙', label: 'Bedtime routine',  command: 'bedtime routine'),
  _Topic(emoji: '📱', label: 'Screen time',      command: 'screen time before bed'),
  _Topic(emoji: '☕', label: 'Caffeine',         command: 'caffeine and sleep'),
  _Topic(emoji: '💤', label: 'Nap advice',       command: 'nap advice'),
  _Topic(emoji: '⏰', label: 'Sleep duration',   command: 'how many hours of sleep'),
  _Topic(emoji: '🧠', label: 'Sleep stages',     command: 'what is rem sleep'),
  _Topic(emoji: '🏃', label: 'Exercise & sleep', command: 'exercise and sleep'),
];

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class SleepVuiScreen extends StatefulWidget {
  const SleepVuiScreen({super.key});

  @override
  State<SleepVuiScreen> createState() => _SleepVuiScreenState();
}

class _SleepVuiScreenState extends State<SleepVuiScreen>
    with SingleTickerProviderStateMixin {

  late final SleepController _controller;
  final ScrollController _scrollController = ScrollController();

  // Indigo — consistent with app-wide brand colour
  static const Color _accent = Color(0xFF3F51B5);

  final Set<int> _animatedSet = {};

  bool   _micVisible       = true;
  double _lastScrollOffset = 0.0;



  @override
  void initState() {
    super.initState();
    _controller = SleepController(vsync: this);
    _controller.addListener(_onStateChange);
    // attachContext must come before init so TTS-triggered navigation works
    _controller.attachContext(context);
    _controller.init();
    _scrollController.addListener(_onScrollMic);
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChange);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onStateChange() {
    if (!mounted) return;
    setState(() => _micVisible = true);
    // Scroll to the latest message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onScrollMic() {
    final offset = _scrollController.offset;
    final goingDown = offset > _lastScrollOffset;
    _lastScrollOffset = offset;
    if (goingDown == _micVisible) {
      setState(() => _micVisible = !goingDown);
    }
  }


  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bool isBusy =
        _controller.isListening || _controller.isProcessing;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [

            // ── Header — mirrors MoodTrackingPage exactly ──────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    style: IconButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: const CircleBorder(),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded, size: 24),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Text(
                      'Sleep Hygiene',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: _accent,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (_, __, ___) => const SleepGraphScreen(),
                        transitionsBuilder: (_, anim, __, child) =>
                            FadeTransition(opacity: anim, child: child),
                        transitionDuration: const Duration(milliseconds: 500),
                      ),
                    ),
                    tooltip: 'Sleep progress',
                    style: IconButton.styleFrom(
                      backgroundColor: _accent.withValues(alpha: 0.10),
                      foregroundColor: _accent,
                      shape: const CircleBorder(),
                    ),
                    icon: const Icon(Icons.bar_chart_rounded, size: 20),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Activity buttons ───────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: _ActivityButton(
                emoji:    '',
                label:    'Bedtime routine',
                disabled: isBusy,
                onTap: () => _controller.sendTextCommand('Wind-down routine', 'wind down'),
              ),
            ),

            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Divider(height: 1, color: Colors.black.withValues(alpha: 0.05)),
            ),

            // ── Chat area ──────────────────────────────────────────────────
            // ── Chat + Mic stacked ─────────────────────────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  // Chat list fills full area
                  Positioned.fill(
                    child: _controller.chatHistory.isEmpty
                        ? _EmptyState(accentColor: _accent)
                        : // Chat list fills full area
                    Positioned.fill(
                      child: _controller.chatHistory.isEmpty
                          ? _EmptyState(accentColor: _accent)
                          : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(24, 20, 24, 120),
                        itemCount: _controller.chatHistory.length + (isBusy ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _controller.chatHistory.length) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16, left: 36),
                              child: _ThinkingDots(color: _accent),
                            );
                          }

                          final isLast = index == _controller.chatHistory.length - 1;
                          final message = _controller.chatHistory[index];

                          // Show rating pills only attached to the last assistant bubble
                          // and only while awaiting a quality rating
                          final showRatingPills = isLast
                              && !message.isUser
                              && _controller.awaitingQualityRating;

                          final showNavConfirmPills = isLast
                              && !message.isUser
                              && _controller.currentState == 'awaiting_nav_confirmation';

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ChatBubble(
                                key:         ValueKey(index),
                                message:     message,
                                accentColor: _accent,
                                animate: isLast && !_animatedSet.contains(index),
                                onAnimationDone: () {
                                  if (mounted) setState(() => _animatedSet.add(index));
                                },
                              ),

                              // ── Rating pills pinned directly under the question bubble ──
                              if (showRatingPills)
                                Padding(
                                  padding: const EdgeInsets.only(left: 36, right: 0, bottom: 20),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: List.generate(5, (i) {
                                      final rating = i + 1;
                                      final colors = [
                                        const Color(0xFFE8EAF6),
                                        const Color(0xFFC5CAE9),
                                        const Color(0xFF9FA8DA),
                                        const Color(0xFF5C6BC0),
                                        const Color(0xFF3F51B5),
                                      ];
                                      final textColor = i >= 2 ? Colors.white : _accent;

                                      return GestureDetector(
                                        onTap: () => _controller.sendRating(rating),
                                        child: Container(
                                          width:  40,
                                          height: 40,
                                          decoration: BoxDecoration(
                                            color: colors[i],
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: _accent.withValues(alpha: 0.25),
                                              width: 1,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              '$rating',
                                              style: TextStyle(
                                                fontSize:   16,
                                                fontWeight: FontWeight.bold,
                                                color:      textColor,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),
                                ),

                              if (showNavConfirmPills)
                                Padding(
                                  padding: const EdgeInsets.only(left: 36, right: 0, bottom: 20),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    children: [
                                      GestureDetector(
                                        onTap: () => _controller.sendTextCommand('Yes', 'yes'),
                                        child: Container(
                                          margin: const EdgeInsets.only(right: 12),
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _accent,
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: const Text('Yes',
                                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => _controller.sendTextCommand('No', 'no'),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: _accent.withValues(alpha: 0.3)),
                                          ),
                                          child: const Text('No',
                                              style: TextStyle(color: _accent, fontWeight: FontWeight.bold)),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  // Mic button pinned to bottom
                  Positioned(
                    left:   0,
                    right:  0,
                    bottom: 0,
                    child: AnimatedSlide(
                      offset:   _micVisible ? Offset.zero : const Offset(0, 1),
                      duration: const Duration(milliseconds: 280),
                      curve:    Curves.easeInOut,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                        child: VoiceMicButton(
                          isListening:    _controller.isListening,
                          onTap:          _controller.onMicTap,
                          statusLabel:    _controller.statusLabel,
                          recognizedText: _controller.recognizedText,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Topic chip widget
// ─────────────────────────────────────────────────────────────────────────────

class _TopicChip extends StatelessWidget {
  const _TopicChip({
    required this.topic,
    required this.disabled,
    required this.onTap,
  });

  final _Topic       topic;
  final bool         disabled;
  final VoidCallback onTap;

  static const Color _accent = Color(0xFF3F51B5);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedOpacity(
        opacity:  disabled ? 0.45 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _accent.withValues(alpha: 0.25)),
            boxShadow: [
              BoxShadow(
                color:      Colors.black.withValues(alpha: 0.04),
                blurRadius: 4,
                offset:     const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(topic.emoji, style: const TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              Text(
                topic.label,
                style: const TextStyle(
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  color:      _accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.accentColor});
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bedtime_outlined,
              size:  56,
              color: Colors.black.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 24),
            Text(
              'Tap a topic or use the mic',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize:   18,
                fontWeight: FontWeight.bold,
                color:      Colors.black.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask about bedtime routines, sleep tips, screen time, and more',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color:    Colors.black.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Chat bubble — mirrors MoodTrackingPage._buildTurn() exactly
// ─────────────────────────────────────────────────────────────────────────────

class _ChatBubble extends StatefulWidget {
  const _ChatBubble({
    super.key,
    required this.message,
    required this.accentColor,
    this.animate = false,
    this.onAnimationDone,
  });

  final SleepMessage message;
  final Color        accentColor;
  final bool         animate;
  final VoidCallback? onAnimationDone;

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble> {
  String _displayText = '';
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.animate && !widget.message.isUser) {
      _startTyping();
    } else {
      _displayText = widget.message.text;
    }
  }

  void _startTyping() {
    final text = widget.message.text;
    if (text.isEmpty) return;

    final words = text.split(' ');

    // Estimate total speech duration based on ~150 words/min average rate
    const wordsPerMinute = 150;
    final estimatedSeconds = (words.length / wordsPerMinute) * 60;
    final totalDurationMs = (estimatedSeconds * 1000).clamp(500, 30000);

    final wordDuration = Duration(
      milliseconds: (totalDurationMs / words.length).round().clamp(50, 400),
    );

    int index = 0;
    _timer = Timer.periodic(wordDuration, (timer) {
      if (index >= words.length) {
        timer.cancel();
        widget.onAnimationDone?.call();
        return;
      }
      setState(() {
        index++;
        _displayText = words.sublist(0, index).join(' ');
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final message     = widget.message;
    final accentColor = widget.accentColor;
    final text         = _displayText;

    if (!message.isUser) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 12),
              child: CircleAvatar(
                radius:          12,
                backgroundColor: accentColor,
                child: const Icon(
                  Icons.bedtime_rounded,
                  color: Colors.white,
                  size:  14,
                ),
              ),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: const BorderRadius.only(
                    topLeft:     Radius.circular(4),
                    topRight:    Radius.circular(16),
                    bottomLeft:  Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:      Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset:     const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  text,
                  style: const TextStyle(
                    fontSize:   15,
                    fontWeight: FontWeight.w500,
                    color:      Colors.black87,
                    height:     1.55,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // User bubble — right-aligned, accent colour
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        mainAxisAlignment:  MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft:     Radius.circular(16),
                  topRight:    Radius.circular(4),
                  bottomLeft:  Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color:      accentColor.withValues(alpha: 0.30),
                    blurRadius: 8,
                    offset:     const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                text,
                style: const TextStyle(
                  fontSize:   15,
                  color:      Colors.white,
                  fontWeight: FontWeight.w500,
                  height:     1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thinking dots — same implementation as MoodTrackingPage._ThinkingDots
// ─────────────────────────────────────────────────────────────────────────────

class _ThinkingDots extends StatefulWidget {
  const _ThinkingDots({required this.color});
  final Color color;

  @override
  State<_ThinkingDots> createState() => _ThinkingDotsState();
}

class _ThinkingDotsState extends State<_ThinkingDots>
    with SingleTickerProviderStateMixin {

  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.start,
          children: List.generate(3, (i) {
            final phase = i / 3;
            final t     = (_ctrl.value - phase + 1.0) % 1.0;
            final scale = 0.6 + 0.8 * (t < 0.5 ? t * 2 : (1 - t) * 2);
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width:  8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: widget.color.withValues(alpha: 0.8),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _SleepStatsCard extends StatelessWidget {
  const _SleepStatsCard({
    required this.issue,
    required this.bedtime,
    required this.wakeTime,
  });

  final String issue;
  final String bedtime;
  final String wakeTime;

  static const Color _accent = Color(0xFF3F51B5);

  String get _issueLabel {
    switch (issue) {
      case 'onset':       return 'Falling asleep';
      case 'maintenance': return 'Staying asleep';
      case 'early':       return 'Waking too early';
      case 'quality':     return 'Sleep quality';
      default:            return 'General sleep';
    }
  }

  IconData get _issueIcon {
    switch (issue) {
      case 'onset':       return Icons.bedtime_rounded;
      case 'maintenance': return Icons.nightlight_round;
      case 'early':       return Icons.wb_twilight_rounded;
      case 'quality':     return Icons.battery_alert_rounded;
      default:            return Icons.bedtime_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color:        Colors.white.withOpacity(0.85),
          borderRadius: BorderRadius.circular(16),
          border:       Border.all(color: _accent.withOpacity(0.12)),
          boxShadow: [
            BoxShadow(
              color:      Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset:     const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Sleep window ────────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your sleep window',
                    style: TextStyle(
                      fontSize:   11,
                      fontWeight: FontWeight.w600,
                      color:      Colors.black.withOpacity(0.40),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.bedtime_rounded, size: 14, color: _accent),
                      const SizedBox(width: 4),
                      Text(
                        bedtime,
                        style: const TextStyle(
                          fontSize:   14,
                          fontWeight: FontWeight.w600,
                          color:      _accent,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size:  12,
                          color: Colors.black.withOpacity(0.30),
                        ),
                      ),
                      const Icon(Icons.wb_sunny_rounded, size: 14, color: Color(0xFFFFB300)),
                      const SizedBox(width: 4),
                      Text(
                        wakeTime,
                        style: const TextStyle(
                          fontSize:   14,
                          fontWeight: FontWeight.w600,
                          color:      Color(0xFF1A237E),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Divider ─────────────────────────────────────────────────────
            Container(
              width:  1,
              height: 36,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color:  Colors.black.withOpacity(0.08),
            ),

            // ── Main concern ────────────────────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Main concern',
                  style: TextStyle(
                    fontSize:   11,
                    fontWeight: FontWeight.w600,
                    color:      Colors.black.withOpacity(0.40),
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(_issueIcon, size: 14, color: _accent),
                    const SizedBox(width: 4),
                    Text(
                      _issueLabel,
                      style: const TextStyle(
                        fontSize:   13,
                        fontWeight: FontWeight.w600,
                        color:      _accent,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityButton extends StatelessWidget {
  const _ActivityButton({
    required this.emoji,
    required this.label,
    required this.disabled,
    required this.onTap,
  });

  final String       emoji;
  final String       label;
  final bool         disabled;
  final VoidCallback onTap;

  static const Color _accent = Color(0xFF3F51B5);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedOpacity(
        opacity:  disabled ? 0.45 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color:        _accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: _accent.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 15)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                    color:      _accent,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

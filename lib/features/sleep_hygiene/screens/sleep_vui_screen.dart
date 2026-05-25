// sleep_screen.dart
// Updated to match new SleepVuiState shape:
//   - state.history (List<ChatMessage>) instead of transcript/response
//   - state.suggestions (chip buttons)
//   - state.lastIntent + state.lastConfidence for debug label
//   - sendSuggestion() on notifier

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/sleep_content.dart';
import '../services/sleep_engine.dart';


// ════════════════════════════════════════════════════════════════
// 1. SCREEN
// ════════════════════════════════════════════════════════════════

class SleepVuiScreen extends ConsumerStatefulWidget {
  const SleepVuiScreen({super.key});

  @override
  ConsumerState<SleepVuiScreen> createState() => _SleepVuiScreenState();
}

class _SleepVuiScreenState extends ConsumerState<SleepVuiScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;
  final TextEditingController _textController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 120), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sleepVuiNotifierProvider);
    final notifier = ref.read(sleepVuiNotifierProvider.notifier);

    // Side effects
    ref.listen<SleepVuiState>(sleepVuiNotifierProvider, (prev, next) {
      // Navigation
      if (next.pendingRoute != null) {
        notifier.clearPendingRoute();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Navigating to ${next.pendingRoute}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
      // Auto-scroll when history grows
      if ((next.history.length) != (prev?.history.length ?? 0)) {
        _scrollToBottom();
      }
    });

    final bool isListening = state.status == SleepVuiStatus.listening;
    final bool isProcessing = state.status == SleepVuiStatus.processing;
    final bool isSpeaking = state.status == SleepVuiStatus.speaking;
    final bool isBusy = isListening || isProcessing || isSpeaking;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: const BackButton(color: Colors.black87),
        title: const Text(
          'Sleep hygiene',
          style: TextStyle(
              color: Colors.black87, fontSize: 17, fontWeight: FontWeight.w400),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Scrollable content ──────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Mic button ────────────────────────────
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: _MicButton(
                          isListening: isListening,
                          isBusy: isBusy,
                          pulseAnim: _pulseAnim,
                          onTap: () {
                            if (isListening) {
                              notifier.stopListening();
                            } else if (!isBusy) {
                              notifier.startVoiceTurn();
                            }
                          },
                        ),
                      ),
                    ),

                    // ── Status label ──────────────────────────
                    if (isBusy)
                      Center(
                        child: Text(
                          _statusLabel(state.status),
                          style: TextStyle(
                              fontSize: 13, color: Colors.grey.shade500),
                        ),
                      ),

                    // ── Error ─────────────────────────────────
                    if (state.status == SleepVuiStatus.error &&
                        state.errorMessage != null)
                      Container(
                        margin: const EdgeInsets.only(top: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          state.errorMessage!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 13),
                        ),
                      ),

                    // ── Conversation history ───────────────────
                    ...state.history.map((msg) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _ChatBubble(
                        text: msg.text,
                        isUser: msg.isUser,
                        intentLabel: (!msg.isUser && msg.intent != null)
                            ? _intentLabel(
                            msg.intent!, msg.confidence ?? 0)
                            : null,
                      ),
                    )),

                    // ── Tip cards (latest response only) ───────
                    if (state.tips != null && state.tips!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      ...state.tips!.map((t) => _SleepTipCard(tip: t)),
                    ],

                    // ── Routine stepper ────────────────────────
                    if (state.routineSteps != null &&
                        state.routineSteps!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _RoutineStepper(steps: state.routineSteps!),
                    ],

                    // ── Suggestion chips ───────────────────────
                    if (state.suggestions != null &&
                        state.suggestions!.isNotEmpty &&
                        !isBusy) ...[
                      const SizedBox(height: 12),
                      _SuggestionChips(
                        suggestions: state.suggestions!,
                        onTap: (s) => notifier.sendSuggestion(s),
                      ),
                    ],

                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),

            // ── Text input bar ────────────────────────────────
            _TextInputBar(
              controller: _textController,
              enabled: !isBusy,
              onSend: () {
                final text = _textController.text.trim();
                if (text.isEmpty) return;
                _textController.clear();
                notifier.sendTextMessage(text);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _statusLabel(SleepVuiStatus s) {
    switch (s) {
      case SleepVuiStatus.listening:  return 'Listening…';
      case SleepVuiStatus.processing: return 'Thinking…';
      case SleepVuiStatus.speaking:   return 'Speaking…';
      default:                         return '';
    }
  }

  String _intentLabel(SleepIntent intent, double confidence) {
    final pct = (confidence * 100).toStringAsFixed(0);
    return 'intent: ${intent.name}  $pct%';
  }
}

// ════════════════════════════════════════════════════════════════
// 2. MIC BUTTON
// ════════════════════════════════════════════════════════════════

class _MicButton extends StatelessWidget {
  final bool isListening;
  final bool isBusy;
  final Animation<double> pulseAnim;
  final VoidCallback onTap;

  const _MicButton({
    required this.isListening,
    required this.isBusy,
    required this.pulseAnim,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final circle = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isListening
              ? const Color(0xFF1a1a1a)
              : const Color(0xFFD9D9D9),
        ),
        child: Icon(
          isListening ? Icons.stop_rounded : Icons.mic,
          size: 52,
          color: Colors.white,
        ),
      ),
    );

    if (isListening) {
      return AnimatedBuilder(
        animation: pulseAnim,
        builder: (_, child) =>
            Transform.scale(scale: pulseAnim.value, child: child),
        child: circle,
      );
    }
    return circle;
  }
}

// ════════════════════════════════════════════════════════════════
// 3. CHAT BUBBLE
// ════════════════════════════════════════════════════════════════

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final String? intentLabel;

  const _ChatBubble({
    required this.text,
    required this.isUser,
    this.intentLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
      isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Container(
          constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.82),
          padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isUser
                ? const Color(0xFF1a1a1a)
                : const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(isUser ? 16 : 4),
              bottomRight: Radius.circular(isUser ? 4 : 16),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              height: 1.5,
              color: isUser ? Colors.white : Colors.black87,
            ),
          ),
        ),
        if (intentLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4),
            child: Text(
              intentLabel!,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 4. SUGGESTION CHIPS
// ════════════════════════════════════════════════════════════════

class _SuggestionChips extends StatelessWidget {
  final List<String> suggestions;
  final ValueChanged<String> onTap;

  const _SuggestionChips({
    required this.suggestions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: suggestions
          .map((s) => GestureDetector(
        onTap: () => onTap(s),
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF2F2F2),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: Colors.grey.shade300),
          ),
          child: Text(
            s,
            style: const TextStyle(
                fontSize: 13, color: Colors.black87),
          ),
        ),
      ))
          .toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 5. SLEEP TIP CARD
// ════════════════════════════════════════════════════════════════

class _SleepTipCard extends StatelessWidget {
  final SleepTip tip;
  const _SleepTipCard({required this.tip});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceVariant
            .withOpacity(0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Theme.of(context).dividerColor.withOpacity(0.4),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(tip.emoji, style: const TextStyle(fontSize: 22)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip.title,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 3),
                Text(
                  tip.body,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withOpacity(0.65),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 6. ROUTINE STEPPER
// ════════════════════════════════════════════════════════════════

class _RoutineStepper extends StatelessWidget {
  final List<String> steps;
  const _RoutineStepper({required this.steps});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding:
      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a2e).withOpacity(0.05),
        borderRadius: BorderRadius.circular(14),
        border:
        Border.all(color: const Color(0xFF9fe1cb).withOpacity(0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🌙', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 8),
              Text(
                '30-min wind-down',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF0f6e56),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...steps.asMap().entries.map((e) => _StepRow(
            index: e.key,
            text: e.value,
            isLast: e.key == steps.length - 1,
          )),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int index;
  final String text;
  final bool isLast;

  const _StepRow({
    required this.index,
    required this.text,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0f6e56).withOpacity(0.7),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1.5,
                      color: const Color(0xFF9fe1cb).withOpacity(0.5),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  height: 1.5,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.75),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 7. TEXT INPUT BAR
// ════════════════════════════════════════════════════════════════

class _TextInputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onSend;

  const _TextInputBar({
    required this.controller,
    required this.enabled,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              enabled: enabled,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                hintText: 'or type here…',
                hintStyle: TextStyle(
                    color: Colors.grey.shade400, fontSize: 14),
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: enabled ? onSend : null,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: enabled
                    ? const Color(0xFF1a1a1a)
                    : Colors.grey.shade300,
              ),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
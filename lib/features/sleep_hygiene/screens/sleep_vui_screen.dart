// sleep_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/sleep_content.dart';
import '../../breathing_exercises/screens/breathing_exercises_page.dart';
import '../../emergency_support/screens/emergency_support_page.dart';
import '../../mindfulness/screens/mindfulness_page.dart';
import '../../mood_tracking/screens/mood_tracking_page.dart';
import '../services/sleep_engine.dart';
import '../themes/sky_theme.dart';

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
  late Animation<double>   _pulseAnim;
  final ScrollController   _scrollController = ScrollController();

  // ── Theme state ────────────────────────────────────────────────
  late SkyPeriod _period;
  bool           _isManualOverride = false;
  Timer?         _overrideTimer;
  Timer?         _realTimeTimer;
  bool _isImageBackground = true;
  int            _syncPressCount = 0;

  // ── Scroll-aware controls visibility ──────────────────────────
  bool   _showControls      = true;
  double _lastScrollOffset  = 0.0;
  static const double _kScrollHideThreshold = 10.0;

  static const Duration _kOverrideDuration = Duration(minutes: 3);

  static SkyPeriod _nextPeriod(SkyPeriod p) {
    const cycle = SkyPeriod.values;
    return cycle[(p.index + 1) % cycle.length];
  }

  void _toggleTheme() {
    final actual = computeSkyPeriod();

    // If on image background, enter sky system at real clock period
    if (_isImageBackground) {
      setState(() {
        _isImageBackground = false;
        _isManualOverride = false;
        _period = actual;
        _syncPressCount = 0; // reset counter on entry
      });
      return;
    }

    // After 4 presses (full cycle through all 4 periods), return to image
    _syncPressCount++;
    if (_syncPressCount >= 4) {
      setState(() {
        _isImageBackground = true;
        _syncPressCount = 0;
      });
      _overrideTimer?.cancel();
      return;
    }

    // Cycle to next period
    final newPeriod = _nextPeriod(_period);
    setState(() {
      _period = newPeriod;
      _isManualOverride = newPeriod != actual;
    });
    _overrideTimer?.cancel();
  }

  void _revertToRealTheme() {
    if (!mounted) return;
    final actual = computeSkyPeriod();
    setState(() { _period = actual; _isManualOverride = false; });
    final snackTheme = themeForPeriod(actual);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: snackTheme.chipBg,
      content: Text(
        '${snackTheme.celestialEmoji} Back to real time · ${actual.name}',
        style: TextStyle(color: snackTheme.textPrimary),
      ),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── Scroll listener ────────────────────────────────────────────
  void _onChatScroll() {
    final offset = _scrollController.offset;
    final delta  = offset - _lastScrollOffset;

    if (delta.abs() < _kScrollHideThreshold) return;

    final shouldShow = delta < 0; // scrolling up → show
    if (shouldShow != _showControls) {
      setState(() => _showControls = shouldShow);
    }
    _lastScrollOffset = offset;
  }

  @override
  void initState() {
    super.initState();

    _period = computeSkyPeriod();
    assert(() {
      debugPrint('SleepScreen init — local hour: ${DateTime.now().toLocal().hour}, period: ${_period.name}');
      return true;
    }());

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _realTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!_isManualOverride && !_isImageBackground && mounted) {
        final actual = computeSkyPeriod();
        if (actual != _period) setState(() => _period = actual);
      }
    });

    _scrollController.addListener(_onChatScroll);
  }

  @override
  void dispose() {
    _overrideTimer?.cancel();
    _realTimeTimer?.cancel();
    _pulseController.dispose();
    _scrollController.removeListener(_onChatScroll);
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
    final statusBarHeight = MediaQuery.of(context).padding.top;
    final state    = ref.watch(sleepVuiNotifierProvider);
    final notifier = ref.read(sleepVuiNotifierProvider.notifier);
    final theme    = _isImageBackground ? imageTheme : themeForPeriod(_period);

    ref.listen<SleepVuiState>(sleepVuiNotifierProvider, (prev, next) {

      if (next.shouldExit && !(prev?.shouldExit ?? false)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
        return;
      }

      if (next.pendingRoute != null &&
          prev?.pendingRoute != next.pendingRoute) {
        final route = next.pendingRoute!;
        notifier.clearPendingRoute();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Widget? page;
          switch (route) {
            case '/emergency':   page = const EmergencySupportPage();   break;
            case '/breathing':   page = const BreathingExercisesPage(); break;
            case '/mindfulness': page = const MindfulnessPage();        break;
            case '/mood':        page = const MoodTrackingPage();       break;
          }
          if (page != null) {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => page!),
            );
          }
        });
      }

      if (next.history.length != (prev?.history.length ?? 0)) {
        _scrollToBottom();
        // Always reveal controls when a new message arrives
        if (!_showControls) {
          setState(() => _showControls = true);
        }
      }
    });

    final bool isListening  = state.status == SleepVuiStatus.listening;
    final bool isProcessing = state.status == SleepVuiStatus.processing;
    final bool isSpeaking   = state.status == SleepVuiStatus.speaking;
    final bool isBusy       = isListening || isProcessing || isSpeaking;

    // Always keep controls visible while the VUI is active
    final bool forceShowControls = _showControls || isBusy;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor:          Colors.transparent,
        statusBarIconBrightness: (_period == SkyPeriod.day || _period == SkyPeriod.morning)
            ? Brightness.dark
            : Brightness.light,
      ),
      child: Scaffold(
        extendBody:             true,
        extendBodyBehindAppBar: true,
        backgroundColor:        Colors.transparent,
        body: AnimatedContainer(
          duration: const Duration(milliseconds: 800),
          color: theme.gradientColors[0],
          child: Stack(
            children: [

              // ── Background: image OR sky ──────────────────────────
              if (_isImageBackground)
                Positioned.fill(
                  child: Image.asset(
                    'assets/images/app_background.png',
                    fit: BoxFit.cover,
                  ),
                )
              else ...[
                // Status bar fill
                Positioned(
                  top: 0, left: 0, right: 0,
                  height: statusBarHeight,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 800),
                    color: theme.gradientColors[0],
                  ),
                ),
                // Sky animation
                Positioned(
                  top:    statusBarHeight,
                  left:   0,
                  right:  0,
                  bottom: 0,
                  child: _SkyBackground(
                    scrollController: _scrollController,
                    period:           _period,
                  ),
                ),
              ],

              // ── All UI content ────────────────────────────────────
              SafeArea(
                child: Stack(
                  children: [

                    // ── Chat scroll area ────────────────────────────
                    Positioned.fill(
                      child: SingleChildScrollView(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(16, 130, 16, 160),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [

                            ...state.history.map((msg) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _ChatBubble(
                                text:        msg.text,
                                isUser:      msg.isUser,
                                theme:       theme,
                                intentLabel: (!msg.isUser && msg.intent != null)
                                    ? _intentLabel(msg.intent!, msg.confidence ?? 0)
                                    : null,
                              ),
                            )),

                            if (isProcessing || isSpeaking)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: _ThinkingPill(accentColor: const Color(0xFF3F51B5)),
                                ),
                              ),

                            if (state.tips != null && state.tips!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              ...state.tips!.map((t) =>
                                  _SleepTipCard(tip: t, theme: theme)),
                            ],

                            if (state.routineSteps != null &&
                                state.routineSteps!.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              _RoutineStepper(
                                  steps: state.routineSteps!, theme: theme),
                            ],

                            if (state.suggestions != null &&
                                state.suggestions!.isNotEmpty &&
                                !isBusy) ...[
                              const SizedBox(height: 12),
                              _SuggestionChips(
                                suggestions: state.suggestions!,
                                theme:       theme,
                                onTap: (s) => notifier.sendSuggestion(s),
                              ),
                            ],

                            const SizedBox(height: 16),
                          ],
                        ),
                      ),
                    ),

                    // ── Bottom fade ─────────────────────────────────
                    Positioned(
                      bottom: 0, left: 0, right: 0,
                      height: 160,
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end:   Alignment.topCenter,
                              stops: const [0.0, 0.6, 1.0],
                              colors: _isImageBackground
                                  ? [
                                Colors.white.withOpacity(0.6),
                                Colors.white.withOpacity(0.2),
                                Colors.transparent,
                              ]
                                  : [
                                theme.gradientColors[0].withOpacity(0.92),
                                theme.gradientColors[0].withOpacity(0.45),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Header ─────────────────────────────────────
                    Positioned(
                      top: 0, left: 0, right: 0,
                      child: AnimatedSlide(
                        offset: forceShowControls
                            ? Offset.zero
                            : const Offset(0, -1),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOut,
                        child: AnimatedOpacity(
                          opacity: forceShowControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 280),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: () => Navigator.of(context).pop(),
                                  style: IconButton.styleFrom(
                                    backgroundColor: _isImageBackground
                                        ? const Color(0xFF3F51B5)
                                        : theme.accentColor.withOpacity(0.2),
                                    foregroundColor: _isImageBackground
                                        ? Colors.white
                                        : theme.textPrimary,
                                    shape: const CircleBorder(),
                                  ),
                                  icon: const Icon(Icons.arrow_back_rounded, size: 24),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Text(
                                    'Sleep Hygiene',
                                    style: TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: _isImageBackground
                                          ? const Color(0xFF3F51B5)
                                          : theme.textPrimary,
                                    ),
                                  ),
                                ),
                                _SkyControlButton(
                                  icon:  Icons.sync_rounded,
                                  onTap: _toggleTheme,
                                  color: _isImageBackground
                                      ? const Color(0xFF3F51B5)
                                      : theme.accentColor,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    // ── Mic ────────────────────────────────────────
                    Positioned(
                      bottom: 24, left: 0, right: 0,
                      child: AnimatedSlide(
                        offset: forceShowControls
                            ? Offset.zero
                            : const Offset(0, 1),
                        duration: const Duration(milliseconds: 320),
                        curve: Curves.easeInOut,
                        child: AnimatedOpacity(
                          opacity: forceShowControls ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 280),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _MicButton(
                                isListening:       isListening,
                                isBusy:            isBusy,
                                pulseAnim:         _pulseAnim,
                                accentColor:       theme.accentColor,
                                isImageBackground: _isImageBackground,
                                onTap: () {
                                  if (isListening) {
                                    notifier.stopListening();
                                  } else if (!isBusy) {
                                    notifier.startVoiceTurn();
                                  }
                                },
                              ),
                              if (state.status == SleepVuiStatus.error &&
                                  state.errorMessage != null)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                                  child: Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade900.withOpacity(0.5),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                          color: Colors.red.shade700.withOpacity(0.5)),
                                    ),
                                    child: Text(
                                      state.errorMessage!,
                                      style: TextStyle(
                                          color: Colors.red.shade200, fontSize: 13),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // ── Scroll-to-bottom FAB (shown when controls hidden) ──
                    AnimatedPositioned(
                      duration: const Duration(milliseconds: 320),
                      curve: Curves.easeInOut,
                      bottom: forceShowControls ? -60 : 24,
                      right: 20,
                      child: AnimatedOpacity(
                        opacity: forceShowControls ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 280),
                        child: IgnorePointer(
                          ignoring: forceShowControls,
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _showControls = true);
                              _scrollToBottom();
                            },
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isImageBackground
                                    ? const Color(0xFF3F51B5)
                                    : theme.accentColor.withOpacity(0.85),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.keyboard_arrow_up_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
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
      ),
    );
  }

  String _intentLabel(SleepIntent intent, double confidence) {
    final pct = (confidence * 100).toStringAsFixed(0);
    return 'intent: ${intent.name}  $pct%';
  }

}

// ════════════════════════════════════════════════════════════════
// 2. SKY CONTROL BUTTON
// ════════════════════════════════════════════════════════════════

class _SkyControlButton extends StatefulWidget {
  final IconData?    icon;
  final String?      label;
  final VoidCallback onTap;
  final Color        color;

  const _SkyControlButton({
    this.icon,
    this.label,
    required this.onTap,
    required this.color,
  });

  @override
  State<_SkyControlButton> createState() => _SkyControlButtonState();
}

class _SkyControlButtonState extends State<_SkyControlButton>
    with SingleTickerProviderStateMixin {

  late AnimationController _spin;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  void _handleTap() {
    _spin.forward(from: 0.0);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _handleTap,
      child: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withOpacity(0.12),
        ),
        alignment: Alignment.center,
        child: AnimatedBuilder(
          animation: _spin,
          builder: (_, child) => Transform.rotate(
            angle: _spin.value * 2 * 3.14159,
            child: child,
          ),
          child: Icon(widget.icon ?? Icons.sync_rounded,
              color: widget.color, size: 18),
        ),
      ),
    );
  }
}


// ════════════════════════════════════════════════════════════════
// 3. SKY BACKGROUND
// ════════════════════════════════════════════════════════════════

class _SkyBackground extends StatefulWidget {
  final ScrollController scrollController;
  final SkyPeriod        period;

  const _SkyBackground({
    required this.scrollController,
    required this.period,
  });

  @override
  State<_SkyBackground> createState() => _SkyBackgroundState();
}

class _SkyBackgroundState extends State<_SkyBackground>
    with TickerProviderStateMixin {

  late AnimationController _cloudDrift;
  late Animation<double>   _cloudDriftAnim;

  late AnimationController _celestialRise;
  late Animation<double>   _celestialRiseAnim;

  late AnimationController _entryController;
  late Animation<double>   _entryAnim;
  bool _entryDone = false;

  double _scrollOffset       = 0.0;
  double _lastNotifiedOffset = 0.0;
  static const double _kScrollThreshold = 4.0;

  static const List<List<double>> _stars = [
    [0.05,0.04,2.5],[0.15,0.10,1.5],[0.28,0.07,2.0],[0.42,0.03,1.5],
    [0.55,0.09,2.5],[0.68,0.05,1.5],[0.80,0.12,2.0],[0.92,0.04,2.5],
    [0.10,0.18,1.5],[0.35,0.22,2.0],[0.60,0.17,1.5],[0.78,0.25,2.0],
    [0.90,0.20,1.5],[0.20,0.32,2.5],[0.48,0.30,1.5],[0.72,0.35,2.0],
    [0.85,0.40,1.5],[0.08,0.45,2.0],[0.33,0.50,1.5],[0.55,0.48,2.5],
    [0.70,0.55,1.5],[0.88,0.52,2.0],[0.18,0.60,1.5],[0.40,0.65,2.0],
    [0.62,0.62,1.5],[0.80,0.68,2.5],[0.05,0.72,1.5],[0.25,0.75,2.0],
    [0.50,0.78,1.5],[0.75,0.80,2.0],[0.93,0.75,1.5],[0.12,0.85,2.5],
    [0.38,0.88,1.5],[0.60,0.90,2.0],[0.82,0.92,1.5],
  ];

  @override
  void initState() {
    super.initState();

    _cloudDrift = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 40),
    )..repeat();
    _cloudDriftAnim = Tween<double>(begin: 0, end: 1).animate(_cloudDrift);

    _celestialRise = AnimationController(
      vsync: this,
      duration: themeForPeriod(widget.period).celestialDuration,
      value:    clockProgressForPeriod(widget.period),
    );
    _celestialRiseAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _celestialRise, curve: Curves.easeInOut),
    );
    _celestialRise.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _celestialRise.value = clockProgressForPeriod(widget.period);
        _celestialRise.forward();
      }
    });
    _celestialRise.forward();

    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _entryAnim = CurvedAnimation(
      parent: _entryController,
      curve:  Curves.easeOutCubic,
    );
    _entryController.forward().then((_) {
      if (mounted) setState(() => _entryDone = true);
    });

    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(_SkyBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.period != oldWidget.period) {
      _celestialRise.duration = themeForPeriod(widget.period).celestialDuration;
      _celestialRise.value    = clockProgressForPeriod(widget.period);
      _celestialRise.forward();
    }
  }

  @override
  void dispose() {
    _cloudDrift.dispose();
    _celestialRise.dispose();
    _entryController.dispose();
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    final offset = widget.scrollController.offset;
    if ((offset - _lastNotifiedOffset).abs() >= _kScrollThreshold) {
      _lastNotifiedOffset = offset;
      if (mounted) setState(() => _scrollOffset = offset);
    }
  }

  @override
  Widget build(BuildContext context) {
    final w       = MediaQuery.of(context).size.width;
    final h       = MediaQuery.of(context).size.height;
    final theme   = themeForPeriod(widget.period);
    final isNight = widget.period == SkyPeriod.night;

    return AnimatedBuilder(
      animation: Listenable.merge([_cloudDriftAnim, _celestialRiseAnim, _entryAnim]),
      builder: (context, _) {
        final scrollParallax = _scrollOffset * 0.3;

        double cloudPos(double phase) =>
            (h + 80) - ((_cloudDriftAnim.value + phase) % 1.0) * (h + 200);

        final cloud1Base = cloudPos(0.0)  - scrollParallax;
        final cloud2Base = cloudPos(0.33) - scrollParallax * 0.7;
        final cloud3Base = cloudPos(0.66) - scrollParallax * 0.5;

        final entryLift = _entryDone ? 0.0 : (1.0 - _entryAnim.value) * 300.0;

        final t          = _celestialRiseAnim.value;
        const pad        = 60.0;
        const apex       = 80.0;
        const base       = 180.0;
        const k          = (base - apex) / 0.25;
        final arcY       = apex + k * (t - 0.5) * (t - 0.5);
        final celestialX = -pad + t * (w + 2 * pad);
        final celestialY = arcY;

        final entrySlide = _entryDone
            ? 0.0
            : (1.0 - _entryAnim.value) * (isNight ? -120.0 : 120.0);

        return Stack(
          children: [
            // ── Sky gradient ───────────────────────────────────────
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin:  Alignment.topCenter,
                    end:    Alignment.bottomCenter,
                    colors: theme.gradientColors,
                    stops:  theme.gradientStops,
                  ),
                ),
              ),
            ),

            // ── Nebula glow 1 ──────────────────────────────────────
            Positioned(
              top: -60, right: -80,
              child: Container(
                width: 280, height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    theme.nebulaColor1.withOpacity(0.07),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),

            // ── Nebula glow 2 ──────────────────────────────────────
            Positioned(
              bottom: -40, left: -60,
              child: Container(
                width: 220, height: 220,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    theme.nebulaColor2.withOpacity(0.08),
                    Colors.transparent,
                  ]),
                ),
              ),
            ),

            // ── Stars (night only) ─────────────────────────────────
            if (theme.showStars)
              ..._stars.asMap().entries.map((e) {
                final i = e.key;
                final s = e.value;
                return Positioned(
                  left: w * s[0],
                  top:  h * s[1],
                  child: Container(
                    width: s[2], height: s[2],
                    decoration: const BoxDecoration(
                        shape: BoxShape.circle, color: Colors.white),
                  )
                      .animate(
                    onPlay: (c) => c.repeat(reverse: true),
                    delay: Duration(milliseconds: i * 180),
                  )
                      .custom(
                    duration: Duration(milliseconds: 1400 + (i % 5) * 200),
                    builder: (_, v, child) =>
                        Opacity(opacity: 0.15 + v * 0.75, child: child),
                  ),
                );
              }),

            // ── Sun glow halo ──────────────────────────────────────
            if (theme.showHorizonGlow)
              Positioned(
                left: celestialX + entrySlide - 38,
                top:  celestialY - 38,
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(colors: [
                      theme.horizonGlowColor.withOpacity(theme.horizonGlowOpacity),
                      Colors.transparent,
                    ]),
                  ),
                ),
              ),

            // ── Celestial body ─────────────────────────────────────
            Positioned(
              left: celestialX + entrySlide,
              top:  celestialY,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 600),
                child: Text(
                  theme.celestialEmoji,
                  key: ValueKey(widget.period),
                  style: TextStyle(fontSize: theme.celestialSize),
                ),
              ),
            ),

            // ── Cloud 1 — left ─────────────────────────────────────
            Positioned(
              left: -8,
              top:  cloud1Base + entryLift,
              child: Opacity(
                opacity: theme.cloudOpacityPrimary,
                child: Text('☁️',
                    style: TextStyle(fontSize: isNight ? 64.0 : 72.0)),
              ),
            ),

            // ── Cloud 2 — right ────────────────────────────────────
            Positioned(
              right: -12,
              top:   cloud2Base + entryLift,
              child: Opacity(
                opacity: theme.cloudOpacitySecondary,
                child: Text('☁️',
                    style: TextStyle(fontSize: isNight ? 48.0 : 56.0)),
              ),
            ),

            // ── Cloud 3 — mid ──────────────────────────────────────
            if (theme.showThirdCloud)
              Positioned(
                left: w * 0.3,
                top:  cloud3Base + entryLift,
                child: Opacity(
                  opacity: 0.6,
                  child: const Text('☁️', style: TextStyle(fontSize: 52)),
                ),
              ),

            // ── Horizon glow bar ───────────────────────────────────
            if (theme.showHorizonGlow)
              Positioned(
                bottom: 0, left: 0, right: 0,
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end:   Alignment.topCenter,
                      colors: [
                        theme.horizonGlowColor
                            .withOpacity(theme.horizonGlowOpacity),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 4. MIC SECTION
// ════════════════════════════════════════════════════════════════

class _MicSection extends StatelessWidget {
  final bool              isListening;
  final bool              isBusy;
  final Animation<double> pulseAnim;
  final SleepVuiStatus    status;
  final Color             accentColor;
  final Color             textSecondary;
  final VoidCallback      onTap;

  const _MicSection({
    required this.isListening,
    required this.isBusy,
    required this.pulseAnim,
    required this.status,
    required this.accentColor,
    required this.textSecondary,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MicButton(
            isListening:       isListening,
            isBusy:            isBusy,
            pulseAnim:         pulseAnim,
            accentColor:       accentColor,
            isImageBackground: false,
            onTap:             onTap,
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 5. MIC BUTTON
// ════════════════════════════════════════════════════════════════

class _MicButton extends StatelessWidget {
  final bool              isListening;
  final bool              isBusy;
  final Animation<double> pulseAnim;
  final Color             accentColor;
  final bool              isImageBackground;
  final VoidCallback      onTap;

  const _MicButton({
    required this.isListening,
    required this.isBusy,
    required this.pulseAnim,
    required this.accentColor,
    required this.isImageBackground,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final circle = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160, height: 160,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: isImageBackground
              ? (isListening
              ? const Color(0xFF3F51B5).withOpacity(0.85)
              : const Color(0xFF3F51B5))
              : (isListening
              ? accentColor.withOpacity(0.15)
              : Colors.white.withOpacity(0.08)),
          border: isImageBackground
              ? null
              : Border.all(
            color: isListening
                ? accentColor.withOpacity(0.6)
                : Colors.white.withOpacity(0.15),
            width: 1.5,
          ),
          boxShadow: isListening
              ? [BoxShadow(
              color: (isImageBackground
                  ? const Color(0xFF3F51B5)
                  : accentColor).withOpacity(0.30),
              blurRadius: 32, spreadRadius: 6)]
              : [],
        ),
        child: Icon(
          isListening ? Icons.stop_rounded : Icons.mic_rounded,
          size: 160 * 0.6,
          color: isImageBackground
              ? Colors.white
              : (isListening ? accentColor : Colors.white.withOpacity(0.85)),
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

class _ThinkingPill extends StatefulWidget {
  final Color accentColor;
  const _ThinkingPill({required this.accentColor});

  @override
  State<_ThinkingPill> createState() => _ThinkingPillState();
}

class _ThinkingPillState extends State<_ThinkingPill>
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color:        widget.accentColor.withOpacity(0.12),
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(16),
          topRight:    Radius.circular(16),
          bottomRight: Radius.circular(16),
          bottomLeft:  Radius.circular(4),
        ),
        border: Border.all(
          color: widget.accentColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(3, (i) {
          return AnimatedBuilder(
            animation: _controller,
            builder: (_, __) {
              final phase = ((_controller.value - i * 0.25) % 1.0);
              final offset = phase < 0.5
                  ? -4.0 * (1 - (phase / 0.5 - 1).abs())
                  : 0.0;
              return Padding(
                padding: EdgeInsets.only(right: i < 2 ? 4.0 : 0),
                child: Transform.translate(
                  offset: Offset(0, offset),
                  child: Container(
                    width: 6, height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.accentColor.withOpacity(0.8),
                    ),
                  ),
                ),
              );
            },
          );
        }),
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 6. CHAT BUBBLE
// ════════════════════════════════════════════════════════════════

class _ChatBubble extends StatefulWidget {
  final String   text;
  final bool     isUser;
  final SkyTheme theme;
  final String?  intentLabel;
  final bool     isThinking;

  const _ChatBubble({
    required this.text,
    required this.isUser,
    required this.theme,
    this.intentLabel,
    this.isThinking = false,
  });

  @override
  State<_ChatBubble> createState() => _ChatBubbleState();
}

class _ChatBubbleState extends State<_ChatBubble>
    with SingleTickerProviderStateMixin {

  late AnimationController _controller;
  late Animation<double>   _scale;
  late Animation<double>   _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );

    _scale = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );

    _fade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    final delay = widget.isUser
        ? Duration.zero
        : const Duration(milliseconds: 60);

    Future.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<String> _splitSentences(String text) {
    final parts = text.split(RegExp(r'(?<=[.!?])\s+(?=[A-Z])'));
    if (parts.length <= 1 || text.length < 80) return [text];
    return parts.where((s) => s.trim().length > 5).toList();
  }

  static final _stepPattern = RegExp(
    r'^(?:step\s*)?\d+[.):\-]\s*.+',
    caseSensitive: false,
    multiLine: true,
  );

  List<String>? _extractSteps(String text) {
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();

    final matched = lines.where((l) => _stepPattern.hasMatch(l)).toList();
    if (matched.length >= 2) {
      return lines.map((l) {
        return l.replaceFirst(RegExp(r'^(?:step\s*)?\d+[.):\-]\s*', caseSensitive: false), '').trim();
      }).where((l) => l.isNotEmpty).toList();
    }

    final inlineSteps = RegExp(r'\d+[.)]\s*([^0-9]+?)(?=\d+[.)]|$)')
        .allMatches(text)
        .map((m) => m.group(1)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
    if (inlineSteps.length >= 2) return inlineSteps;

    return null;
  }

  Widget _buildContent(TextStyle baseStyle) {
    final text = widget.text;

    final steps = !widget.isUser ? _extractSteps(text) : null;
    if (steps != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: steps.asMap().entries.map((e) {
          return Padding(
            padding: EdgeInsets.only(top: e.key == 0 ? 0 : 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.only(top: 1, right: 10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.theme.accentColor.withOpacity(0.18),
                    border: Border.all(
                      color: widget.theme.accentColor.withOpacity(0.4),
                      width: 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${e.key + 1}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: widget.theme.accentColor,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(e.value, style: baseStyle),
                ),
              ],
            ),
          );
        }).toList(),
      );
    }

    final sentences = _splitSentences(text);
    if (sentences.length <= 1) return Text(text, style: baseStyle);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sentences.asMap().entries.map((e) => Padding(
        padding: EdgeInsets.only(top: e.key == 0 ? 0 : 8),
        child: Text(e.value, style: baseStyle),
      )).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textStyle = TextStyle(
      fontSize: 14,
      height:   1.5,
      color: widget.isUser
          ? widget.theme.textPrimary
          : widget.theme.textSecondary,
    );

    return Column(
      crossAxisAlignment: widget.isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        if (!widget.isUser && widget.isThinking)
          _ThinkingPill(accentColor: widget.theme.accentColor)
        else
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => FadeTransition(
              opacity: _fade,
              child: Align(
                alignment: widget.isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: ScaleTransition(
                  scale: _scale,
                  alignment: widget.isUser
                      ? Alignment.topRight
                      : Alignment.topLeft,
                  child: child,
                ),
              ),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.82,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: widget.isUser
                    ? widget.theme.userBubble
                    : widget.theme.assistBubble,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(widget.isUser ? 16 : 4),
                  bottomRight: Radius.circular(widget.isUser ? 4 : 16),
                ),
                border: Border.all(
                  color: widget.isUser
                      ? widget.theme.accentColor.withOpacity(0.2)
                      : Colors.white.withOpacity(0.06),
                  width: 1,
                ),
              ),
              child: _buildContent(textStyle),
            ),
          ),

        if (widget.intentLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: 3, left: 4),
            child: Text(
              widget.intentLabel!,
              style: TextStyle(
                fontSize: 11,
                color: widget.theme.textSecondary.withOpacity(0.5),
              ),
            ),
          ),
      ],
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 7. SUGGESTION CHIPS
// ════════════════════════════════════════════════════════════════

class _SuggestionChips extends StatelessWidget {
  final List<String>         suggestions;
  final SkyTheme             theme;
  final ValueChanged<String> onTap;

  const _SuggestionChips({
    required this.suggestions,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8, runSpacing: 8,
      children: suggestions.map((s) => GestureDetector(
        onTap: () => onTap(s),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color:        theme.chipBg,
            borderRadius: BorderRadius.circular(20),
            border:       Border.all(color: theme.chipBorder),
          ),
          child: Text(s,
              style: TextStyle(fontSize: 13, color: theme.textSecondary)),
        ),
      )).toList(),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 8. SLEEP TIP CARD
// ════════════════════════════════════════════════════════════════

class _SleepTipCard extends StatelessWidget {
  final SleepTip tip;
  final SkyTheme theme;
  const _SleepTipCard({required this.tip, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        theme.assistBubble,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.accentColor.withOpacity(0.2)),
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
                Text(tip.title,
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.textPrimary, fontSize: 14)),
                const SizedBox(height: 3),
                Text(tip.body,
                    style: TextStyle(
                        color: theme.textSecondary,
                        fontSize: 13, height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ════════════════════════════════════════════════════════════════
// 9. ROUTINE STEPPER
// ════════════════════════════════════════════════════════════════

class _RoutineStepper extends StatelessWidget {
  final List<String> steps;
  final SkyTheme     theme;
  const _RoutineStepper({required this.steps, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin:  const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        theme.assistBubble,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.accentColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Text('🌙', style: TextStyle(fontSize: 16)),
            const SizedBox(width: 8),
            Text('30-min wind-down',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.accentColor, fontSize: 14)),
          ]),
          const SizedBox(height: 10),
          ...steps.asMap().entries.map((e) => _StepRow(
            index:  e.key,
            text:   e.value,
            isLast: e.key == steps.length - 1,
            theme:  theme,
          )),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final int      index;
  final String   text;
  final bool     isLast;
  final SkyTheme theme;

  const _StepRow({
    required this.index,
    required this.text,
    required this.isLast,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            child: Column(children: [
              Container(
                width: 8, height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: theme.accentColor.withOpacity(0.7),
                ),
              ),
              if (!isLast)
                Expanded(child: Container(
                    width: 1.5,
                    color: theme.accentColor.withOpacity(0.25))),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(text,
                  style: TextStyle(
                      height: 1.5, color: theme.textSecondary, fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }
}
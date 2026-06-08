// sky_theme.dart
// Four-period dynamic sky: morning · day · afternoon · night.
// Drop-in replacement for the inline _SkyTheme / _nightTheme / _dayTheme
// that lived inside sleep_screen.dart.

import 'package:flutter/material.dart';

// ════════════════════════════════════════════════════════════════
// PERIOD ENUM + HELPERS
// ════════════════════════════════════════════════════════════════

enum SkyPeriod { morning, day, afternoon, night }

/// Maps the current local device hour to a [SkyPeriod].
///
/// Boundaries:
///   06:00–11:59  → morning
///   12:00–16:59  → day
///   17:00–19:59  → afternoon
///   20:00–05:59  → night
SkyPeriod computeSkyPeriod() {
  final h = DateTime.now().toLocal().hour;
  if (h >= 6  && h < 12) return SkyPeriod.morning;
  if (h >= 12 && h < 17) return SkyPeriod.day;
  if (h >= 17 && h < 20) return SkyPeriod.afternoon;
  return SkyPeriod.night;
}

/// Returns the matching [SkyTheme] palette for [period].
SkyTheme themeForPeriod(SkyPeriod period) {
  switch (period) {
    case SkyPeriod.morning:   return morningTheme;
    case SkyPeriod.day:       return dayTheme;
    case SkyPeriod.afternoon: return afternoonTheme;
    case SkyPeriod.night:     return nightTheme;
  }
}

/// Clock-based animation progress within a period (0.0 → 1.0).
///
/// Used to seed the celestial body's position when the screen opens
/// so it continues from the real current position in the sky.
double clockProgressForPeriod(SkyPeriod period) {
  final now  = DateTime.now().toLocal();
  final mins = now.hour * 60 + now.minute;
  switch (period) {
    case SkyPeriod.morning:
    // 06:00 (360 min) → 12:00 (720 min) · span 360 min
      return ((mins - 360) / 360).clamp(0.0, 1.0);
    case SkyPeriod.day:
    // 12:00 (720 min) → 17:00 (1020 min) · span 300 min
      return ((mins - 720) / 300).clamp(0.0, 1.0);
    case SkyPeriod.afternoon:
    // 17:00 (1020 min) → 20:00 (1200 min) · span 180 min
      return ((mins - 1020) / 180).clamp(0.0, 1.0);
    case SkyPeriod.night:
    // 20:00 → 06:00 next day · span 600 min · wraps midnight
      final since20 = mins >= 1200 ? mins - 1200 : mins + 240;
      return (since20 / 600).clamp(0.0, 1.0);
  }
}

// ════════════════════════════════════════════════════════════════
// THEME DATA CLASS
// ════════════════════════════════════════════════════════════════

class SkyTheme {
  // ── Sky gradient ──────────────────────────────────────────────
  final List<Color>  gradientColors;
  final List<double> gradientStops;

  // ── UI colours ────────────────────────────────────────────────
  final Color accentColor;
  final Color userBubble;
  final Color assistBubble;
  final Color chipBg;
  final Color chipBorder;
  final Color inputBg;
  final Color inputFill;
  final Color textPrimary;
  final Color textSecondary;

  // ── Nebula glows ──────────────────────────────────────────────
  final Color nebulaColor1;
  final Color nebulaColor2;

  // ── Celestial body ────────────────────────────────────────────
  final String   celestialEmoji;
  final double   celestialSize;
  /// True for night (moon) and morning (rising sun glow is lunar-style).
  /// False for day / afternoon (bright sun halo shown instead).
  final bool     showSunHalo;

  // ── Sky features ──────────────────────────────────────────────
  final bool   showStars;
  final double cloudOpacityPrimary;
  final double cloudOpacitySecondary;
  final bool   showThirdCloud;
  final bool   showHorizonGlow;
  final Color  horizonGlowColor;
  final double horizonGlowOpacity;

  // ── Animation ─────────────────────────────────────────────────
  /// Real-time duration of this period (drives the celestial arc speed).
  final Duration celestialDuration;

  // ── Toggle button ─────────────────────────────────────────────
  /// Emoji shown in the app-bar button — represents the NEXT period
  /// the user will switch to (i.e. what the button will change to).
  final String nextPeriodIcon;

  const SkyTheme({
    required this.gradientColors,
    required this.gradientStops,
    required this.accentColor,
    required this.userBubble,
    required this.assistBubble,
    required this.chipBg,
    required this.chipBorder,
    required this.inputBg,
    required this.inputFill,
    required this.textPrimary,
    required this.textSecondary,
    required this.nebulaColor1,
    required this.nebulaColor2,
    required this.celestialEmoji,
    required this.celestialSize,
    required this.showSunHalo,
    required this.showStars,
    required this.cloudOpacityPrimary,
    required this.cloudOpacitySecondary,
    required this.showThirdCloud,
    required this.showHorizonGlow,
    required this.horizonGlowColor,
    required this.horizonGlowOpacity,
    required this.celestialDuration,
    required this.nextPeriodIcon,
  });
}

// ════════════════════════════════════════════════════════════════
// PALETTES
// ════════════════════════════════════════════════════════════════

// ── 1. Night  (20:00–05:59) ────────────────────────────────────
const nightTheme = SkyTheme(
  gradientColors: [Color(0xFF080c18), Color(0xFF1a1a2e), Color(0xFF0f2035)],
  gradientStops:  [0.0, 0.5, 1.0],
  accentColor:    Color(0xFF9fe1cb),
  userBubble:     Color(0xFF1e3a52),
  assistBubble:   Color(0xFF12233a),
  chipBg:         Color(0xFF1a2e42),
  chipBorder:     Color(0xFF2e5068),
  inputBg:        Color(0xFF0f1e30),
  inputFill:      Color(0xFF1a2e42),
  textPrimary:    Color(0xFFe8f4f0),
  textSecondary:  Color(0xFF8ab4c8),
  nebulaColor1:   Color(0xFF9fe1cb),
  nebulaColor2:   Color(0xFF4a6fa5),
  celestialEmoji:          '🌙',
  celestialSize:           36,
  showSunHalo:             false,
  showStars:               true,
  cloudOpacityPrimary:     0.25,
  cloudOpacitySecondary:   0.18,
  showThirdCloud:          false,
  showHorizonGlow:         false,
  horizonGlowColor:        Color(0xFF000000), // unused
  horizonGlowOpacity:      0.0,
  celestialDuration:       Duration(hours: 10),
  nextPeriodIcon:          '', // cycles to morning
);

// ── 2. Morning  (06:00–11:59) ──────────────────────────────────
// Peach-to-sky-blue dawn palette.  Warm, soft, hopeful.
const morningTheme = SkyTheme(
  gradientColors: [Color(0xFFff9a9e), Color(0xFFfad0c4), Color(0xFF96c9e8)],
  gradientStops:  [0.0, 0.45, 1.0],
  accentColor:    Color(0xFFf4845f),
  userBubble:     Color(0xFFb85438),
  assistBubble:   Color(0xFFcb6545),
  chipBg:         Color(0xFFcb6545),
  chipBorder:     Color(0xFFf4a47a),
  inputBg:        Color(0xFFa34832),
  inputFill:      Color(0xFFcb6545),
  textPrimary:    Color(0xFFfff8f5),
  textSecondary:  Color(0xFFffe4d4),
  nebulaColor1:   Color(0xFFffb347),
  nebulaColor2:   Color(0xFFff6b6b),
  celestialEmoji:          '🌅',
  celestialSize:           44,
  showSunHalo:             true,
  showStars:               false,
  cloudOpacityPrimary:     0.70,
  cloudOpacitySecondary:   0.55,
  showThirdCloud:          true,
  showHorizonGlow:         true,
  horizonGlowColor:        Color(0xFFffb347),
  horizonGlowOpacity:      0.35,
  celestialDuration:       Duration(hours: 6),
  nextPeriodIcon:          '☀️', // cycles to day
);

// ── 3. Day  (12:00–16:59) ──────────────────────────────────────
// Bright cerulean blue sky — the existing day palette, unchanged.
const dayTheme = SkyTheme(
  gradientColors: [Color(0xFF4fc3f7), Color(0xFF81d4fa), Color(0xFFb3e5fc)],
  gradientStops:  [0.0, 0.5, 1.0],
  accentColor:    Color(0xFFf57c00),
  userBubble:     Color(0xFF0277bd),
  assistBubble:   Color(0xFF0288d1),
  chipBg:         Color(0xFF0288d1),
  chipBorder:     Color(0xFF4fc3f7),
  inputBg:        Color(0xFF0277bd),
  inputFill:      Color(0xFF0288d1),
  textPrimary:    Color(0xFFffffff),
  textSecondary:  Color(0xFFe1f5fe),
  nebulaColor1:   Color(0xFFffd54f),
  nebulaColor2:   Color(0xFFffffff),
  celestialEmoji:          '☀️',
  celestialSize:           44,
  showSunHalo:             true,
  showStars:               false,
  cloudOpacityPrimary:     0.85,
  cloudOpacitySecondary:   0.75,
  showThirdCloud:          true,
  showHorizonGlow:         true,
  horizonGlowColor:        Color(0xFFffe082),
  horizonGlowOpacity:      0.30,
  celestialDuration:       Duration(hours: 5),
  nextPeriodIcon:          '', // cycles to afternoon
);

// ── 4. Afternoon  (17:00–19:59) ────────────────────────────────
// Golden-hour sunset: deep violet crown → magenta band → amber base.
const afternoonTheme = SkyTheme(
  gradientColors: [
    Color(0xFF1a0533),
    Color(0xFF8b1e5a),
    Color(0xFFe8512d),
    Color(0xFFf9a825),
  ],
  gradientStops:  [0.0, 0.30, 0.65, 1.0],
  accentColor:    Color(0xFFffd166),
  userBubble:     Color(0xFF7b1e4a),
  assistBubble:   Color(0xFF5c1537),
  chipBg:         Color(0xFF7b1e4a),
  chipBorder:     Color(0xFFe8512d),
  inputBg:        Color(0xFF3d0f2a),
  inputFill:      Color(0xFF5c1537),
  textPrimary:    Color(0xFFfff3e0),
  textSecondary:  Color(0xFFffcc80),
  nebulaColor1:   Color(0xFFff6b35),
  nebulaColor2:   Color(0xFF9c27b0),
  celestialEmoji:          '',
  celestialSize:           44,
  showSunHalo:             true,
  showStars:               false,
  cloudOpacityPrimary:     0.70,
  cloudOpacitySecondary:   0.60,
  showThirdCloud:          true,
  showHorizonGlow:         true,
  horizonGlowColor:        Color(0xFFff6b35),
  horizonGlowOpacity:      0.45,
  celestialDuration:       Duration(hours: 3),
  nextPeriodIcon:          '🌙', // cycles to night
);

// ── 5. Image background  (app_background.png lavender palette) ─
// Used whenever _isImageBackground = true so all UI elements
// (bubbles, chips, mic, thinking pill) harmonise with the PNG
// instead of inheriting the last active sky-period colours.
const imageTheme = SkyTheme(
  gradientColors: [Color(0xFFc8ceed), Color(0xFFdde1f7), Color(0xFFf0f2fc)],
  gradientStops:  [0.0, 0.5, 1.0],
  accentColor:    Color(0xFF3F51B5),
  userBubble:    Color(0xFF9FA8DA),
  assistBubble:  Color(0xFF9FA8DA),
  chipBg:         Color(0xFF5C6BC0),
  chipBorder:     Color(0xFF7986CB),
  inputBg:        Color(0xFFFFFFFF),
  inputFill:      Color(0xFFEEF0FB),
  textPrimary:   Color(0xFFFFFFFF),
  textSecondary: Color(0xFFFFFFFF),
  nebulaColor1:   Color(0xFF9fa8da),
  nebulaColor2:   Color(0xFF8d9dc8),
  celestialEmoji:        '',
  celestialSize:         0,
  showSunHalo:           false,
  showStars:             false,
  cloudOpacityPrimary:   0,
  cloudOpacitySecondary: 0,
  showThirdCloud:        false,
  showHorizonGlow:       false,
  horizonGlowColor:      Color(0xFF000000),
  horizonGlowOpacity:    0.0,
  celestialDuration:     Duration(hours: 1),
  nextPeriodIcon:        '',
);

// lib/core/voice/voice_registry.dart
//
// Central connector — merges every module's voice strings into one map.
// The TtsService reads ONLY from here for preloadAll() and speak().
//


import 'package:mindmate/core/constants/sleep_content.dart';
import '../constants/home_content.dart';


class VoiceRegistry {
  VoiceRegistry._();

  /// Every spoken string in the app, keyed by 'module.intent.variant'.
  /// TtsService.preloadAll() iterates this map on first launch.
  static const Map<String, String> all = {
    ...HomeCorpus.all,
    ...SleepCorpus.all,
    // ...BreathingCorpus.all,
    // ...MindfulnessCorpus.all,
    // ...MoodVoiceCorpus.all,
    // ...EmergencyCorpus.all,
  };

  /// Convenience getter — throws clearly in debug if a key is missing.
  static String get(String key) {
    assert(all.containsKey(key), '[VoiceRegistry] Missing key: "$key"');
    return all[key]!;
  }
}
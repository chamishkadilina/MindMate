// lib/core/voice/home_corpus.dart
//
// All spoken strings for the Home module.
// Register in VoiceRegistry.all — do not call TtsService directly with raw text.

class HomeCorpus {
  HomeCorpus._();

  static const Map<String, String> all = {
    // ── Welcome & navigation ──────────────────────────────────────────────────
    'home.welcome':
    'Welcome to MindMate. Tap the microphone and tell me where you want to go.',
    'home.back':
    'You are back on the home page.',
    'home.notHeard':
    'I didn\'t catch that. Please try again.',
    'home.notFound':
    'I\'m not sure where to navigate. Try saying Breathing, Sleep, Mindfulness, Mood, or Emergency.',

    // ── Instructions (spoken once on startup, text loops forever) ────────────
    'home.instruction.0': 'Say Breathing to open Breathing Exercises.',
    'home.instruction.1': 'Say Sleep for Sleep Hygiene tips.',
    'home.instruction.2': 'Say Mindfulness to begin a session.',
    'home.instruction.3': 'Say Mood to track how you feel.',
    'home.instruction.4': 'Say Emergency for immediate support.',

    // ── Navigation confirmations ──────────────────────────────────────────────
    'nav.breathing':   'Opening Breathing Exercises.',
    'nav.emergency':   'Opening Emergency Support.',
    'nav.sleep':       'Opening Sleep Hygiene.',
    'nav.mindfulness': 'Opening Mindfulness.',
    'nav.mood':        'Opening Mood Tracking.',
  };
}
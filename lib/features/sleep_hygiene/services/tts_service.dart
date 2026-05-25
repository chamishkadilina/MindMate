// tts_service.dart
// Offline TTS using flutter_tts package.

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  final FlutterTts _tts = FlutterTts();
  bool _isInitialised = false;
  VoidCallback? _completionCallback;

  Future<void> initialise() async {
    if (_isInitialised) return;

    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.45);  // slightly slower — calming feel
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setCompletionHandler(() {
      _completionCallback?.call();
    });

    _isInitialised = true;
  }

  Future<void> speak(String text) async {
    if (!_isInitialised) await initialise();
    await stop();
    await _tts.speak(text);
  }

  Future<void> stop() async {
    await _tts.stop();
  }

  void onComplete(VoidCallback callback) {
    _completionCallback = callback;
  }
}
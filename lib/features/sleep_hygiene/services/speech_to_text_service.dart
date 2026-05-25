// speech_to_text_service.dart

import 'package:speech_to_text/speech_to_text.dart' as stt;

class SpeechException implements Exception {
  final String message;
  const SpeechException(this.message);
  @override
  String toString() => 'SpeechException: $message';
}

class SpeechToTextService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isInitialised = false;
  String _lastResult = '';
  bool _resultReady = false;

  Future<bool> initialise() async {
    if (_isInitialised) return true;
    _isInitialised = await _speech.initialize(
      onError: (error) {
        // Only log — never throw
        // ignore: avoid_print
        print('[STT] error: ${error.errorMsg} permanent=${error.permanent}');
      },
      onStatus: (status) {
        // ignore: avoid_print
        print('[STT] status: $status');
      },
    );
    return _isInitialised;
  }

  Future<String> listen() async {
    if (!_isInitialised) {
      final ok = await initialise();
      if (!ok) {
        throw const SpeechException(
            'Speech recognition not available on this device.');
      }
    }

    if (_speech.isListening) await _speech.stop();

    _lastResult = '';
    _resultReady = false;

    await _speech.listen(
      onResult: (result) {
        _lastResult = result.recognizedWords;
        if (result.finalResult) {
          _resultReady = true;
        }
      },
      listenFor: const Duration(seconds: 10),
      pauseFor: const Duration(seconds: 2),
      localeId: 'en_US',
      listenMode: stt.ListenMode.confirmation,
      cancelOnError: false,
    );

    // Poll until result ready or timeout
    for (int i = 0; i < 120; i++) {
      await Future.delayed(const Duration(milliseconds: 100));
      if (_resultReady) break;
      if (!_speech.isListening && _lastResult.isNotEmpty) break;
      if (!_speech.isListening && i > 10) break;
    }

    final text = _lastResult.trim();

    if (text.isEmpty) {
      throw const SpeechException(
          'No speech detected. Please tap the mic and speak.');
    }

    return text;
  }

  Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
  }

  bool get isListening => _speech.isListening;
  bool get isAvailable => _isInitialised;
}
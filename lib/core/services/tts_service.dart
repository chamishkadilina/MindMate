// lib/core/services/tts_service.dart
//
// Shared TTS service for all MindMate modules.
// • Cache-first: WAV files stored permanently by SHA-256 hash of text.
// • preloadAll(): fetches & caches every string in VoiceRegistry on first launch.
// • speak(key):   plays a VoiceRegistry key — instant from cache after first run.
// • speakRaw(text): ad-hoc dynamic text, still cached by hash.
//
// Dependencies (pubspec.yaml):
//   http: ^1.2.0
//   audioplayers: ^6.0.0
//   path_provider: ^2.1.0
//   crypto: ^3.0.3        ← add this

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../voice/voice_registry.dart';


class TtsService {
  static const bool _verbose = true;

  TtsService._();
  static final TtsService instance = TtsService._();
  factory TtsService() => instance;

  /// Fires true while an HTTP synthesis request is in flight.
  final ValueNotifier<bool> isLoading = ValueNotifier(false);

  /// 0.0 → 1.0 as preloadAll() progresses. Observe in the warming-up UI.
  final ValueNotifier<double> preloadProgress = ValueNotifier(0.0);

  static const String _baseUrl =
      'https://sandaruearl-mindmate-voice-tts.hf.space';

  final AudioPlayer _player = AudioPlayer();
  bool _isInitialised  = false;
  bool _isInitialising = false;
  bool _isSpeaking     = false;
  String? _cacheDir;

  // ─────────────────────────────────────────────────────────────────────────
  // PUBLIC API
  // ─────────────────────────────────────────────────────────────────────────

  /// Sets up the permanent cache directory. Safe to call multiple times.
  Future<void> initialise() async {
    if (_isInitialised || _isInitialising) return;
    _isInitialising = true;
    _log('=== INITIALISE START ===');
    try {
      final dir = await getApplicationDocumentsDirectory();
      _cacheDir = '${dir.path}/tts_cache';
      await Directory(_cacheDir!).create(recursive: true);
      _player.onPlayerStateChanged.listen((s) => _log('player → $s'));
      _isInitialised = true;
      _log('cache dir: $_cacheDir');
      _log('=== INITIALISE COMPLETE ===');
    } finally {
      _isInitialising = false;
    }
  }

  /// Iterates VoiceRegistry.all and pre-fetches any strings not yet cached.
  /// Safe to call every launch — cached files are skipped instantly.
  /// Progress reported via [preloadProgress] (0.0 → 1.0).
  Future<void> preloadAll() async {
    if (!_isInitialised) await initialise();

    final entries = VoiceRegistry.all.entries.toList();
    final total   = entries.length;
    int done      = 0;

    preloadProgress.value = 0.0;
    _log('=== PRELOAD START: $total strings ===');

    await _pingServer();

    for (final entry in entries) {
      final file = _cacheFileFor(entry.value);
      if (await file.exists()) {
        _log('HIT  [${entry.key}]');
      } else {
        _log('MISS [${entry.key}] — fetching…');
        try {
          final bytes = await _fetchFromServer(entry.value);
          await file.writeAsBytes(bytes, flush: true);
          _log('cached [${entry.key}] ${bytes.length} bytes');
        } catch (e) {
          _log('ERROR [${entry.key}]: $e');
          // Non-fatal — speak() will retry at runtime
        }
      }
      done++;
      preloadProgress.value = done / total;
    }

    _log('=== PRELOAD COMPLETE ===');
  }

  /// Play a [VoiceRegistry] key. Always instant from cache after first launch.
  /// Awaits full audio playback before returning.
  Future<void> speak(String key) async {
    final text = VoiceRegistry.all[key];
    if (text == null) {
      _log('WARN: unknown key "$key" — ignored');
      assert(false, '[TtsService] speak() called with unregistered key: "$key"');
      return;
    }
    await _speakText(text, label: key);
  }

  /// Play arbitrary dynamic text (not in VoiceRegistry).
  /// Still cached by content hash so repeated calls are instant.
  Future<void> speakRaw(String text) async {
    final t = text.trim();
    if (t.isEmpty) return;
    await _speakText(t, label: 'raw');
  }

  Future<void> stop() async {
    _log('stop()');
    await _player.stop();
    _isSpeaking = false;
  }

  bool get isSpeaking => _isSpeaking;

  void dispose() {
    _log('dispose()');
    _player.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INTERNAL
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _speakText(String text, {required String label}) async {
    _log('=== SPEAK [$label] ===');
    if (!_isInitialised) await initialise();

    await stop();
    _isSpeaking = true;

    try {
      final file = _cacheFileFor(text);
      if (await file.exists()) {
        _log('cache HIT [$label]');
        await _playFile(file.path);
      } else {
        _log('cache MISS [$label] — fetching');
        isLoading.value = true;
        final bytes = await _fetchFromServer(text);
        isLoading.value = false;
        await file.writeAsBytes(bytes, flush: true);
        await _playFile(file.path);
      }
    } catch (e, st) {
      isLoading.value = false;
      _log('ERROR [$label]: $e\n$st');
    } finally {
      _isSpeaking = false;
    }
  }

  /// Cache file path = SHA-256(text)[0..15].wav
  /// Changing the text → different hash → old cache auto-invalidated.
  File _cacheFileFor(String text) {
    final hash = sha256
        .convert(utf8.encode(text))
        .toString()
        .substring(0, 16);
    return File('$_cacheDir/$hash.wav');
  }

  Future<Uint8List> _fetchFromServer(String text) async {
    // Graceful truncation at word boundary
    if (text.length > 300) {
      text = text.substring(0, 300).trimRight();
      final cut = text.lastIndexOf(' ');
      if (cut > 200) text = text.substring(0, cut);
    }
    final sw  = Stopwatch()..start();
    final res = await http
        .post(
      Uri.parse('$_baseUrl/tts'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'text': text, 'speed': 0.95}),
    )
        .timeout(const Duration(seconds: 30));
    sw.stop();
    _log('POST /tts → ${res.statusCode} '
        '(${sw.elapsedMilliseconds} ms, ${res.bodyBytes.length} B)');

    if (res.statusCode == 503) throw HttpException('TTS not ready (503)');
    if (res.statusCode != 200) throw HttpException('Server error ${res.statusCode}');
    return res.bodyBytes;
  }

  Future<void> _pingServer() async {
    try {
      await http
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 8));
      _log('ping OK');
    } catch (e) {
      _log('ping failed (cold start likely): $e');
    }
  }

  Future<void> _playFile(String path) async {
    await _player.play(DeviceFileSource(path));
    _log('playback started');
    await _player.onPlayerStateChanged.firstWhere(
          (s) => s == PlayerState.completed || s == PlayerState.stopped,
    );
    _log('playback complete');
  }

  void _log(String msg) {
    if (_verbose) debugPrint('[TTS] $msg');
  }
}
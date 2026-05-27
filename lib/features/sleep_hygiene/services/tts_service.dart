import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

class TtsService {
  static const bool _verbose = true;

  sherpa.OfflineTts? _tts;
  final AudioPlayer _player = AudioPlayer();
  bool _isInitialised = false;
  bool _isInitialising = false;
  bool _isSpeaking = false;

  static const Map<String, String> _assetFiles = {
    'assets/tts_model/en_US-lessac-medium.onnx': 'en_US-lessac-medium.onnx',
    'assets/tts_model/en_US-lessac-medium.onnx.json': 'en_US-lessac-medium.onnx.json',
    'assets/tts_model/tokens.txt': 'tokens.txt',
  };

  Future<void> initialise() async {
    if (_isInitialised || _isInitialising) {
      _log('already initialised or initialising — skipping');
      return;
    }
    _isInitialising = true;
    _log('=== INITIALISE START ===');

    try {
      final dir = await getApplicationDocumentsDirectory();
      _log('document dir: ${dir.path}');

      _log('--- copying main model assets ---');
      bool allFilesOk = true;

      for (final entry in _assetFiles.entries) {
        final ok = await _copyAssetIfNeeded(entry.key, '${dir.path}/${entry.value}');
        if (!ok) allFilesOk = false;
      }

      _log('--- copying espeak-ng-data assets ---');
      final espeakDir = Directory('${dir.path}/espeak-ng-data');

      try {
        late List<String> espeakAssets;
        try {
          final manifestContent = await rootBundle.loadString('AssetManifest.json');
          final Map<String, dynamic> manifestMap = json.decode(manifestContent);
          espeakAssets = manifestMap.keys
              .where((k) => k.startsWith('assets/tts_model/espeak-ng-data/'))
              .toList();
        } catch (_) {
          final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
          espeakAssets = manifest
              .listAssets()
              .where((k) => k.startsWith('assets/tts_model/espeak-ng-data/'))
              .toList();
        }

        _log('  found ${espeakAssets.length} espeak-ng-data assets');

        for (final assetPath in espeakAssets) {
          final relativePath = assetPath.replaceFirst('assets/tts_model/espeak-ng-data/', '');
          final destPath = '${espeakDir.path}/$relativePath';
          await File(destPath).parent.create(recursive: true);
          final ok = await _copyAssetIfNeeded(assetPath, destPath);
          if (!ok) allFilesOk = false;
        }
      } catch (e) {
        _log('ERROR reading asset manifest: $e');
        allFilesOk = false;
      }

      if (!allFilesOk) {
        _log('ERROR: one or more asset files could not be copied — aborting init');
        return;
      }

      _log('--- verifying main files on disk ---');
      for (final fileName in _assetFiles.values) {
        final f = File('${dir.path}/$fileName');
        final exists = await f.exists();
        final size = exists ? await f.length() : -1;
        _log('  $fileName → exists=$exists  size=$size bytes${size == 0 ? "  ⚠️ ZERO-BYTE" : ""}');
      }

      final phontab = File('${espeakDir.path}/phontab');
      final phontabExists = await phontab.exists();
      _log('  espeak-ng-data/phontab → exists=$phontabExists${!phontabExists ? "  ⚠️ MISSING" : ""}');

      if (!phontabExists) {
        _log('ERROR: phontab missing');
        return;
      }

      _log('--- building sherpa config ---');
      final modelPath = '${dir.path}/en_US-lessac-medium.onnx';
      final tokensPath = '${dir.path}/tokens.txt';
      final espeakPath = espeakDir.path;

      _log('config.model.vits.model   = $modelPath');
      _log('config.model.vits.tokens  = $tokensPath');
      _log('config.model.vits.dataDir = $espeakPath');

      final config = sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          vits: sherpa.OfflineTtsVitsModelConfig(
            model: modelPath,
            tokens: tokensPath,
            lexicon: '',
            dataDir: espeakPath,
            noiseScale: 0.667,
            noiseScaleW: 0.8,
            lengthScale: 1.1,
          ),
          numThreads: 1,
          debug: true,
          provider: 'cpu',
        ),
        maxNumSenetences: 2,
      );

      _log('--- creating OfflineTts engine ---');
      try {
        _tts = sherpa.OfflineTts(config);
        _log('engine created OK');
        _log('  sampleRate  = ${_tts!.sampleRate}');
        try {
          _log('  numSpeakers = ${_tts!.numSpeakers}');
        } catch (_) {
          _log('  numSpeakers = (not available)');
        }
      } catch (e, st) {
        _log('ERROR creating OfflineTts: $e');
        _log(st.toString());
        return;
      }

      _player.onPlayerStateChanged.listen((state) {
        _log('AudioPlayer state → $state');
      });
      _player.onLog.listen((msg) {
        _log('AudioPlayer log: $msg');
      });

      _isInitialised = true;
      _log('=== INITIALISE COMPLETE ===');
    } finally {
      _isInitialising = false;
    }
  }

  Future<void> speak(String text) async {
    _log('=== SPEAK called: "${text.length > 60 ? text.substring(0, 60) + "…" : text}"');

    if (text.trim().isEmpty) {
      _log('skipping — empty text');
      return;
    }

    if (!_isInitialised) {
      _log('not yet initialised — calling initialise() now');
      await initialise();
      if (!_isInitialised) {
        _log('ERROR: initialise() failed — cannot speak');
        return;
      }
    }

    await stop();
    _isSpeaking = true;

    try {
      _log('--- generating audio ---');
      final sw = Stopwatch()..start();
      final audio = _tts!.generate(text: text, sid: 0, speed: 0.9);
      sw.stop();

      _log('generate() finished in ${sw.elapsedMilliseconds} ms');
      _log('  samples    = ${audio.samples.length}');
      _log('  sampleRate = ${audio.sampleRate}');

      if (audio.samples.isEmpty) {
        _log('ERROR: generate() returned 0 samples');
        return;
      }

      final durationMs = ((audio.samples.length / audio.sampleRate) * 1000).round();
      _log('  audio duration ≈ $durationMs ms');

      _log('--- building WAV ---');
      final wavBytes = _buildWav(audio.samples, audio.sampleRate);
      _log('  WAV size = ${wavBytes.length} bytes');

      final tmpDir = await getTemporaryDirectory();
      final wavFile = File('${tmpDir.path}/mindmate_tts.wav');
      await wavFile.writeAsBytes(wavBytes);
      _log('  WAV written to: ${wavFile.path}');

      _log('--- starting playback ---');
      await _player.play(DeviceFileSource(wavFile.path));
      _log('play() returned');
    } catch (e, st) {
      _log('ERROR in speak(): $e');
      _log(st.toString());
    } finally {
      _isSpeaking = false;
    }
  }

  Future<void> stop() async {
    _log('stop() called');
    await _player.stop();
    _isSpeaking = false;
  }

  bool get isSpeaking => _isSpeaking;

  void dispose() {
    _log('dispose()');
    _tts?.free();
    _player.dispose();
  }

  Future<bool> _copyAssetIfNeeded(String assetPath, String destPath) async {
    final file = File(destPath);

    if (await file.exists()) {
      final size = await file.length();
      _log('  SKIP (already exists, $size bytes): $assetPath');
      if (size == 0) {
        _log('  ⚠️  zero-byte file found — deleting and re-copying');
        await file.delete();
      } else {
        return true;
      }
    }

    _log('  COPY: $assetPath → $destPath');
    try {
      final data = await rootBundle.load(assetPath);
      final bytes = data.buffer.asUint8List();
      _log('    loaded ${bytes.length} bytes from bundle');
      await file.writeAsBytes(bytes, flush: true);
      final written = await file.length();
      _log('    wrote $written bytes to disk');
      return written > 0;
    } catch (e) {
      _log('  ERROR copying $assetPath: $e');
      return false;
    }
  }

  Uint8List _buildWav(List<double> samples, int sampleRate) {
    final pcm = Int16List(samples.length);
    for (int i = 0; i < samples.length; i++) {
      pcm[i] = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    }

    final dataSize = pcm.lengthInBytes;
    final buffer = ByteData(44 + dataSize);

    buffer.setUint32(0,  0x52494646, Endian.big);
    buffer.setUint32(4,  36 + dataSize, Endian.little);
    buffer.setUint32(8,  0x57415645, Endian.big);
    buffer.setUint32(12, 0x666d7420, Endian.big);
    buffer.setUint32(16, 16, Endian.little);
    buffer.setUint16(20, 1,  Endian.little);
    buffer.setUint16(22, 1,  Endian.little);
    buffer.setUint32(24, sampleRate,     Endian.little);
    buffer.setUint32(28, sampleRate * 2, Endian.little);
    buffer.setUint16(32, 2,  Endian.little);
    buffer.setUint16(34, 16, Endian.little);
    buffer.setUint32(36, 0x64617461, Endian.big);
    buffer.setUint32(40, dataSize, Endian.little);

    final out = buffer.buffer.asUint8List();
    out.setRange(44, 44 + dataSize, pcm.buffer.asUint8List());
    return out;
  }

  void _log(String msg) {
    if (_verbose) debugPrint('[TTS] $msg');
  }
}
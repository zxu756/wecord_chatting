import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

const _voiceSampleRate = 44100;
const _voiceNumChannels = 1;
const _voiceBitsPerSample = 16;

/// A recording stops by itself after this long. The recorder writes WAV
/// (16-bit mono 44.1 kHz: 88,200 bytes a second, about 5.3 MB a minute) and
/// the voice-messages bucket takes up to 50 MB (migration 202610190051), so
/// 9 minutes (about 47.6 MB) fits with room to spare.
const maxVoiceRecordingSeconds = 9 * 60;

/// The last seconds of a recording show a countdown.
const voiceCountdownSeconds = 30;

final voiceMessageRecorderProvider = Provider.autoDispose<VoiceMessageRecorder>(
  (ref) {
    final recorder = AudioVoiceMessageRecorder();
    ref.onDispose(() {
      recorder.dispose();
    });
    return recorder;
  },
);

class RecordedVoiceMessage {
  const RecordedVoiceMessage({
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
  });

  final Uint8List bytes;
  final String mimeType;
  final int durationMs;
}

abstract interface class VoiceMessageRecorder {
  Future<void> start();
  Future<RecordedVoiceMessage?> stop();
  Future<void> cancel();
}

/// A recorder that can be paused and carry on (A10). Like
/// `OutboxMessageSender`, a recorder may or may not be one; the pause button
/// shows only for those that are.
abstract interface class PausableVoiceRecorder {
  bool get isPaused;

  /// Stops taking sound in; what was recorded is kept.
  Future<void> pause();

  /// Carries on into the same recording.
  Future<void> resume();

  /// What has been recorded so far as a WAV, without stopping (to trim it
  /// or listen to it while paused). Null before anything was recorded.
  RecordedVoiceMessage? snapshot();
}

class AudioVoiceMessageRecorder
    implements VoiceMessageRecorder, PausableVoiceRecorder {
  AudioVoiceMessageRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final _recordedChunks = <Uint8List>[];
  var _paused = false;
  StreamSubscription<Uint8List>? _recordingSubscription;

  @override
  Future<void> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is required.');
    }

    await _recordingSubscription?.cancel();
    _recordedChunks.clear();
    _paused = false;
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _voiceSampleRate,
        numChannels: _voiceNumChannels,
      ),
    );
    // While paused, whatever still arrives is dropped: the browser's and the
    // phone's recorders differ in how soon they go quiet.
    _recordingSubscription = stream.listen((chunk) {
      if (!_paused) {
        _recordedChunks.add(chunk);
      }
    });
  }

  @override
  bool get isPaused => _paused;

  @override
  Future<void> pause() async {
    if (_paused) {
      return;
    }
    _paused = true;
    try {
      await _recorder.pause();
    } catch (_) {
      // Some platforms cannot pause the input; the chunks are dropped anyway.
    }
  }

  @override
  Future<void> resume() async {
    if (!_paused) {
      return;
    }
    try {
      await _recorder.resume();
    } catch (_) {
      // See [pause].
    }
    _paused = false;
  }

  @override
  RecordedVoiceMessage? snapshot() {
    if (_recordedChunks.isEmpty) {
      return null;
    }
    final pcmBytes = Uint8List.fromList([
      for (final chunk in _recordedChunks) ...chunk,
    ]);
    return RecordedVoiceMessage(
      bytes: _wavBytes(pcmBytes),
      mimeType: 'audio/wav',
      durationMs: _pcmDurationMs(pcmBytes.length),
    );
  }

  @override
  Future<RecordedVoiceMessage?> stop() async {
    _paused = false;
    await _recorder.stop();
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    if (_recordedChunks.isEmpty) {
      return null;
    }

    final pcmBytes = Uint8List.fromList([
      for (final chunk in _recordedChunks) ...chunk,
    ]);
    _recordedChunks.clear();
    // The length of the sound itself, so a pause does not count.
    return RecordedVoiceMessage(
      bytes: _wavBytes(pcmBytes),
      mimeType: 'audio/wav',
      durationMs: _pcmDurationMs(pcmBytes.length),
    );
  }

  @override
  Future<void> cancel() async {
    _paused = false;
    await _recorder.cancel();
    await _recordingSubscription?.cancel();
    _recordingSubscription = null;
    _recordedChunks.clear();
  }

  void dispose() {
    unawaited(_recordingSubscription?.cancel());
    unawaited(_recorder.dispose());
  }
}

int _pcmDurationMs(int pcmLength) =>
    pcmLength *
    1000 ~/
    (_voiceSampleRate * _voiceNumChannels * _voiceBitsPerSample ~/ 8);

Uint8List _wavBytes(Uint8List pcmBytes) {
  final bytes = Uint8List(44 + pcmBytes.length);
  final data = ByteData.sublistView(bytes);

  _writeAscii(bytes, 0, 'RIFF');
  data.setUint32(4, 36 + pcmBytes.length, Endian.little);
  _writeAscii(bytes, 8, 'WAVE');
  _writeAscii(bytes, 12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, _voiceNumChannels, Endian.little);
  data.setUint32(24, _voiceSampleRate, Endian.little);
  data.setUint32(
    28,
    _voiceSampleRate * _voiceNumChannels * _voiceBitsPerSample ~/ 8,
    Endian.little,
  );
  data.setUint16(
    32,
    _voiceNumChannels * _voiceBitsPerSample ~/ 8,
    Endian.little,
  );
  data.setUint16(34, _voiceBitsPerSample, Endian.little);
  _writeAscii(bytes, 36, 'data');
  data.setUint32(40, pcmBytes.length, Endian.little);
  bytes.setRange(44, bytes.length, pcmBytes);

  return bytes;
}

void _writeAscii(Uint8List bytes, int offset, String value) {
  for (var index = 0; index < value.length; index += 1) {
    bytes[offset + index] = value.codeUnitAt(index);
  }
}

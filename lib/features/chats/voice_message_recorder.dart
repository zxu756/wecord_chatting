import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

const _voiceSampleRate = 44100;
const _voiceNumChannels = 1;
const _voiceBitsPerSample = 16;

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

class AudioVoiceMessageRecorder implements VoiceMessageRecorder {
  AudioVoiceMessageRecorder({AudioRecorder? recorder})
    : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final _recordedChunks = <Uint8List>[];
  DateTime? _startedAt;
  StreamSubscription<Uint8List>? _recordingSubscription;

  @override
  Future<void> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission is required.');
    }

    await _recordingSubscription?.cancel();
    _recordedChunks.clear();
    _startedAt = DateTime.now();
    final stream = await _recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _voiceSampleRate,
        numChannels: _voiceNumChannels,
      ),
    );
    _recordingSubscription = stream.listen(_recordedChunks.add);
  }

  @override
  Future<RecordedVoiceMessage?> stop() async {
    final startedAt = _startedAt;
    _startedAt = null;

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
    final durationMs = startedAt == null
        ? 0
        : DateTime.now().difference(startedAt).inMilliseconds;
    return RecordedVoiceMessage(
      bytes: _wavBytes(pcmBytes),
      mimeType: 'audio/wav',
      durationMs: durationMs,
    );
  }

  @override
  Future<void> cancel() async {
    _startedAt = null;
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

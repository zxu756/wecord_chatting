import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/voice/audio_clip.dart';

import 'audio_fixtures.dart';

void main() {
  test('reads a WAV clip', () {
    final clip = readAudioClip(wavBytes(seconds: 1.5))!;
    expect(clip.mimeType, 'audio/wav');
    expect(clip.extension, 'wav');
    expect(clip.duration, const Duration(milliseconds: 1500));
  });

  test('reads an MP3 clip after its ID3 tag, frame by frame', () {
    final clip = readAudioClip(mp3Bytes(frames: 100))!;
    expect(clip.mimeType, 'audio/mpeg');
    expect(clip.extension, 'mp3');
    // 100 frames of 1152 samples at 44.1 kHz.
    expect(clip.duration.inMilliseconds, 2612);
    expect(readAudioClip(mp3Bytes(frames: 3, id3: false)), isNotNull);
  });

  test('reads Ogg Vorbis and Opus clips from the last granule', () {
    final vorbis = readAudioClip(oggBytes(granule: 44100 * 3))!;
    expect(vorbis.mimeType, 'audio/ogg');
    expect(vorbis.extension, 'ogg');
    expect(vorbis.duration, const Duration(seconds: 3));

    final opus = readAudioClip(
      oggBytes(granule: 48000 * 6 + 312, opus: true, preSkip: 312),
    )!;
    expect(opus.duration, const Duration(seconds: 6));
  });

  test('anything else is not a clip', () {
    expect(readAudioClip(Uint8List(0)), isNull);
    expect(readAudioClip(Uint8List.fromList('hello world'.codeUnits)), isNull);
    // A PNG signature.
    expect(
      readAudioClip(Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0])),
      isNull,
    );
  });
}

// Small audio files built in memory for the soundboard tests.
import 'dart:typed_data';

/// A mono 8-bit PCM WAV file of [seconds] at [sampleRate].
Uint8List wavBytes({double seconds = 1, int sampleRate = 8000}) {
  final samples = (seconds * sampleRate).round();
  final data = ByteData(44 + samples);
  void ascii(int offset, String text) {
    for (var index = 0; index < text.length; index++) {
      data.setUint8(offset + index, text.codeUnitAt(index));
    }
  }

  ascii(0, 'RIFF');
  data.setUint32(4, 36 + samples, Endian.little);
  ascii(8, 'WAVE');
  ascii(12, 'fmt ');
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little); // PCM
  data.setUint16(22, 1, Endian.little); // mono
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate, Endian.little); // byte rate
  data.setUint16(32, 1, Endian.little); // block align
  data.setUint16(34, 8, Endian.little); // bits
  ascii(36, 'data');
  data.setUint32(40, samples, Endian.little);
  return data.buffer.asUint8List();
}

/// [frames] MPEG-1 Layer III frames at 128 kbps and 44.1 kHz, after an
/// ID3v2 tag when [id3].
Uint8List mp3Bytes({int frames = 10, bool id3 = true}) {
  final bytes = BytesBuilder();
  if (id3) {
    // "ID3", version 4.0, no flags, 20 bytes of tag.
    bytes.add([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 20]);
    bytes.add(List.filled(20, 0));
  }
  for (var index = 0; index < frames; index++) {
    // 144 * 128000 / 44100 = 417 bytes without padding.
    final frame = Uint8List(417);
    frame[0] = 0xFF;
    frame[1] = 0xFB; // MPEG-1, Layer III, no CRC
    frame[2] = 0x90; // 128 kbps, 44.1 kHz, no padding
    frame[3] = 0x64;
    bytes.add(frame);
  }
  return bytes.toBytes();
}

/// An Ogg stream: an identification page then a last page with
/// [granule]; Opus when [opus] (with [preSkip]), Vorbis otherwise.
Uint8List oggBytes({
  required int granule,
  int sampleRate = 44100,
  bool opus = false,
  int preSkip = 0,
}) {
  Uint8List page(List<int> packet, int granulePosition) {
    final data = ByteData(27 + 1 + packet.length);
    for (final (index, char) in 'OggS'.codeUnits.indexed) {
      data.setUint8(index, char);
    }
    data.setUint32(6, granulePosition & 0xFFFFFFFF, Endian.little);
    data.setUint32(10, granulePosition >> 32, Endian.little);
    data.setUint8(26, 1);
    data.setUint8(27, packet.length);
    final bytes = data.buffer.asUint8List();
    bytes.setRange(28, 28 + packet.length, packet);
    return bytes;
  }

  final id = ByteData(opus ? 19 : 30);
  if (opus) {
    for (final (index, char) in 'OpusHead'.codeUnits.indexed) {
      id.setUint8(index, char);
    }
    id.setUint8(8, 1);
    id.setUint8(9, 2);
    id.setUint16(10, preSkip, Endian.little);
    id.setUint32(12, 48000, Endian.little);
  } else {
    id.setUint8(0, 1);
    for (final (index, char) in 'vorbis'.codeUnits.indexed) {
      id.setUint8(1 + index, char);
    }
    id.setUint8(11, 2);
    id.setUint32(12, sampleRate, Endian.little);
  }
  return Uint8List.fromList([
    ...page(id.buffer.asUint8List(), 0),
    ...page(List.filled(40, 7), granule),
  ]);
}

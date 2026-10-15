import 'dart:typed_data';

/// What a short audio file is: its type, file extension and length, read
/// from its bytes (no decoding).
class AudioClipInfo {
  const AudioClipInfo({
    required this.mimeType,
    required this.extension,
    required this.duration,
  });

  /// `audio/mpeg`, `audio/ogg` or `audio/wav`.
  final String mimeType;

  /// `mp3`, `ogg` or `wav`.
  final String extension;
  final Duration duration;
}

/// Reads an MP3, Ogg (Vorbis or Opus) or WAV clip's type and length; null
/// for anything else or a file too broken to tell.
AudioClipInfo? readAudioClip(Uint8List bytes) {
  if (_startsWith(bytes, 0, 'RIFF') && _startsWith(bytes, 8, 'WAVE')) {
    return _wav(bytes);
  }
  if (_startsWith(bytes, 0, 'OggS')) {
    return _ogg(bytes);
  }
  return _mp3(bytes);
}

bool _startsWith(Uint8List bytes, int offset, String ascii) {
  if (bytes.length < offset + ascii.length) {
    return false;
  }
  for (var index = 0; index < ascii.length; index++) {
    if (bytes[offset + index] != ascii.codeUnitAt(index)) {
      return false;
    }
  }
  return true;
}

Duration _seconds(double seconds) {
  return Duration(
    microseconds: (seconds * Duration.microsecondsPerSecond).round(),
  );
}

AudioClipInfo? _wav(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  var offset = 12;
  int? byteRate;
  while (offset + 8 <= bytes.length) {
    final size = data.getUint32(offset + 4, Endian.little);
    if (_startsWith(bytes, offset, 'fmt ') && offset + 16 <= bytes.length) {
      byteRate = data.getUint32(offset + 16, Endian.little);
    } else if (_startsWith(bytes, offset, 'data')) {
      final rate = byteRate;
      if (rate == null || rate == 0) {
        return null;
      }
      // Streams write an unknown (or too large) size; count what is there.
      final available = bytes.length - offset - 8;
      final length = size > available ? available : size;
      return AudioClipInfo(
        mimeType: 'audio/wav',
        extension: 'wav',
        duration: _seconds(length / rate),
      );
    }
    offset += 8 + size + (size.isOdd ? 1 : 0);
  }
  return null;
}

AudioClipInfo? _ogg(Uint8List bytes) {
  final data = ByteData.sublistView(bytes);
  if (bytes.length < 28) {
    return null;
  }
  // The first page holds the codec's identification header.
  final segments = bytes[26];
  final packet = 27 + segments;
  int sampleRate;
  var preSkip = 0;
  if (_startsWith(bytes, packet, '\u0001vorbis') &&
      packet + 16 <= bytes.length) {
    sampleRate = data.getUint32(packet + 12, Endian.little);
  } else if (_startsWith(bytes, packet, 'OpusHead') &&
      packet + 12 <= bytes.length) {
    // Opus always counts at 48 kHz, after skipping the encoder delay.
    sampleRate = 48000;
    preSkip = data.getUint16(packet + 10, Endian.little);
  } else {
    return null;
  }
  if (sampleRate <= 0) {
    return null;
  }
  // The last page's granule position is the stream's length in samples.
  for (var offset = bytes.length - 27; offset >= 0; offset--) {
    if (!_startsWith(bytes, offset, 'OggS')) {
      continue;
    }
    // Two 32-bit halves: browsers can't read 64-bit integers.
    final low = data.getUint32(offset + 6, Endian.little);
    final high = data.getUint32(offset + 10, Endian.little);
    if (high == 0xFFFFFFFF) {
      // -1: no packet ends on this page.
      continue;
    }
    final granule = high * 4294967296 + low;
    final samples = granule - preSkip;
    return AudioClipInfo(
      mimeType: 'audio/ogg',
      extension: 'ogg',
      duration: _seconds((samples < 0 ? 0 : samples) / sampleRate),
    );
  }
  return null;
}

const _mpeg1Bitrates = [
  [0, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448],
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384],
  [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320],
];

const _mpeg2Bitrates = [
  [0, 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256],
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
  [0, 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160],
];

const _sampleRates = {
  3: [44100, 48000, 32000], // MPEG 1
  2: [22050, 24000, 16000], // MPEG 2
  0: [11025, 12000, 8000], // MPEG 2.5
};

/// One MPEG audio frame: how long it is in bytes and in seconds.
({int length, double seconds})? _mpegFrame(Uint8List bytes, int offset) {
  if (offset + 4 > bytes.length ||
      bytes[offset] != 0xFF ||
      bytes[offset + 1] & 0xE0 != 0xE0) {
    return null;
  }
  final version = (bytes[offset + 1] >> 3) & 0x3;
  final layerBits = (bytes[offset + 1] >> 1) & 0x3;
  final bitrateIndex = bytes[offset + 2] >> 4;
  final sampleRateIndex = (bytes[offset + 2] >> 2) & 0x3;
  final padding = (bytes[offset + 2] >> 1) & 0x1;
  final rates = _sampleRates[version];
  if (rates == null ||
      layerBits == 0 ||
      bitrateIndex == 0 ||
      bitrateIndex == 15 ||
      sampleRateIndex == 3) {
    return null;
  }
  // Layer I, II or III as 1, 2, 3.
  final layer = 4 - layerBits;
  final mpeg1 = version == 3;
  final bitrate =
      (mpeg1 ? _mpeg1Bitrates : _mpeg2Bitrates)[layer - 1][bitrateIndex] * 1000;
  final sampleRate = rates[sampleRateIndex];
  final int samples;
  final int length;
  if (layer == 1) {
    samples = 384;
    length = (12 * bitrate ~/ sampleRate + padding) * 4;
  } else if (layer == 3 && !mpeg1) {
    samples = 576;
    length = 72 * bitrate ~/ sampleRate + padding;
  } else {
    samples = 1152;
    length = 144 * bitrate ~/ sampleRate + padding;
  }
  if (length < 4) {
    return null;
  }
  return (length: length, seconds: samples / sampleRate);
}

AudioClipInfo? _mp3(Uint8List bytes) {
  var offset = 0;
  // An ID3v2 tag comes first: 10 bytes and a size in 7-bit bytes.
  if (_startsWith(bytes, 0, 'ID3') && bytes.length >= 10) {
    final size =
        (bytes[6] & 0x7F) << 21 |
        (bytes[7] & 0x7F) << 14 |
        (bytes[8] & 0x7F) << 7 |
        (bytes[9] & 0x7F);
    final footer = bytes[5] & 0x10 != 0 ? 10 : 0;
    offset = 10 + size + footer;
  }
  // Find the first frame, followed by another (or the end).
  while (offset + 4 <= bytes.length) {
    final frame = _mpegFrame(bytes, offset);
    if (frame != null) {
      final next = offset + frame.length;
      if (next >= bytes.length || _mpegFrame(bytes, next) != null) {
        break;
      }
    }
    offset++;
    if (offset > 64 * 1024) {
      return null;
    }
  }
  var seconds = 0.0;
  var frames = 0;
  while (true) {
    final frame = _mpegFrame(bytes, offset);
    if (frame == null) {
      break;
    }
    seconds += frame.seconds;
    frames++;
    offset += frame.length;
  }
  if (frames == 0) {
    return null;
  }
  return AudioClipInfo(
    mimeType: 'audio/mpeg',
    extension: 'mp3',
    duration: _seconds(seconds),
  );
}

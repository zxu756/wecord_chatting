import 'dart:typed_data';

/// Reading and cleaning the metadata of JPEG photos, without decoding them.
///
/// Photos carry EXIF (camera, time, often the GPS position), XMP, IPTC and
/// comments. A chat should not hand those on. [stripJpegMetadata] drops them
/// all but keeps the picture byte for byte, the colour profile, and the
/// orientation (rewritten as a tiny EXIF block of its own), so a photo taken
/// sideways still shows upright.
class JpegMetadata {
  const JpegMetadata({required this.orientation, required this.hasGps});

  /// The EXIF orientation, 1 (upright) to 8; 1 when there is none.
  final int orientation;

  /// Whether the EXIF block holds a GPS position.
  final bool hasGps;

  /// Whether the picture is turned by 90 degrees when shown (orientations
  /// 5 to 8), so its width and height swap.
  bool get swapsAxes => orientation >= 5 && orientation <= 8;
}

bool _isJpeg(Uint8List bytes) =>
    bytes.length > 4 && bytes[0] == 0xFF && bytes[1] == 0xD8;

/// What the EXIF block of [jpeg] says; null when it is not a JPEG.
JpegMetadata? readJpegMetadata(Uint8List jpeg) {
  if (!_isJpeg(jpeg)) {
    return null;
  }
  var orientation = 1;
  var hasGps = false;
  for (final segment in _segments(jpeg)) {
    if (segment.marker == 0xE1 && _isExif(jpeg, segment)) {
      final exif = _readExif(jpeg, segment.dataStart + 6, segment.end);
      if (exif != null) {
        orientation = exif.$1;
        hasGps = exif.$2;
      }
    }
  }
  return JpegMetadata(orientation: orientation, hasGps: hasGps);
}

/// [jpeg] without its EXIF, XMP, IPTC and comments, keeping the pixels, the
/// colour profile and the orientation. Returns null when [jpeg] is not a
/// well-formed JPEG (callers then re-encode the picture instead).
Uint8List? stripJpegMetadata(Uint8List jpeg) {
  if (!_isJpeg(jpeg)) {
    return null;
  }
  final metadata = readJpegMetadata(jpeg);
  if (metadata == null) {
    return null;
  }
  final kept = <Uint8List>[];
  var scanStart = -1;
  for (final segment in _segments(jpeg)) {
    if (segment.marker == 0xDA) {
      scanStart = segment.start;
      break;
    }
    if (_dropsSegment(jpeg, segment)) {
      continue;
    }
    kept.add(Uint8List.sublistView(jpeg, segment.start, segment.end));
  }
  if (scanStart < 0) {
    return null;
  }

  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var orientationWritten = metadata.orientation <= 1;
  for (final segment in kept) {
    out.add(segment);
    // After the JFIF header, if there is one; the orientation block is
    // otherwise the first segment.
    if (!orientationWritten && segment[1] == 0xE0) {
      out.add(_orientationBlock(metadata.orientation));
      orientationWritten = true;
    }
  }
  if (!orientationWritten) {
    out.add(_orientationBlock(metadata.orientation));
  }
  out.add(Uint8List.sublistView(jpeg, scanStart));
  return out.takeBytes();
}

/// Everything before the scan and the scan header itself, as markers.
class _Segment {
  const _Segment(this.marker, this.start, this.end, this.dataStart);

  final int marker;

  /// Offset of the 0xFF of the marker.
  final int start;

  /// Offset after the segment (for the scan header: where the entropy coded
  /// data begins).
  final int end;

  /// Offset of the segment's payload (after the length).
  final int dataStart;
}

Iterable<_Segment> _segments(Uint8List bytes) sync* {
  var i = 2;
  while (i + 1 < bytes.length) {
    if (bytes[i] != 0xFF) {
      return;
    }
    var marker = bytes[i + 1];
    var start = i;
    // Fill bytes before a marker.
    while (marker == 0xFF && i + 2 < bytes.length) {
      i++;
      start = i;
      marker = bytes[i + 1];
    }
    if (marker == 0xD9) {
      return;
    }
    // Markers without a payload.
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) {
      yield _Segment(marker, start, start + 2, start + 2);
      i = start + 2;
      continue;
    }
    if (start + 3 >= bytes.length) {
      return;
    }
    final length = (bytes[start + 2] << 8) | bytes[start + 3];
    if (length < 2) {
      return;
    }
    final end = start + 2 + length;
    if (end > bytes.length) {
      return;
    }
    yield _Segment(marker, start, end, start + 4);
    if (marker == 0xDA) {
      return;
    }
    i = end;
  }
}

bool _isExif(Uint8List bytes, _Segment segment) {
  if (segment.end - segment.dataStart < 6) {
    return false;
  }
  const exif = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // "Exif\0\0"
  for (var i = 0; i < exif.length; i++) {
    if (bytes[segment.dataStart + i] != exif[i]) {
      return false;
    }
  }
  return true;
}

bool _startsWith(Uint8List bytes, int offset, int end, String text) {
  if (end - offset < text.length) {
    return false;
  }
  for (var i = 0; i < text.length; i++) {
    if (bytes[offset + i] != text.codeUnitAt(i)) {
      return false;
    }
  }
  return true;
}

/// Segments that can hold personal data. Colour profiles (APP2), the JFIF
/// header (APP0) and the Adobe colour transform (APP14) stay.
bool _dropsSegment(Uint8List bytes, _Segment segment) {
  switch (segment.marker) {
    case 0xE1: // EXIF and XMP
      return true;
    case 0xED: // Photoshop / IPTC
    case 0xFE: // comment
      return true;
    case 0xE2: // ICC profile stays; other APP2 (FlashPix, MPF) goes
      return !_startsWith(bytes, segment.dataStart, segment.end, 'ICC_PROFILE');
    default:
      // Vendor blocks in APP3 to APP12 and APP15 (maker notes, thumbnails).
      return segment.marker >= 0xE3 && segment.marker <= 0xEF
          ? segment.marker != 0xEE
          : false;
  }
}

/// (orientation, hasGps) from the TIFF structure in an EXIF block.
(int, bool)? _readExif(Uint8List bytes, int tiffStart, int end) {
  if (end - tiffStart < 8) {
    return null;
  }
  final big = bytes[tiffStart] == 0x4D && bytes[tiffStart + 1] == 0x4D;
  final little = bytes[tiffStart] == 0x49 && bytes[tiffStart + 1] == 0x49;
  if (!big && !little) {
    return null;
  }
  final data = ByteData.sublistView(bytes, tiffStart, end);
  final endian = big ? Endian.big : Endian.little;
  final ifdOffset = data.getUint32(4, endian);
  if (ifdOffset < 8 || ifdOffset + 2 > data.lengthInBytes) {
    return null;
  }
  final count = data.getUint16(ifdOffset, endian);
  var orientation = 1;
  var hasGps = false;
  for (var i = 0; i < count; i++) {
    final entry = ifdOffset + 2 + i * 12;
    if (entry + 12 > data.lengthInBytes) {
      break;
    }
    final tag = data.getUint16(entry, endian);
    if (tag == 0x0112) {
      final value = data.getUint16(entry + 8, endian);
      if (value >= 1 && value <= 8) {
        orientation = value;
      }
    } else if (tag == 0x8825) {
      hasGps = true;
    }
  }
  return (orientation, hasGps);
}

/// An APP1 segment holding nothing but the orientation.
Uint8List _orientationBlock(int orientation) {
  return Uint8List.fromList([
    0xFF, 0xE1, 0x00, 0x22, // APP1, 34 bytes
    0x45, 0x78, 0x69, 0x66, 0x00, 0x00, // "Exif\0\0"
    0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // big endian TIFF header
    0x00, 0x01, // one entry
    0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // orientation, SHORT, 1
    0x00, orientation, 0x00, 0x00, // value
    0x00, 0x00, 0x00, 0x00, // no next IFD
  ]);
}

// Round video messages (A13): the limits and what a recording is.
import 'package:file_selector/file_selector.dart' show XFile;

/// A recording stops by itself after this long (the roadmap's 60 seconds).
const maxVideoNoteSeconds = 60;

/// The last seconds of a recording show a countdown.
const videoNoteCountdownSeconds = 10;

/// Shorter than this is a slip of the finger, not a message.
const minVideoNoteMs = 1000;

/// The server refuses a note over this many bytes (migration 202610280320);
/// a minute at the camera's medium quality is about a tenth of it.
const maxVideoNoteBytes = 30 * 1024 * 1024;

/// A finished recording, before it is sent.
class VideoNoteClip {
  const VideoNoteClip({
    required this.file,
    required this.durationMs,
    required this.mimeType,
    required this.size,
    this.width,
    this.height,
  });

  /// The video: a file on iOS and macOS, in memory in the browser.
  final XFile file;

  /// How long it ran, which the receiving app shows and the server checks.
  final int durationMs;

  /// `video/mp4` where the recorder made MP4, otherwise what it made
  /// (`video/webm` in browsers that cannot record MP4).
  final String mimeType;

  /// Bytes.
  final int size;

  /// The picture's size, when the camera said.
  final int? width;
  final int? height;

  bool get tooLong => durationMs > maxVideoNoteSeconds * 1000 + 1000;
  bool get tooShort => durationMs < minVideoNoteMs;
  bool get tooBig => size > maxVideoNoteBytes;

  /// The name stored with the file.
  String get fileName =>
      mimeType == 'video/webm' ? 'video-message.webm' : 'video-message.mp4';
}

/// Why the camera could not be used.
enum VideoNoteCameraProblem {
  /// The person said no to the camera or the microphone.
  denied,

  /// No camera (or no microphone) was found.
  missing,

  /// The browser or the device cannot record this.
  unsupported,

  /// Something else went wrong.
  failed,
}

class VideoNoteCameraException implements Exception {
  const VideoNoteCameraException(this.problem, [this.detail]);

  final VideoNoteCameraProblem problem;
  final Object? detail;

  @override
  String toString() => 'VideoNoteCameraException($problem, $detail)';
}

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';

/// How far the local media has got.
enum WatchMediaPhase { idle, loading, ready, failed }

/// Why the media could not play.
enum WatchMediaFailure {
  /// The device or browser can not play this file or stream.
  cannotPlay,

  /// It did not load in time (a slow or blocked link).
  timeout,
}

/// What the local player is doing now.
@immutable
class WatchMediaValue {
  const WatchMediaValue({
    this.phase = WatchMediaPhase.idle,
    this.playing = false,
    this.buffering = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.failure,
    this.aspectRatio = 16 / 9,
  });

  final WatchMediaPhase phase;
  final bool playing;
  final bool buffering;
  final Duration position;
  final Duration duration;
  final WatchMediaFailure? failure;
  final double aspectRatio;

  bool get ready => phase == WatchMediaPhase.ready;
  bool get failed => phase == WatchMediaPhase.failed;

  WatchMediaValue copyWith({
    WatchMediaPhase? phase,
    bool? playing,
    bool? buffering,
    Duration? position,
    Duration? duration,
    WatchMediaFailure? failure,
    double? aspectRatio,
  }) {
    return WatchMediaValue(
      phase: phase ?? this.phase,
      playing: playing ?? this.playing,
      buffering: buffering ?? this.buffering,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      failure: failure ?? this.failure,
      aspectRatio: aspectRatio ?? this.aspectRatio,
    );
  }
}

/// A player for one video or audio link. The app plays through
/// `video_player`; tests use a fake. It never sends anything anywhere: each
/// person's device loads the link itself.
abstract interface class WatchMediaPlayer
    implements ValueListenable<WatchMediaValue> {
  /// Loads [link]. Completes when it is ready or has failed (see [value]).
  Future<void> open(WatchLink link);

  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);

  /// Silences (or restores) the sound on this device only.
  Future<void> setMuted(bool muted);

  /// The picture; an empty box for audio.
  Widget buildView(BuildContext context);

  Future<void> dispose();
}

/// Makes a player; the provider is replaced in tests.
typedef WatchPlayerFactory = WatchMediaPlayer Function();

final watchPlayerFactoryProvider = Provider<WatchPlayerFactory>(
  (ref) => VideoPlayerWatchMedia.new,
);

/// How long a link may take to load.
const watchLoadTimeout = Duration(seconds: 25);

/// A [WatchMediaPlayer] on `video_player`: AVPlayer on iOS and macOS (MP4,
/// MOV, HLS, MP3, M4A…), the browser's media element on the web (MP4,
/// WebM, MP3…; HLS only where the browser plays it itself, as Safari does).
class VideoPlayerWatchMedia extends ChangeNotifier implements WatchMediaPlayer {
  VideoPlayerWatchMedia({
    VideoPlayerController Function(Uri uri, VideoFormat? format)? controller,
    this.loadTimeout = watchLoadTimeout,
  }) : _make = controller ?? _defaultController;

  final Duration loadTimeout;
  final VideoPlayerController Function(Uri uri, VideoFormat? format) _make;
  VideoPlayerController? _controller;
  WatchMediaValue _value = const WatchMediaValue();
  var _disposed = false;
  var _muted = false;

  static VideoPlayerController _defaultController(
    Uri uri,
    VideoFormat? format,
  ) {
    return VideoPlayerController.networkUrl(
      uri,
      formatHint: format,
      // The call's audio session must not be taken over, or the
      // microphone would stop mid-call.
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
  }

  @override
  WatchMediaValue get value => _value;

  void _set(WatchMediaValue value) {
    if (_disposed) {
      return;
    }
    _value = value;
    notifyListeners();
  }

  @override
  Future<void> open(WatchLink link) async {
    if (_disposed) {
      return;
    }
    _set(const WatchMediaValue(phase: WatchMediaPhase.loading));
    final controller = _make(
      link.uri,
      link.kind == WatchLinkKind.hls ? VideoFormat.hls : null,
    );
    _controller = controller;
    try {
      await controller.initialize().timeout(loadTimeout);
    } on TimeoutException {
      _fail(WatchMediaFailure.timeout);
      return;
    } on Object {
      _fail(WatchMediaFailure.cannotPlay);
      return;
    }
    if (_disposed) {
      return;
    }
    if (_muted) {
      await controller.setVolume(0);
    }
    controller.addListener(_onController);
    _onController();
  }

  void _fail(WatchMediaFailure failure) {
    _set(
      _value.copyWith(
        phase: WatchMediaPhase.failed,
        failure: failure,
        playing: false,
        buffering: false,
      ),
    );
  }

  void _onController() {
    final controller = _controller;
    if (controller == null || _disposed) {
      return;
    }
    final v = controller.value;
    if (v.hasError) {
      _fail(WatchMediaFailure.cannotPlay);
      return;
    }
    if (!v.isInitialized) {
      return;
    }
    final size = v.size;
    _set(
      WatchMediaValue(
        phase: WatchMediaPhase.ready,
        playing: v.isPlaying,
        buffering: v.isBuffering,
        position: v.position,
        duration: v.duration,
        aspectRatio: size.width > 0 && size.height > 0
            ? size.width / size.height
            : 16 / 9,
      ),
    );
  }

  @override
  Future<void> play() async {
    final controller = _controller;
    if (controller != null && _value.ready) {
      await controller.play();
    }
  }

  @override
  Future<void> pause() async {
    final controller = _controller;
    if (controller != null && _value.ready) {
      await controller.pause();
    }
  }

  @override
  Future<void> seekTo(Duration position) async {
    final controller = _controller;
    if (controller != null && _value.ready) {
      await controller.seekTo(position);
    }
  }

  @override
  Future<void> setMuted(bool muted) async {
    _muted = muted;
    final controller = _controller;
    if (controller != null && _value.ready) {
      await controller.setVolume(muted ? 0 : 1);
    }
  }

  @override
  Widget buildView(BuildContext context) {
    final controller = _controller;
    if (controller == null || !_value.ready) {
      return const SizedBox.shrink();
    }
    return VideoPlayer(controller);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_onController);
    try {
      await controller?.dispose();
    } on Object {
      // Already gone.
    }
    super.dispose();
  }
}

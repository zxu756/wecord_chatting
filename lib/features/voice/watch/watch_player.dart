import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart'
    show videoControllerFactoryProvider;
import 'package:wecord/features/voice/watch/watch_embed_player_stub.dart'
    if (dart.library.js_interop) 'package:wecord/features/voice/watch/watch_embed_player_web.dart'
    as embed;
import 'package:wecord/features/voice/watch/watch_sources.dart';

/// One device's player for what the room watches. The room only agrees on
/// where the playback is; each device loads and plays the media itself.
abstract interface class WatchPlayer implements Listenable {
  /// Where this player is now (an estimate for players that report only now
  /// and then).
  Duration get position;

  /// How long the media is, once known.
  Duration? get duration;

  bool get isPlaying;
  bool get isBuffering;
  bool get hasEnded;

  /// Whether there is a picture to show (a video, not a song).
  bool get hasSurface;

  /// Whether this player can be played, paused and moved from the app.
  /// Bilibili's embedded player can not.
  bool get remoteControl;

  /// The picture takes the pointer itself (the site's own play button).
  bool get surfaceInteractive;

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setMuted(bool muted);

  /// The picture; only when [hasSurface].
  Widget buildSurface(BuildContext context);

  Future<void> close();
}

/// Opens the player for a [source]; null when this device has none for it
/// (the embedded players of YouTube and Bilibili outside the web). Throws
/// when the media can not be loaded. Tests swap in a fake.
typedef WatchPlayerFactory =
    Future<WatchPlayer?> Function(WatchSource source, {String? conversationId});

final watchPlayerFactoryProvider = Provider<WatchPlayerFactory>((ref) {
  return (source, {conversationId}) async {
    switch (source) {
      case WatchEmbedSource():
        return embed.createEmbedWatchPlayer(source);
      case WatchLinkSource():
        final factory = ref.read(videoControllerFactoryProvider);
        return VideoWatchPlayer.open(
          factory(url: source.url),
          hasSurface: !source.isAudio,
        );
      case WatchFileSource():
        final factory = ref.read(videoControllerFactoryProvider);
        final file = source.toPreviewFile(conversationId: conversationId);
        final cached = await ref
            .read(fileFetcherProvider)
            .cachedPath(file)
            .catchError((Object _) => null);
        final controller = cached != null
            ? factory(localPath: cached)
            : factory(
                url: await ref.read(filePreviewServiceProvider).fileUrl(file),
              );
        return VideoWatchPlayer.open(controller, hasSurface: !source.isAudio);
    }
  };
});

/// Plays a video or audio file with the app's video player (iPhone, Mac and
/// the web all stream it from the file's own address).
class VideoWatchPlayer extends ChangeNotifier implements WatchPlayer {
  VideoWatchPlayer._(this._controller, {required this.hasSurface}) {
    _controller.addListener(_changed);
  }

  /// Starts [controller] and waits until it is ready to play. Throws when it
  /// can not be (the controller is released then).
  static Future<VideoWatchPlayer> open(
    VideoPlayerController controller, {
    required bool hasSurface,
  }) async {
    try {
      await controller.initialize().timeout(const Duration(seconds: 25));
      await controller.setLooping(false);
    } on Object {
      unawaited(controller.dispose());
      rethrow;
    }
    return VideoWatchPlayer._(controller, hasSurface: hasSurface);
  }

  final VideoPlayerController _controller;
  var _closed = false;

  @override
  final bool hasSurface;

  void _changed() {
    if (!_closed) {
      notifyListeners();
    }
  }

  @override
  Duration get position => _controller.value.position;

  @override
  Duration? get duration {
    final length = _controller.value.duration;
    return length == Duration.zero ? null : length;
  }

  @override
  bool get isPlaying => _controller.value.isPlaying;

  @override
  bool get isBuffering => _controller.value.isBuffering;

  @override
  bool get hasEnded {
    final length = duration;
    return length != null &&
        !isPlaying &&
        position >= length - const Duration(milliseconds: 250);
  }

  @override
  bool get remoteControl => true;

  @override
  bool get surfaceInteractive => false;

  @override
  Future<void> play() => _controller.play();

  @override
  Future<void> pause() => _controller.pause();

  @override
  Future<void> seek(Duration position) => _controller.seekTo(position);

  @override
  Future<void> setMuted(bool muted) => _controller.setVolume(muted ? 0 : 1);

  @override
  Widget buildSurface(BuildContext context) {
    final value = _controller.value;
    final size = value.size;
    final ratio = size.isEmpty ? 16 / 9 : size.width / size.height;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(_controller)),
      ),
    );
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _controller.removeListener(_changed);
    try {
      await _controller.dispose();
    } on Object {
      // Already gone.
    }
    super.dispose();
  }
}

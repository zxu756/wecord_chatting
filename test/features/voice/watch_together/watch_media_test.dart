import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/voice/watch_together/watch_media.dart';
import 'package:wecord/features/voice/watch_together/watch_protocol.dart';

/// A controller that plays nothing; the test moves its clock.
class _FakeController extends VideoPlayerController {
  _FakeController(super.uri, {this.failToLoad = false, this.neverLoads = false})
    : super.networkUrl();

  final bool failToLoad;
  final bool neverLoads;
  double? volume;
  var disposed = false;
  final calls = <String>[];

  @override
  Future<void> initialize() async {
    if (neverLoads) {
      await Completer<void>().future;
    }
    if (failToLoad) {
      throw Exception('The media could not be loaded');
    }
    value = value.copyWith(
      isInitialized: true,
      duration: const Duration(minutes: 5),
      size: const Size(1280, 720),
    );
  }

  @override
  Future<void> play() async {
    calls.add('play');
    value = value.copyWith(isPlaying: true);
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    value = value.copyWith(isPlaying: false);
  }

  @override
  Future<void> seekTo(Duration position) async {
    calls.add('seek:${position.inMilliseconds}');
    value = value.copyWith(position: position);
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  // The real dispose would talk to a platform player that is not there.
  @override
  // ignore: must_call_super
  Future<void> dispose() async {
    disposed = true;
  }
}

WatchLink _link(String url) => parseWatchLink(url).link!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads, then plays, pauses and seeks the controller', () async {
    late _FakeController controller;
    VideoFormat? format;
    final player = VideoPlayerWatchMedia(
      controller: (uri, hint) {
        format = hint;
        return controller = _FakeController(uri);
      },
    );
    expect(player.value.phase, WatchMediaPhase.idle);

    await player.open(_link('https://cdn.example.com/a.mp4'));
    expect(format, isNull);
    expect(player.value.ready, isTrue);
    expect(player.value.duration, const Duration(minutes: 5));
    expect(player.value.aspectRatio, closeTo(16 / 9, 0.01));

    await player.play();
    expect(controller.calls, ['play']);
    expect(player.value.playing, isTrue);

    await player.seekTo(const Duration(seconds: 42));
    expect(player.value.position, const Duration(seconds: 42));

    await player.pause();
    expect(player.value.playing, isFalse);
    await player.dispose();
  });

  test('tells the platform when the link is an HLS stream', () async {
    VideoFormat? format;
    final player = VideoPlayerWatchMedia(
      controller: (uri, hint) {
        format = hint;
        return _FakeController(uri);
      },
    );
    await player.open(_link('https://cdn.example.com/live/index.m3u8'));
    expect(format, VideoFormat.hls);
    await player.dispose();
  });

  test('muting sets the volume, also before the media is loaded', () async {
    late _FakeController controller;
    final player = VideoPlayerWatchMedia(
      controller: (uri, hint) => controller = _FakeController(uri),
    );
    await player.setMuted(true);
    await player.open(_link('https://cdn.example.com/a.mp3'));
    expect(controller.volume, 0);
    await player.setMuted(false);
    expect(controller.volume, 1);
    await player.dispose();
  });

  test('a link that can not be played is reported as failed', () async {
    final player = VideoPlayerWatchMedia(
      controller: (uri, hint) => _FakeController(uri, failToLoad: true),
    );
    await player.open(_link('https://cdn.example.com/a.mp4'));
    expect(player.value.failed, isTrue);
    expect(player.value.failure, WatchMediaFailure.cannotPlay);
    // Asking it to play does nothing and does not throw.
    await player.play();
    await player.dispose();
  });

  test('a link that never loads times out', () async {
    final player = VideoPlayerWatchMedia(
      loadTimeout: const Duration(milliseconds: 30),
      controller: (uri, hint) => _FakeController(uri, neverLoads: true),
    );
    await player.open(_link('https://cdn.example.com/a.mp4'));
    expect(player.value.failed, isTrue);
    expect(player.value.failure, WatchMediaFailure.timeout);
    await player.dispose();
  });

  test('an error while playing is reported', () async {
    late _FakeController controller;
    final player = VideoPlayerWatchMedia(
      controller: (uri, hint) => controller = _FakeController(uri),
    );
    await player.open(_link('https://cdn.example.com/a.mp4'));
    expect(player.value.ready, isTrue);
    controller.value = controller.value.copyWith(
      errorDescription: 'The network went away',
    );
    expect(player.value.failed, isTrue);
    await player.dispose();
  });

  test(
    'disposing releases the controller and later calls do nothing',
    () async {
      late _FakeController controller;
      final player = VideoPlayerWatchMedia(
        controller: (uri, hint) => controller = _FakeController(uri),
      );
      await player.open(_link('https://cdn.example.com/a.mp4'));
      await player.dispose();
      expect(controller.disposed, isTrue);
      await player.play();
      await player.seekTo(const Duration(seconds: 3));
      expect(controller.calls, isEmpty);
      // Disposing again is harmless.
      await player.dispose();
    },
  );
}

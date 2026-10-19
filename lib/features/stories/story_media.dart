import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart'
    show videoControllerFactoryProvider;
import 'package:wecord/features/stories/stories_models.dart';
import 'package:wecord/features/stories/stories_providers.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A picture of the private bucket: its signed link is fetched (and reused
/// while valid), a quiet block shows meanwhile and when it cannot be read.
class StoryImage extends ConsumerStatefulWidget {
  const StoryImage({
    required this.path,
    this.fit = BoxFit.cover,
    this.semanticLabel,
    super.key,
  });

  final String path;
  final BoxFit fit;
  final String? semanticLabel;

  @override
  ConsumerState<StoryImage> createState() => _StoryImageState();
}

class _StoryImageState extends ConsumerState<StoryImage> {
  var _retried = false;

  void _retry() {
    if (_retried) {
      return;
    }
    _retried = true;
    // The link may have expired: sign it again once.
    ref
        .read(chatSignedUrlCacheProvider)
        .evict(SignedUrlCache.keyFor(storiesBucket, widget.path));
    ref.invalidate(storyFileUrlProvider(widget.path));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final url = ref.watch(storyFileUrlProvider(widget.path));
    Widget placeholder([IconData? icon]) => ColoredBox(
      color: c.raised,
      child: icon == null
          ? null
          : Center(child: Icon(icon, size: 22, color: c.faint)),
    );
    return url.when(
      loading: placeholder,
      error: (error, stackTrace) => placeholder(Icons.broken_image_outlined),
      data: (url) => Image(
        image: ref.read(storyImageProviderFactory)(url),
        fit: widget.fit,
        gaplessPlayback: true,
        semanticLabel: widget.semanticLabel,
        excludeFromSemantics: widget.semanticLabel == null,
        loadingBuilder: (context, child, progress) =>
            progress == null ? child : placeholder(),
        errorBuilder: (context, error, stackTrace) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _retry();
            }
          });
          return placeholder(Icons.broken_image_outlined);
        },
      ),
    );
  }
}

/// The video of a daily, full bleed: its poster frame until it can play, then
/// the video. The viewer decides when it plays ([playing]) and hears about
/// its progress, so one bar can show photos and videos alike.
class StoryVideoSurface extends ConsumerStatefulWidget {
  const StoryVideoSurface({
    required this.path,
    required this.posterPath,
    required this.playing,
    required this.onProgress,
    required this.onEnded,
    this.onFailed,
    super.key,
  });

  final String path;
  final String? posterPath;

  /// Whether it should be playing now (the viewer pauses it for a long press,
  /// a sheet or the keyboard, and for reduced motion).
  final bool playing;

  /// The position as a fraction of its length, 0 to 1.
  final ValueChanged<double> onProgress;
  final VoidCallback onEnded;
  final VoidCallback? onFailed;

  @override
  ConsumerState<StoryVideoSurface> createState() => _StoryVideoSurfaceState();
}

class _StoryVideoSurfaceState extends ConsumerState<StoryVideoSurface> {
  VideoPlayerController? _controller;
  var _failed = false;
  var _ended = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void didUpdateWidget(covariant StoryVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.playing != oldWidget.playing) {
      _sync();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      controller.removeListener(_onChanged);
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  void _sync() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (widget.playing && !_ended) {
      unawaited(controller.play());
    } else {
      unawaited(controller.pause());
    }
  }

  Future<void> _start() async {
    try {
      final url = await ref.read(storyFileUrlProvider(widget.path).future);
      if (!mounted) {
        return;
      }
      final controller = ref.read(videoControllerFactoryProvider)(
        url: Uri.parse(url),
      );
      _controller = controller..addListener(_onChanged);
      await controller.initialize();
      await controller.setLooping(false);
      if (!mounted) {
        return;
      }
      setState(() {});
      _sync();
    } on Object {
      if (mounted) {
        setState(() => _failed = true);
        widget.onFailed?.call();
      }
    }
  }

  void _onChanged() {
    final controller = _controller;
    if (controller == null || !mounted) {
      return;
    }
    final value = controller.value;
    if (value.hasError && !_failed) {
      setState(() => _failed = true);
      widget.onFailed?.call();
      return;
    }
    if (!value.isInitialized || value.duration <= Duration.zero) {
      return;
    }
    final fraction =
        value.position.inMilliseconds / value.duration.inMilliseconds;
    widget.onProgress(fraction.clamp(0.0, 1.0));
    if (!_ended && value.position >= value.duration) {
      _ended = true;
      widget.onEnded();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final poster = widget.posterPath;
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!ready && poster != null)
            StoryImage(path: poster, fit: BoxFit.contain),
          if (ready)
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio > 0
                    ? controller.value.aspectRatio
                    : 9 / 16,
                child: VideoPlayer(controller),
              ),
            ),
          if (_failed)
            Center(
              child: Icon(
                Icons.videocam_off_outlined,
                size: 36,
                color: c.faint,
              ),
            ),
          if (!ready && !_failed)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ],
      ),
    );
  }
}

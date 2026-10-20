import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_controller.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_service.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_platform_io.dart'
    if (dart.library.js_interop) 'package:wecord/features/file_preview/preview_platform_web.dart'
    as platform;
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Makes the player for a video; tests swap in a fake.
typedef VideoControllerFactory =
    VideoPlayerController Function({Uri? url, String? localPath});

final videoControllerFactoryProvider = Provider<VideoControllerFactory>((ref) {
  return ({Uri? url, String? localPath}) => localPath != null
      ? platform.localVideoController(localPath)
      : VideoPlayerController.networkUrl(url!);
});

const videoSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

/// A video with its poster frame until it plays, and a glass control bar:
/// play/pause, scrubber, time, speed (0.5–2×), mute and fullscreen. Plays
/// the cached copy when there is one, else streams it.
class VideoPreview extends ConsumerStatefulWidget {
  const VideoPreview({
    required this.file,
    required this.active,
    required this.chromeVisible,
    required this.onTap,
    required this.fullscreen,
    required this.onFullscreenChanged,
    this.onDownload,
    super.key,
  });

  final PreviewFile file;

  /// The page on screen; others pause.
  final bool active;
  final bool chromeVisible;
  final VoidCallback onTap;
  final bool fullscreen;
  final ValueChanged<bool> onFullscreenChanged;
  final VoidCallback? onDownload;

  @override
  ConsumerState<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends ConsumerState<VideoPreview> {
  VideoPlayerController? _controller;
  Object? _error;
  Uint8List? _poster;
  var _speed = 1.0;
  var _muted = false;
  var _scrubbing = false;
  double? _scrubValue;

  @override
  void initState() {
    super.initState();
    unawaited(_loadPoster());
    if (widget.active) {
      unawaited(_start());
    }
  }

  @override
  void didUpdateWidget(covariant VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      if (_controller == null) {
        unawaited(_start());
      }
    } else if (!widget.active && oldWidget.active) {
      unawaited(_controller?.pause());
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

  Future<void> _loadPoster() async {
    final poster = await ref
        .read(thumbnailServiceProvider)
        .thumbnailFor(widget.file)
        .catchError((Object _) => null);
    if (mounted && poster != null) {
      setState(() => _poster = poster);
    }
  }

  Future<void> _start() async {
    setState(() => _error = null);
    final factory = ref.read(videoControllerFactoryProvider);
    try {
      final cached = await ref
          .read(fileFetcherProvider)
          .cachedPath(widget.file);
      final controller = cached != null
          ? factory(localPath: cached)
          : factory(
              url: await ref
                  .read(filePreviewServiceProvider)
                  .fileUrl(widget.file),
            );
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      _controller = controller..addListener(_onChanged);
      await controller.initialize();
      await controller.setPlaybackSpeed(_speed);
      await controller.setVolume(_muted ? 0 : 1);
      // Someone who turned captions on gets them on every video.
      if (mounted &&
          ref.read(videoCaptionsOnProvider) &&
          ref.read(videoCaptionMakerProvider).available) {
        unawaited(ref.read(videoCaptionsProvider(widget.file).notifier).make());
      }
      // With reduced motion the video waits on its first frame until the
      // play button is pressed.
      if (mounted && widget.active && !WeCordMotion.reduceMotion(context)) {
        await controller.play();
      }
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  void _onChanged() {
    final value = _controller?.value;
    if (value != null && value.hasError && _error == null) {
      setState(() => _error = value.errorDescription ?? 'error');
      return;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _retry() async {
    final old = _controller;
    _controller = null;
    if (old != null) {
      old.removeListener(_onChanged);
      await old.dispose();
    }
    await _start();
  }

  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final value = controller.value;
    if (value.isPlaying) {
      unawaited(controller.pause());
    } else {
      if (value.duration > Duration.zero && value.position >= value.duration) {
        unawaited(controller.seekTo(Duration.zero));
      }
      unawaited(controller.play());
    }
  }

  void _cycleSpeed() {
    final next =
        videoSpeeds[(videoSpeeds.indexOf(_speed) + 1) % videoSpeeds.length];
    setState(() => _speed = next);
    unawaited(_controller?.setPlaybackSpeed(next));
    WeCordHaptics.selection();
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    unawaited(_controller?.setVolume(_muted ? 0 : 1));
  }

  /// Turns captions on or off; turning them on makes them if need be.
  void _toggleCaptions() {
    final on = !ref.read(videoCaptionsOnProvider);
    unawaited(ref.read(videoCaptionsOnProvider.notifier).set(on));
    if (on) {
      unawaited(ref.read(videoCaptionsProvider(widget.file).notifier).retry());
    }
    WeCordHaptics.selection();
  }

  @override
  Widget build(BuildContext context) {
    final file = widget.file;
    // Turned on while a video is open: made now.
    ref.listen(videoCaptionsOnProvider, (previous, on) {
      if (on && widget.active && _controller != null) {
        unawaited(ref.read(videoCaptionsProvider(file).notifier).make());
      }
    });
    if (_error != null) {
      return PreviewErrorView(
        file: file,
        title: tr("This video can't be played here."),
        message: tr('Download it to watch it in another app.'),
        onRetry: _retry,
        onDownload: widget.onDownload,
      );
    }
    final controller = _controller;
    final value = controller?.value;
    final ready = value != null && value.isInitialized;
    final poster = _poster;
    final aspect = ready && value.aspectRatio > 0
        ? value.aspectRatio
        : (file.width != null && file.height != null && file.height! > 0
              ? file.width! / file.height!
              : 16 / 9);

    final picture = Center(
      child: AspectRatio(
        aspectRatio: aspect,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (ready) VideoPlayer(controller!),
            if (!ready && poster != null)
              Image.memory(poster, fit: BoxFit.contain, gaplessPlayback: true),
            if (!ready || value.isBuffering)
              const Center(child: PreviewSpinner()),
          ],
        ),
      ),
    );

    return GestureDetector(
      key: ValueKey('video-preview-${file.key}'),
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onDoubleTap: () => widget.onFullscreenChanged(!widget.fullscreen),
      child: Stack(
        fit: StackFit.expand,
        children: [
          picture,
          if (ref.watch(videoCaptionMakerProvider).available)
            _captionLayer(context, value),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: AnimatedOpacity(
                opacity: widget.chromeVisible ? 1 : 0,
                duration: WeCordMotion.durationOf(context, WeCordMotion.base),
                child: IgnorePointer(
                  ignoring: !widget.chromeVisible,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: _controls(context, value, ready),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The line being said, and a note while captions are made or failed.
  Widget _captionLayer(BuildContext context, VideoPlayerValue? value) {
    final on = ref.watch(videoCaptionsOnProvider);
    final state = ref.watch(videoCaptionsProvider(widget.file));
    final dark = WeCordPalette.dark;
    if (!on) {
      return const SizedBox.shrink();
    }
    final cue = state.status == VideoCaptionStatus.ready
        ? state.captions?.at(value?.position ?? Duration.zero)
        : null;
    final note = switch (state.status) {
      VideoCaptionStatus.working => tr('Making captions on this device…'),
      VideoCaptionStatus.failed => _failureText(state.failure),
      _ => null,
    };
    final text = cue?.text ?? note;
    if (text == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 16,
      right: 16,
      // Clear of the control bar while it shows.
      bottom: widget.chromeVisible ? 132 : 40,
      child: IgnorePointer(
        ignoring: true,
        child: Center(
          child: Container(
            key: ValueKey(
              cue != null
                  ? 'video-caption-line'
                  : state.status == VideoCaptionStatus.failed
                  ? 'video-caption-failed'
                  : 'video-caption-working',
            ),
            constraints: const BoxConstraints(maxWidth: 640),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: dark.paper.withValues(alpha: cue != null ? 0.82 : 0.72),
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: cue != null ? 17 : 13,
                height: 1.3,
                fontWeight: cue != null ? FontWeight.w600 : FontWeight.w500,
                color: dark.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _failureText(VideoCaptionFailure? failure) {
    return switch (failure) {
      VideoCaptionFailure.noSpeech => tr('There is no speech in this video.'),
      VideoCaptionFailure.notAuthorized => tr(
        'Speech recognition is turned off for WeCord. Turn it on in Settings to get captions.',
      ),
      VideoCaptionFailure.language => tr(
        "This device can't make captions in this language without sending the sound away, so there are none.",
      ),
      VideoCaptionFailure.unreadable => tr(
        "The sound of this video can't be read here.",
      ),
      _ => tr('Captions could not be made.'),
    };
  }

  Widget _controls(BuildContext context, VideoPlayerValue? value, bool ready) {
    final c = context.tokens.colors;
    final duration = ready ? value!.duration : Duration.zero;
    final position = ready ? value!.position : Duration.zero;
    final max = duration.inMilliseconds.toDouble();
    final current = _scrubbing && _scrubValue != null
        ? _scrubValue!
        : position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble();
    final playing = value?.isPlaying ?? false;
    final narrow = MediaQuery.sizeOf(context).width < 480;
    final play = WeCordIconButton(
      key: const ValueKey('video-play-pause'),
      icon: playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
      tooltip: playing ? tr('Pause') : tr('Play'),
      variant: WeCordButtonVariant.ghost,
      size: 40,
      iconSize: 26,
      onPressed: ready ? _togglePlay : null,
    );
    final scrubber = SliderTheme(
      data: SliderThemeData(
        trackHeight: 4,
        activeTrackColor: c.ink,
        inactiveTrackColor: c.track,
        thumbColor: c.ink,
        overlayColor: c.ink.withValues(alpha: 0.12),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
      ),
      child: Slider(
        key: const ValueKey('video-scrubber'),
        value: max <= 0 ? 0 : current.clamp(0, max),
        max: max <= 0 ? 1 : max,
        semanticFormatterCallback: (v) =>
            _format(Duration(milliseconds: v.round())),
        onChangeStart: ready
            ? (v) => setState(() {
                _scrubbing = true;
                _scrubValue = v;
              })
            : null,
        onChanged: ready ? (v) => setState(() => _scrubValue = v) : null,
        onChangeEnd: ready
            ? (v) {
                unawaited(
                  _controller?.seekTo(Duration(milliseconds: v.round())),
                );
                setState(() => _scrubbing = false);
              }
            : null,
      ),
    );
    final elapsed = Text(
      _format(Duration(milliseconds: current.round())),
      style: _timeStyle(c),
    );
    final total = Text(_format(duration), style: _timeStyle(c));
    final speed = WeCordPressable(
      key: const ValueKey('video-speed'),
      tooltip: tr('Playback speed'),
      semanticLabel: tr('Playback speed'),
      onPressed: _cycleSpeed,
      builder: (context, states) => Container(
        height: 30,
        constraints: const BoxConstraints(minWidth: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: ShapeDecoration(
          color: states.contains(WidgetState.hovered)
              ? c.raisedStrong
              : c.raised,
          shape: const StadiumBorder(),
        ),
        child: Text(
          '${_speedLabel(_speed)}×',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
      ),
    );
    final captionsAvailable = ref.watch(videoCaptionMakerProvider).available;
    final captionsOn = ref.watch(videoCaptionsOnProvider);
    final captionState = ref.watch(videoCaptionsProvider(widget.file));
    final captions = !captionsAvailable
        ? null
        : captionState.isWorking && captionsOn
        ? SizedBox.square(
            key: const ValueKey('video-captions-working'),
            dimension: 36,
            child: Center(
              child: Semantics(
                label: tr('Making captions on this device…'),
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    value: captionState.progress,
                    color: c.ink,
                    backgroundColor: c.track,
                  ),
                ),
              ),
            ),
          )
        : WeCordIconButton(
            key: const ValueKey('video-captions'),
            icon: captionsOn
                ? Icons.closed_caption_rounded
                : Icons.closed_caption_off_rounded,
            tooltip: captionsOn ? tr('Turn off captions') : tr('Captions'),
            variant: WeCordButtonVariant.ghost,
            size: 36,
            onPressed: _toggleCaptions,
          );
    final mute = WeCordIconButton(
      key: const ValueKey('video-mute'),
      icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
      tooltip: _muted ? tr('Unmute') : tr('Mute'),
      variant: WeCordButtonVariant.ghost,
      size: 36,
      onPressed: _toggleMute,
    );
    final fullscreen = WeCordIconButton(
      key: const ValueKey('video-fullscreen'),
      icon: widget.fullscreen
          ? Icons.fullscreen_exit_rounded
          : Icons.fullscreen_rounded,
      tooltip: widget.fullscreen ? tr('Exit full screen') : tr('Full screen'),
      variant: WeCordButtonVariant.ghost,
      size: 36,
      onPressed: () => widget.onFullscreenChanged(!widget.fullscreen),
    );
    return WeCordGlass(
      key: const ValueKey('video-controls'),
      borderRadius: BorderRadius.circular(narrow ? WeCordRadii.xl : 30),
      padding: EdgeInsets.fromLTRB(6, narrow ? 2 : 4, 10, narrow ? 2 : 4),
      child: narrow
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Row(
                    children: [
                      elapsed,
                      Expanded(child: scrubber),
                      total,
                    ],
                  ),
                ),
                Row(
                  children: [
                    play,
                    const Spacer(),
                    speed,
                    ?captions,
                    mute,
                    fullscreen,
                  ],
                ),
              ],
            )
          : Row(
              children: [
                play,
                elapsed,
                Expanded(child: scrubber),
                total,
                const SizedBox(width: 4),
                speed,
                ?captions,
                mute,
                fullscreen,
              ],
            ),
    );
  }

  TextStyle _timeStyle(WeCordPalette c) => TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    color: c.muted,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  static String _speedLabel(double speed) => speed == speed.roundToDouble()
      ? speed.toStringAsFixed(0)
      : speed.toString();

  static String _format(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return hours > 0
        ? '$hours:${minutes.toString().padLeft(2, '0')}:$seconds'
        : '$minutes:$seconds';
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/preview_states.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What plays audio files; tests swap in a fake.
abstract interface class AudioFilePlayback {
  Stream<bool> get playingStream;
  Stream<Duration> get positionStream;
  Stream<Duration?> get durationStream;
  bool get playing;
  Duration get position;
  Duration? get duration;

  /// Loads [url] (a signed link) or [localPath]; returns the length.
  Future<Duration?> load({Uri? url, String? localPath});
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> setSpeed(double speed);
  Future<void> dispose();
}

final audioFilePlaybackFactoryProvider = Provider<AudioFilePlayback Function()>(
  (ref) => JustAudioFilePlayback.new,
);

class JustAudioFilePlayback implements AudioFilePlayback {
  final _player = AudioPlayer();

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  bool get playing => _player.playing;

  @override
  Duration get position => _player.position;

  @override
  Duration? get duration => _player.duration;

  @override
  Future<Duration?> load({Uri? url, String? localPath}) async {
    final duration = localPath != null
        ? await _player.setFilePath(localPath)
        : await _player.setUrl(url.toString());
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        unawaited(_player.pause());
        unawaited(_player.seek(Duration.zero));
      }
    });
    return duration;
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setSpeed(double speed) => _player.setSpeed(speed);

  @override
  Future<void> dispose() => _player.dispose();
}

/// Plays an audio file: a round play button, a scrubber and the time.
/// [compact] is the inline player in a chat file card; otherwise it is the
/// viewer's large player with the file's tile above it.
class AudioFilePlayer extends ConsumerStatefulWidget {
  const AudioFilePlayer({
    required this.file,
    this.compact = false,
    this.foreground,
    this.active = true,
    super.key,
  });

  final PreviewFile file;
  final bool compact;

  /// Text color inside a bubble.
  final Color? foreground;

  /// Pauses when false (another page of the viewer is showing).
  final bool active;

  @override
  ConsumerState<AudioFilePlayer> createState() => _AudioFilePlayerState();
}

class _AudioFilePlayerState extends ConsumerState<AudioFilePlayer> {
  AudioFilePlayback? _playback;
  final _subscriptions = <StreamSubscription<Object?>>[];
  var _loading = false;
  var _error = false;
  var _playing = false;
  var _position = Duration.zero;
  Duration? _duration;
  double? _dragValue;

  @override
  void didUpdateWidget(covariant AudioFilePlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.active && oldWidget.active) {
      unawaited(_playback?.pause());
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_playback?.dispose());
    super.dispose();
  }

  Future<AudioFilePlayback> _ensureLoaded() async {
    final existing = _playback;
    if (existing != null) {
      return existing;
    }
    final playback = ref.read(audioFilePlaybackFactoryProvider)();
    final cached = await ref.read(fileFetcherProvider).cachedPath(widget.file);
    final duration = cached != null
        ? await playback.load(localPath: cached)
        : await playback.load(
            url: await ref
                .read(filePreviewServiceProvider)
                .fileUrl(widget.file),
          );
    if (!mounted) {
      unawaited(playback.dispose());
      throw StateError('disposed');
    }
    _playback = playback;
    _duration = duration;
    _subscriptions
      ..add(playback.playingStream.listen((v) => setState(() => _playing = v)))
      ..add(
        playback.positionStream.listen((v) => setState(() => _position = v)),
      )
      ..add(
        playback.durationStream.listen((v) => setState(() => _duration = v)),
      );
    return playback;
  }

  Future<void> _toggle() async {
    if (_loading) {
      return;
    }
    if (_playing) {
      await _playback?.pause();
      return;
    }
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final playback = await _ensureLoaded();
      unawaited(playback.play());
    } catch (_) {
      if (mounted) {
        setState(() => _error = true);
      }
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final foreground = widget.foreground ?? c.ink;
    final total = _duration ?? Duration.zero;
    final max = total.inMilliseconds.toDouble();
    final value =
        _dragValue ??
        _position.inMilliseconds.clamp(0, total.inMilliseconds).toDouble();
    final buttonSize = widget.compact ? 36.0 : 64.0;
    final onButton = foreground == c.ink ? c.onInk : c.ink;

    final button = WeCordPressable(
      key: ValueKey('audio-play-${widget.file.key}'),
      onPressed: _toggle,
      tooltip: _playing ? tr('Pause') : tr('Play'),
      semanticLabel: _playing ? tr('Pause') : tr('Play'),
      shape: const CircleBorder(),
      pressedScale: 0.92,
      builder: (context, states) => Container(
        width: buttonSize,
        height: buttonSize,
        decoration: BoxDecoration(color: foreground, shape: BoxShape.circle),
        child: _loading
            ? Padding(
                padding: EdgeInsets.all(buttonSize * 0.3),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: onButton,
                ),
              )
            : Icon(
                _error
                    ? Icons.error_outline_rounded
                    : _playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: onButton,
                size: buttonSize * 0.56,
              ),
      ),
    );

    final slider = SliderTheme(
      data: SliderThemeData(
        trackHeight: widget.compact ? 3 : 4,
        activeTrackColor: foreground,
        inactiveTrackColor: foreground.withValues(alpha: 0.22),
        thumbColor: foreground,
        overlayColor: foreground.withValues(alpha: 0.1),
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: widget.compact ? 5 : 7,
        ),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        trackShape: const RoundedRectSliderTrackShape(),
      ),
      child: Slider(
        value: max <= 0 ? 0 : value.clamp(0, max),
        max: max <= 0 ? 1 : max,
        onChanged: _playback == null || max <= 0
            ? null
            : (v) => setState(() => _dragValue = v),
        onChangeEnd: (v) {
          unawaited(_playback?.seek(Duration(milliseconds: v.round())));
          setState(() => _dragValue = null);
        },
      ),
    );
    final time = Text(
      _duration == null
          ? '--:--'
          : '${_format(Duration(milliseconds: value.round()))} / ${_format(total)}',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: foreground.withValues(alpha: 0.65),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );

    if (widget.compact) {
      return Row(
        children: [
          button,
          Expanded(child: slider),
          time,
        ],
      );
    }
    return PreviewStateLayout(
      key: const ValueKey('audio-preview'),
      leading: FileTypeTile(file: widget.file, size: 96),
      title: widget.file.name,
      message: previewSubtitle(widget.file),
      below: Column(
        children: [
          slider,
          time,
          const SizedBox(height: WeCordSpace.x4),
          button,
          if (_error) ...[
            const SizedBox(height: WeCordSpace.x3),
            Text(
              tr("This audio can't be played here."),
              style: TextStyle(fontSize: 13, color: c.dangerText),
            ),
          ],
        ],
      ),
    );
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

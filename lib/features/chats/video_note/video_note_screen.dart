import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/chats/video_note/video_note_camera.dart';
import 'package:wecord/features/chats/video_note/video_note_models.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart'
    show videoControllerFactoryProvider;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What the recording page hands back when the person sends.
class VideoNoteResult {
  const VideoNoteResult({required this.clip, required this.viewOnce});

  final VideoNoteClip clip;
  final bool viewOnce;
}

/// Opens the recording page; resolves to the recording to send, or null.
Future<VideoNoteResult?> showVideoNoteRecorder(
  BuildContext context, {
  bool canViewOnce = true,
}) {
  return Navigator.of(context, rootNavigator: true).push<VideoNoteResult>(
    PageRouteBuilder<VideoNoteResult>(
      fullscreenDialog: true,
      opaque: true,
      pageBuilder: (context, _, _) => VideoNoteScreen(canViewOnce: canViewOnce),
      transitionsBuilder: (context, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );
}

enum _Stage { opening, ready, recording, review, failed }

/// A page on a dark ground (it is a camera): the picture of the front camera
/// in a circle with a ring that fills up to 60 seconds, a button to record
/// (tap to start and stop, or hold), then the recording played back in the
/// circle with "Record again" and "Send".
class VideoNoteScreen extends ConsumerStatefulWidget {
  const VideoNoteScreen({this.canViewOnce = true, super.key});

  final bool canViewOnce;

  @override
  ConsumerState<VideoNoteScreen> createState() => _VideoNoteScreenState();
}

class _VideoNoteScreenState extends ConsumerState<VideoNoteScreen> {
  late final VideoNoteCamera _camera = ref.read(
    videoNoteCameraFactoryProvider,
  )();
  var _stage = _Stage.opening;
  VideoNoteCameraProblem? _problem;
  Timer? _ticker;
  final _watch = clock.stopwatch();
  var _elapsed = Duration.zero;
  var _holding = false;
  VideoNoteClip? _clip;
  VideoPlayerController? _player;
  var _viewOnce = false;
  String? _notice;
  var _disposed = false;

  @override
  void initState() {
    super.initState();
    unawaited(_open());
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_player?.dispose());
    unawaited(_camera.dispose());
    super.dispose();
  }

  Future<void> _open() async {
    try {
      // Waits for the picture to be on screen where the plugin needs that.
      await _camera.open();
      if (_disposed) {
        return;
      }
      setState(() => _stage = _Stage.ready);
    } on VideoNoteCameraException catch (error) {
      if (!_disposed) {
        setState(() {
          _stage = _Stage.failed;
          _problem = error.problem;
        });
      }
    } catch (_) {
      if (!_disposed) {
        setState(() {
          _stage = _Stage.failed;
          _problem = VideoNoteCameraProblem.failed;
        });
      }
    }
  }

  void _say(String message) {
    SemanticsService.sendAnnouncement(
      View.of(context),
      message,
      Directionality.of(context),
    );
  }

  Future<void> _start() async {
    if (_stage != _Stage.ready) {
      return;
    }
    try {
      await _camera.startRecording();
    } catch (_) {
      if (mounted) {
        setState(() => _notice = tr('Could not start recording. Try again.'));
      }
      return;
    }
    if (!mounted) {
      return;
    }
    _watch
      ..reset()
      ..start();
    _elapsed = Duration.zero;
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) {
        return;
      }
      setState(() => _elapsed = _watch.elapsed);
      if (_elapsed >= const Duration(seconds: maxVideoNoteSeconds)) {
        unawaited(_stop());
      }
    });
    setState(() {
      _stage = _Stage.recording;
      _notice = null;
    });
    _say(tr('Recording started'));
  }

  Future<void> _stop() async {
    if (_stage != _Stage.recording) {
      return;
    }
    _ticker?.cancel();
    _watch.stop();
    setState(() => _stage = _Stage.opening);
    VideoNoteClip? clip;
    try {
      clip = await _camera.stopRecording();
    } catch (_) {
      clip = null;
    }
    if (!mounted) {
      return;
    }
    if (clip == null || clip.tooShort) {
      setState(() {
        _stage = _Stage.ready;
        _elapsed = Duration.zero;
        _notice = tr('That was too short. Hold a little longer.');
      });
      return;
    }
    if (clip.tooBig) {
      setState(() {
        _stage = _Stage.ready;
        _elapsed = Duration.zero;
        _notice = tr(
          'That video message is too large to send. Record a shorter one.',
        );
      });
      return;
    }
    await _review(clip);
  }

  Future<void> _review(VideoNoteClip clip) async {
    final factory = ref.read(videoControllerFactoryProvider);
    final player = factory(localPath: clip.file.path);
    try {
      await player.initialize();
      await player.setLooping(true);
      await player.play();
    } catch (_) {
      // The recording still sends; it just cannot be played back here.
    }
    if (!mounted) {
      unawaited(player.dispose());
      return;
    }
    setState(() {
      _clip = clip;
      _player = player;
      _stage = _Stage.review;
    });
    _say(tr('Recording done. Check it, then send.'));
  }

  Future<void> _again() async {
    final player = _player;
    setState(() {
      _player = null;
      _clip = null;
      _elapsed = Duration.zero;
      _stage = _Stage.ready;
      _notice = null;
    });
    await player?.dispose();
  }

  Future<void> _close() async {
    if (_stage == _Stage.recording) {
      await _camera.cancelRecording();
    }
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _send() {
    final clip = _clip;
    if (clip == null) {
      return;
    }
    Navigator.of(context).pop(VideoNoteResult(clip: clip, viewOnce: _viewOnce));
  }

  void _togglePlayback() {
    final player = _player;
    if (player == null) {
      return;
    }
    setState(() {
      if (player.value.isPlaying) {
        unawaited(player.pause());
      } else {
        unawaited(player.play());
      }
    });
  }

  String _clockText(Duration time) {
    final seconds = time.inSeconds;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Theme(
      data: Theme.of(context).copyWith(brightness: Brightness.dark),
      child: Scaffold(
        backgroundColor: const Color(0xFF0B0B0F),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final diameter = (box.maxHeight - 290).clamp(150.0, 340.0);
              final width = (box.maxWidth - 48).clamp(150.0, 340.0);
              final size = diameter < width ? diameter : width;
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: box.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _TopBar(
                        title: tr('Video message'),
                        onClose: () => unawaited(_close()),
                        onSwitch: _camera.canSwitch && (_stage == _Stage.ready)
                            ? () async {
                                await _camera.switchCamera();
                                if (mounted) {
                                  setState(() {});
                                }
                              }
                            : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _stage == _Stage.failed
                            ? _Failure(
                                problem: _problem,
                                onClose: () => unawaited(_close()),
                              )
                            : _CircleStage(
                                size: size,
                                camera: _camera,
                                stage: _stage,
                                elapsed: _elapsed,
                                player: _player,
                                onTapPlayer: _togglePlayback,
                                tokens: tokens,
                              ),
                      ),
                      _Controls(
                        stage: _stage,
                        elapsed: _elapsed,
                        clockText: _clockText,
                        notice: _notice,
                        canViewOnce: widget.canViewOnce,
                        viewOnce: _viewOnce,
                        onViewOnce: (value) =>
                            setState(() => _viewOnce = value),
                        holding: _holding,
                        onTapRecord: () {
                          if (_stage == _Stage.ready) {
                            unawaited(_start());
                          } else if (_stage == _Stage.recording) {
                            unawaited(_stop());
                          }
                        },
                        onHoldStart: () {
                          if (_stage == _Stage.ready) {
                            _holding = true;
                            unawaited(_start());
                          }
                        },
                        onHoldEnd: () {
                          if (_holding && _stage == _Stage.recording) {
                            unawaited(_stop());
                          }
                          _holding = false;
                        },
                        onAgain: () => unawaited(_again()),
                        onSend: _send,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.onClose,
    required this.onSwitch,
  });

  final String title;
  final VoidCallback onClose;
  final VoidCallback? onSwitch;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('video-note-close'),
            tooltip: tr('Close'),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: onClose,
          ),
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: onSwitch == null
                ? null
                : IconButton(
                    key: const ValueKey('video-note-switch'),
                    tooltip: tr('Switch camera'),
                    icon: const Icon(
                      Icons.flip_camera_ios_outlined,
                      color: Colors.white,
                    ),
                    onPressed: onSwitch,
                  ),
          ),
        ],
      ),
    );
  }
}

class _CircleStage extends StatelessWidget {
  const _CircleStage({
    required this.size,
    required this.camera,
    required this.stage,
    required this.elapsed,
    required this.player,
    required this.onTapPlayer,
    required this.tokens,
  });

  final double size;
  final VideoNoteCamera camera;
  final _Stage stage;
  final Duration elapsed;
  final VideoPlayerController? player;
  final VoidCallback onTapPlayer;
  final WeCordTokens tokens;

  @override
  Widget build(BuildContext context) {
    final reviewing = stage == _Stage.review && player != null;
    final progress = (elapsed.inMilliseconds / (maxVideoNoteSeconds * 1000))
        .clamp(0.0, 1.0);
    final live = stage != _Stage.review;
    return SizedBox(
      width: size + 20,
      height: size + 20,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size + 12,
            height: size + 12,
            child: CircularProgressIndicator(
              key: const ValueKey('video-note-ring'),
              value: stage == _Stage.recording ? progress : 0,
              strokeWidth: 4,
              color: const Color(0xFFFF5A5F),
              backgroundColor: Colors.white24,
              semanticsLabel: tr('Recording length'),
            ),
          ),
          Semantics(
            label: reviewing
                ? tr('Your recording. Double tap to pause or play.')
                : tr('Camera picture'),
            button: reviewing,
            onTap: reviewing ? onTapPlayer : null,
            child: GestureDetector(
              onTap: reviewing ? onTapPlayer : null,
              child: ClipOval(
                child: Container(
                  width: size,
                  height: size,
                  color: Colors.black,
                  child: reviewing
                      ? _Cover(
                          aspect: player!.value.aspectRatio > 0
                              ? player!.value.aspectRatio
                              : 1,
                          child: VideoPlayer(player!),
                        )
                      : live
                      ? _Cover(
                          aspect: camera.previewAspect,
                          child: camera.buildPreview(),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          if (stage == _Stage.opening)
            const CircularProgressIndicator(color: Colors.white),
          if (reviewing && !player!.value.isPlaying)
            const IgnorePointer(
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 56,
              ),
            ),
        ],
      ),
    );
  }
}

/// [child] filling its box like a cover, cropped (a circle shows the middle
/// of a picture wider or taller than itself).
class _Cover extends StatelessWidget {
  const _Cover({required this.aspect, required this.child});

  final double aspect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(width: 1000 * aspect, height: 1000, child: child),
    );
  }
}

class _Failure extends StatelessWidget {
  const _Failure({required this.problem, required this.onClose});

  final VideoNoteCameraProblem? problem;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final (title, hint) = switch (problem) {
      VideoNoteCameraProblem.denied => (
        tr('Camera or microphone is off'),
        tr(
          'Allow the camera and the microphone for WeCord in your system settings (or in the browser), then try again.',
        ),
      ),
      VideoNoteCameraProblem.missing => (
        tr('No camera found'),
        tr('Connect a camera and a microphone, then try again.'),
      ),
      VideoNoteCameraProblem.unsupported => (
        tr("This device can't record video messages"),
        tr(
          'Send a video from Photos and videos instead, or try another browser.',
        ),
      ),
      _ => (tr('Could not open the camera'), tr('Close it and try again.')),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.videocam_off_outlined,
            color: Colors.white70,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            key: const ValueKey('video-note-failure-close'),
            onPressed: onClose,
            child: Text(tr('Close')),
          ),
        ],
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.stage,
    required this.elapsed,
    required this.clockText,
    required this.notice,
    required this.canViewOnce,
    required this.viewOnce,
    required this.onViewOnce,
    required this.holding,
    required this.onTapRecord,
    required this.onHoldStart,
    required this.onHoldEnd,
    required this.onAgain,
    required this.onSend,
  });

  final _Stage stage;
  final Duration elapsed;
  final String Function(Duration) clockText;
  final String? notice;
  final bool canViewOnce;
  final bool viewOnce;
  final ValueChanged<bool> onViewOnce;
  final bool holding;
  final VoidCallback onTapRecord;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;
  final VoidCallback onAgain;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final left = maxVideoNoteSeconds - elapsed.inSeconds;
    final counting =
        stage == _Stage.recording && left <= videoNoteCountdownSeconds;
    final hint = switch (stage) {
      _Stage.recording =>
        counting
            ? tr('{count} seconds left', {'count': left})
            : tr('Tap again to stop'),
      _Stage.review => tr('Check it, then send.'),
      _Stage.failed => '',
      _ => tr('Tap to record, or hold the button. Up to 60 seconds.'),
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (stage == _Stage.recording)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Semantics(
                liveRegion: false,
                child: Text(
                  clockText(elapsed),
                  key: const ValueKey('video-note-clock'),
                  style: TextStyle(
                    color: counting ? const Color(0xFFFF8A8E) : Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          if (notice != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                notice!,
                key: const ValueKey('video-note-notice'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFFFFB4B6), fontSize: 14),
              ),
            ),
          if (hint.isNotEmpty)
            Text(
              hint,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          const SizedBox(height: 16),
          if (stage == _Stage.review) ...[
            if (canViewOnce)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: FilterChip(
                  key: const ValueKey('video-note-view-once'),
                  avatar: const Icon(Icons.timer_outlined, size: 18),
                  label: Text(tr('View once')),
                  selected: viewOnce,
                  onSelected: onViewOnce,
                ),
              ),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('video-note-again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white54),
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: onAgain,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(tr('Record again')),
                ),
                FilledButton.icon(
                  key: const ValueKey('video-note-send'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  onPressed: onSend,
                  icon: const Icon(Icons.send_rounded),
                  label: Text(tr('Send')),
                ),
              ],
            ),
          ] else if (stage != _Stage.failed)
            _RecordButton(
              recording: stage == _Stage.recording,
              enabled: stage == _Stage.ready || stage == _Stage.recording,
              onTap: onTapRecord,
              onHoldStart: onHoldStart,
              onHoldEnd: onHoldEnd,
            ),
        ],
      ),
    );
  }
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.recording,
    required this.enabled,
    required this.onTap,
    required this.onHoldStart,
    required this.onHoldEnd,
  });

  final bool recording;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onHoldStart;
  final VoidCallback onHoldEnd;

  @override
  Widget build(BuildContext context) {
    final duration = WeCordMotion.durationOf(context, WeCordMotion.quick);
    return Semantics(
      button: true,
      enabled: enabled,
      label: recording ? tr('Stop recording') : tr('Start recording'),
      onTap: enabled ? onTap : null,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const ValueKey('video-note-record'),
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          onLongPressStart: enabled ? (_) => onHoldStart() : null,
          onLongPressEnd: enabled ? (_) => onHoldEnd() : null,
          child: SizedBox(
            width: 88,
            height: 88,
            child: Center(
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: enabled ? Colors.white : Colors.white30,
                    width: 4,
                  ),
                ),
                child: AnimatedContainer(
                  duration: duration,
                  decoration: BoxDecoration(
                    color: enabled
                        ? const Color(0xFFFF4D52)
                        : const Color(0x66FF4D52),
                    borderRadius: BorderRadius.circular(recording ? 12 : 40),
                  ),
                  margin: EdgeInsets.all(recording ? 12 : 0),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_controller.dart';
import 'package:wecord/features/accessibility/video_captions/video_captions_service.dart';
import 'package:wecord/features/chats/offline/outbox.dart'
    show isPendingMessageId;
import 'package:wecord/features/file_preview/file_fetcher.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart'
    show videoControllerFactoryProvider;
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How many round videos loop in the chat at once; the rest show their
/// first picture until opened (a list of them must not start a dozen
/// players).
const maxLoopingVideoNotes = 3;
var _looping = 0;

/// "0:12" for a duration in milliseconds.
String videoNoteLength(int milliseconds) {
  final seconds = (milliseconds / 1000).round();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}

/// A round video message in the chat (A13): a circle that plays muted and
/// loops while it is in view, with its length at the bottom; a tap opens it
/// larger, with sound.
class VideoNoteBubble extends ConsumerStatefulWidget {
  const VideoNoteBubble({
    required this.message,
    required this.attachment,
    this.size = 200,
    super.key,
  });

  final ChatMessage message;
  final FileAttachment attachment;
  final double size;

  @override
  ConsumerState<VideoNoteBubble> createState() => _VideoNoteBubbleState();
}

class _VideoNoteBubbleState extends ConsumerState<VideoNoteBubble> {
  VideoPlayerController? _controller;
  Uint8List? _poster;
  var _counted = false;
  var _started = false;

  PreviewFile get _file => PreviewFile.fromFileAttachment(
    widget.attachment,
    messageId: widget.message.id,
    conversationId: widget.message.conversationId,
    senderName:
        widget.message.senderNickname ?? widget.message.sender?.displayName,
    sentAt: widget.message.createdAt,
  );

  bool get _pending => isPendingMessageId(widget.message.id);

  @override
  void initState() {
    super.initState();
    if (!_pending) {
      unawaited(_loadPoster());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started && !_pending && !MediaQuery.disableAnimationsOf(context)) {
      _started = true;
      unawaited(_startLoop());
    }
  }

  @override
  void didUpdateWidget(covariant VideoNoteBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The sent message replaced the one still uploading.
    if (!_started && oldWidget.message.id != widget.message.id && !_pending) {
      unawaited(_loadPoster());
      if (!MediaQuery.disableAnimationsOf(context)) {
        _started = true;
        unawaited(_startLoop());
      }
    }
  }

  @override
  void dispose() {
    if (_counted) {
      _looping -= 1;
    }
    unawaited(_controller?.dispose());
    super.dispose();
  }

  Future<void> _loadPoster() async {
    final poster = await ref
        .read(thumbnailServiceProvider)
        .thumbnailFor(_file)
        .catchError((Object _) => null);
    if (mounted && poster != null) {
      setState(() => _poster = poster);
    }
  }

  Future<void> _startLoop() async {
    if (_looping >= maxLoopingVideoNotes) {
      return;
    }
    _looping += 1;
    _counted = true;
    try {
      final file = _file;
      final factory = ref.read(videoControllerFactoryProvider);
      final cached = await ref.read(fileFetcherProvider).cachedPath(file);
      final controller = cached != null
          ? factory(localPath: cached)
          : factory(
              url: await ref.read(filePreviewServiceProvider).fileUrl(file),
            );
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      _controller = controller;
      await controller.initialize();
      await controller.setVolume(0);
      await controller.setLooping(true);
      await controller.play();
      if (mounted) {
        setState(() {});
      }
    } on Object {
      // The picture stays; a tap opens it with the full viewer's messages.
      final controller = _controller;
      _controller = null;
      unawaited(controller?.dispose());
      if (_counted) {
        _counted = false;
        _looping -= 1;
      }
    }
  }

  Future<void> _open() async {
    if (_pending) {
      return;
    }
    // The loop gives way to the viewer.
    unawaited(_controller?.pause());
    await showVideoNoteViewer(
      context,
      file: _file,
      durationMs: widget.attachment.videoNoteMs ?? 0,
      poster: _poster,
    );
    if (mounted) {
      unawaited(_controller?.play());
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final size = widget.size;
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final length = widget.attachment.videoNoteMs ?? 0;
    final label = length > 0
        ? tr('Video message, {time}', {'time': videoNoteLength(length)})
        : tr('Video message');
    return Semantics(
      button: !_pending,
      label: _pending ? tr('Video message, sending') : label,
      hint: _pending ? null : tr('Double tap to watch'),
      onTap: _pending ? null : _open,
      child: ExcludeSemantics(
        child: GestureDetector(
          key: ValueKey('video-note-${widget.message.id}'),
          onTap: _pending ? null : () => unawaited(_open()),
          child: SizedBox(
            width: size,
            height: size,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: c.lineSoft, width: 1.5),
              ),
              child: ClipOval(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: c.well),
                    if (_poster != null)
                      Image.memory(
                        _poster!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      ),
                    if (ready)
                      FittedBox(
                        fit: BoxFit.cover,
                        clipBehavior: Clip.hardEdge,
                        child: SizedBox(
                          width: controller.value.size.width,
                          height: controller.value.size.height,
                          child: VideoPlayer(controller),
                        ),
                      ),
                    if (_pending)
                      const Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(strokeWidth: 3),
                        ),
                      )
                    else if (!ready)
                      Center(
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 44,
                          color: _poster == null ? c.muted : Colors.white,
                        ),
                      ),
                    if (length > 0)
                      Positioned(
                        bottom: 10,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              videoNoteLength(length),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens a round video larger and plays it with sound from the start; a tap
/// on the picture pauses it, "Captions" shows what is said (made on this
/// device, like captions of any video).
Future<void> showVideoNoteViewer(
  BuildContext context, {
  required PreviewFile file,
  required int durationMs,
  Uint8List? poster,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: tr('Close'),
    barrierColor: Colors.black87,
    transitionDuration: WeCordMotion.durationOf(context, WeCordMotion.base),
    pageBuilder: (context, _, _) =>
        VideoNoteViewer(file: file, durationMs: durationMs, poster: poster),
    transitionBuilder: (context, animation, _, child) => FadeTransition(
      opacity: animation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.92, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    ),
  );
}

class VideoNoteViewer extends ConsumerStatefulWidget {
  const VideoNoteViewer({
    required this.file,
    required this.durationMs,
    this.poster,
    super.key,
  });

  final PreviewFile file;
  final int durationMs;
  final Uint8List? poster;

  @override
  ConsumerState<VideoNoteViewer> createState() => _VideoNoteViewerState();
}

class _VideoNoteViewerState extends ConsumerState<VideoNoteViewer> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    final controller = _controller;
    _controller = null;
    controller?.removeListener(_changed);
    unawaited(controller?.dispose());
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _start() async {
    try {
      final file = widget.file;
      final factory = ref.read(videoControllerFactoryProvider);
      final cached = await ref.read(fileFetcherProvider).cachedPath(file);
      final controller = cached != null
          ? factory(localPath: cached)
          : factory(
              url: await ref.read(filePreviewServiceProvider).fileUrl(file),
            );
      if (!mounted) {
        unawaited(controller.dispose());
        return;
      }
      _controller = controller..addListener(_changed);
      await controller.initialize();
      await controller.setVolume(1);
      if (mounted &&
          ref.read(videoCaptionsOnProvider) &&
          ref.read(videoCaptionMakerProvider).available) {
        unawaited(ref.read(videoCaptionsProvider(file).notifier).make());
      }
      await controller.play();
    } on Object catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    }
  }

  void _togglePlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      unawaited(controller.pause());
    } else {
      unawaited(controller.play());
    }
  }

  void _toggleCaptions() {
    final on = !ref.read(videoCaptionsOnProvider);
    unawaited(ref.read(videoCaptionsOnProvider.notifier).set(on));
    if (on) {
      unawaited(ref.read(videoCaptionsProvider(widget.file).notifier).retry());
    }
  }

  @override
  Widget build(BuildContext context) {
    final box = MediaQuery.sizeOf(context);
    final size = (box.shortestSide - 48).clamp(180.0, 420.0);
    final controller = _controller;
    final value = controller?.value;
    final ready = value != null && value.isInitialized;
    final total = ready ? value.duration.inMilliseconds : widget.durationMs;
    final progress = ready && total > 0
        ? (value.position.inMilliseconds / total).clamp(0.0, 1.0)
        : 0.0;
    final captionsAvailable = ref.watch(videoCaptionMakerProvider).available;
    final captionsOn = ref.watch(videoCaptionsOnProvider);
    final captions = ref.watch(videoCaptionsProvider(widget.file));
    final cue = captionsOn && captions.status == VideoCaptionStatus.ready
        ? captions.captions?.at(value?.position ?? Duration.zero)?.text
        : null;
    final note = captionsOn
        ? switch (captions.status) {
            VideoCaptionStatus.working => tr('Making captions on this device…'),
            VideoCaptionStatus.failed => tr('Captions could not be made.'),
            _ => null,
          }
        : null;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          tr("This video can't be played here."),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                          ),
                        ),
                      )
                    else
                      SizedBox(
                        width: size + 16,
                        height: size + 16,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: size + 12,
                              height: size + 12,
                              child: CircularProgressIndicator(
                                value: progress,
                                strokeWidth: 3,
                                color: Colors.white,
                                backgroundColor: Colors.white24,
                                semanticsLabel: tr('Playback position'),
                              ),
                            ),
                            Semantics(
                              button: true,
                              label: ready && value.isPlaying
                                  ? tr('Pause')
                                  : tr('Play'),
                              onTap: _togglePlayback,
                              child: ExcludeSemantics(
                                child: GestureDetector(
                                  key: const ValueKey(
                                    'video-note-viewer-picture',
                                  ),
                                  onTap: _togglePlayback,
                                  child: ClipOval(
                                    child: SizedBox(
                                      width: size,
                                      height: size,
                                      child: Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          const ColoredBox(color: Colors.black),
                                          if (!ready && widget.poster != null)
                                            Image.memory(
                                              widget.poster!,
                                              fit: BoxFit.cover,
                                            ),
                                          if (ready)
                                            FittedBox(
                                              fit: BoxFit.cover,
                                              clipBehavior: Clip.hardEdge,
                                              child: SizedBox(
                                                width: value.size.width,
                                                height: value.size.height,
                                                child: VideoPlayer(controller!),
                                              ),
                                            ),
                                          if (!ready)
                                            const Center(
                                              child: CircularProgressIndicator(
                                                color: Colors.white,
                                              ),
                                            )
                                          else if (!value.isPlaying)
                                            const Center(
                                              child: Icon(
                                                Icons.play_arrow_rounded,
                                                color: Colors.white,
                                                size: 64,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    if (cue != null || note != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Text(
                            cue ?? note!,
                            key: ValueKey(
                              cue != null
                                  ? 'video-caption-line'
                                  : 'video-caption-note',
                            ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: cue != null ? 17 : 13,
                              height: 1.3,
                              fontWeight: cue != null
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                key: const ValueKey('video-note-viewer-close'),
                tooltip: tr('Close'),
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            if (captionsAvailable)
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(
                  key: const ValueKey('video-note-viewer-captions'),
                  tooltip: captionsOn
                      ? tr('Turn off captions')
                      : tr('Captions'),
                  isSelected: captionsOn,
                  icon: const Icon(
                    Icons.closed_caption_outlined,
                    color: Colors.white,
                  ),
                  selectedIcon: const Icon(
                    Icons.closed_caption,
                    color: Colors.white,
                  ),
                  onPressed: _toggleCaptions,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

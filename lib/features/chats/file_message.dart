import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens a sent file in the browser or the app that handles it; tests
/// override it.
final fileOpenerProvider = Provider<Future<void> Function(Uri url)>((ref) {
  return (url) async {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  };
});

IconData fileIconFor(String mimeType) {
  if (mimeType.startsWith('video/')) {
    return Icons.movie_outlined;
  }
  if (mimeType.startsWith('audio/')) {
    return Icons.audio_file_outlined;
  }
  if (mimeType.startsWith('image/')) {
    return Icons.image_outlined;
  }
  if (mimeType == 'application/pdf') {
    return Icons.picture_as_pdf_outlined;
  }
  if (mimeType.contains('zip') ||
      mimeType.contains('compressed') ||
      mimeType.contains('tar')) {
    return Icons.folder_zip_outlined;
  }
  if (mimeType.startsWith('text/')) {
    return Icons.description_outlined;
  }
  return Icons.insert_drive_file_outlined;
}

/// A sent file: its type, name and size, opening it on tap. Videos get a
/// play button and open in the player.
class FileMessageContent extends ConsumerStatefulWidget {
  const FileMessageContent({
    required this.attachment,
    required this.textColor,
    this.card = false,
    super.key,
  });

  final FileAttachment attachment;
  final Color textColor;

  /// On its own rounded card (circle channels, the media page) rather
  /// than inside a bubble.
  final bool card;

  @override
  ConsumerState<FileMessageContent> createState() => _FileMessageContentState();
}

class _FileMessageContentState extends ConsumerState<FileMessageContent> {
  var _opening = false;

  Future<void> _open() async {
    if (_opening) {
      return;
    }
    setState(() => _opening = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final url = await ref
          .read(chatsRepositoryProvider)
          .createFileUrl(widget.attachment);
      if (!mounted) {
        return;
      }
      if (widget.attachment.isVideo) {
        await Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (context) => VideoPlayerScreen(
              url: Uri.parse(url),
              title: widget.attachment.name,
            ),
          ),
        );
      } else {
        await ref.read(fileOpenerProvider)(Uri.parse(url));
      }
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not open the file. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    final c = context.tokens.colors;
    final foreground = widget.card ? c.ink : widget.textColor;
    final muted = foreground.withValues(alpha: 0.65);
    final tileFill = widget.card ? c.raised : foreground.withValues(alpha: 0.1);
    final details = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: ShapeDecoration(
            color: tileFill,
            shape: RoundedSuperellipseBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.md),
            ),
          ),
          child: Icon(
            fileIconFor(attachment.mimeType),
            color: foreground,
            size: 21,
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                attachment.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.3,
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                formatFileSize(attachment.size),
                style: TextStyle(fontSize: 12, height: 1.3, color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        if (_opening)
          SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: muted),
          )
        else
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: tileFill, shape: BoxShape.circle),
            child: Icon(
              attachment.isVideo
                  ? Icons.play_arrow_rounded
                  : Icons.download_rounded,
              size: 18,
              color: foreground,
            ),
          ),
      ],
    );

    final body = attachment.isVideo
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF17171A),
                    borderRadius: BorderRadius.circular(WeCordRadii.md),
                  ),
                  child: Center(
                    child: Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.play_arrow_rounded,
                        size: 30,
                        color: Color(0xFF17171A),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              details,
            ],
          )
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: details,
          );

    return WeCordPressable(
      key: ValueKey('file-message-${attachment.path}'),
      onPressed: _open,
      pressedScale: 0.98,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        if (!widget.card) {
          return body;
        }
        final hovered = states.contains(WidgetState.hovered);
        return AnimatedContainer(
          duration: WeCordMotion.quick,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: hovered ? c.raised : c.well,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
            border: Border.all(color: c.lineSoft),
          ),
          child: body,
        );
      },
    );
  }
}

/// Plays a video full screen with play / pause and seeking.
class VideoPlayerScreen extends StatefulWidget {
  const VideoPlayerScreen({required this.url, required this.title, super.key});

  final Uri url;
  final String title;

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final VideoPlayerController _controller =
      VideoPlayerController.networkUrl(widget.url);
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    unawaited(
      _controller
          .initialize()
          .then((_) {
            if (mounted) {
              setState(() {});
              unawaited(_controller.play());
            }
          })
          .catchError((Object error) {
            if (mounted) {
              setState(() => _error = error);
            }
          }),
    );
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = _controller.value;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: SafeArea(
        child: _error != null
            ? Center(
                child: Text(
                  tr("This video can't be played here."),
                  style: const TextStyle(color: Colors.white70),
                ),
              )
            : !value.isInitialized
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: value.aspectRatio,
                        child: GestureDetector(
                          onTap: _togglePlay,
                          child: VideoPlayer(_controller),
                        ),
                      ),
                    ),
                  ),
                  VideoProgressIndicator(
                    _controller,
                    allowScrubbing: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
                    child: Row(
                      children: [
                        IconButton(
                          key: const ValueKey('video-play-pause'),
                          tooltip: value.isPlaying ? tr('Pause') : tr('Play'),
                          color: Colors.white,
                          onPressed: _togglePlay,
                          icon: Icon(
                            value.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                        ),
                        Text(
                          '${_format(value.position)} / ${_format(value.duration)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  void _togglePlay() {
    final value = _controller.value;
    if (value.isPlaying) {
      unawaited(_controller.pause());
    } else {
      if (value.position >= value.duration && value.duration > Duration.zero) {
        unawaited(_controller.seekTo(Duration.zero));
      }
      unawaited(_controller.play());
    }
  }

  static String _format(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/message.dart';

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
    super.key,
  });

  final FileAttachment attachment;
  final Color textColor;

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
        const SnackBar(content: Text('Could not open the file. Try again.')),
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
    final theme = Theme.of(context);
    final muted = widget.textColor.withValues(alpha: 0.75);
    final details = Row(
      children: [
        Icon(
          fileIconFor(attachment.mimeType),
          color: widget.textColor,
          size: 32,
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
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: widget.textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatFileSize(attachment.size),
                style: theme.textTheme.labelSmall?.copyWith(color: muted),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        if (_opening)
          const SizedBox.square(
            dimension: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        else
          Icon(
            attachment.isVideo ? Icons.play_circle_outline : Icons.download,
            color: widget.textColor,
          ),
      ],
    );

    return InkWell(
      key: ValueKey('file-message-${attachment.path}'),
      borderRadius: BorderRadius.circular(6),
      onTap: _open,
      child: attachment.isVideo
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        size: 48,
                        color: Colors.white70,
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
            ),
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
            ? const Center(
                child: Text(
                  "This video can't be played here.",
                  style: TextStyle(color: Colors.white70),
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
                          tooltip: value.isPlaying ? 'Pause' : 'Play',
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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/file_preview/viewers/video_preview.dart'
    show videoControllerFactoryProvider;
import 'package:wecord/features/screen_capture/screen_capture_service.dart';
import 'package:wecord/features/screen_capture/view_once_screenshots.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The file of a view-once photo or video, signed for a minute.
class ViewOnceFile {
  const ViewOnceFile({required this.url, required this.isVideo});

  final String url;
  final bool isVideo;
}

/// Someone opened a view-once message.
class ViewOnceOpen {
  const ViewOnceOpen({required this.userId, required this.openedAt});

  final String userId;
  final DateTime openedAt;
}

/// This person already opened it (once is once).
class ViewOnceAlreadyOpened implements Exception {
  const ViewOnceAlreadyOpened();
}

/// Deleted, expired, or not for this person.
class ViewOnceUnavailable implements Exception {
  const ViewOnceUnavailable();
}

abstract interface class ViewOnceRepository {
  /// Records that the current user opened [messageId] and returns its
  /// file; throws [ViewOnceAlreadyOpened] the second time.
  Future<ViewOnceFile> open(String messageId);

  /// Who opened [messageId]: everyone for its sender, only themselves for
  /// anyone else. Follows changes.
  Stream<List<ViewOnceOpen>> watchOpens(String messageId);
}

class SupabaseViewOnceRepository implements ViewOnceRepository {
  const SupabaseViewOnceRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<ViewOnceFile> open(String messageId) async {
    final Object? result;
    try {
      result = await _client.rpc<Object?>(
        'open_view_once',
        params: {'target_message_id': messageId},
      );
    } on PostgrestException catch (error) {
      if (error.message.contains('view_once_already_opened')) {
        throw const ViewOnceAlreadyOpened();
      }
      if (error.message.startsWith('view_once_')) {
        throw const ViewOnceUnavailable();
      }
      rethrow;
    }
    final file = result as Map<String, dynamic>;
    final bucket = file['bucket'] as String;
    final path = file['path'] as String;
    // The open is recorded; signing is tried again briefly so a hiccup
    // does not spend the only look.
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final url = await _client.storage
            .from(bucket)
            .createSignedUrl(path, 60);
        return ViewOnceFile(url: url, isVideo: file['kind'] == 'video');
      } catch (error) {
        lastError = error;
        await Future<void>.delayed(const Duration(milliseconds: 300));
      }
    }
    throw lastError!;
  }

  @override
  Stream<List<ViewOnceOpen>> watchOpens(String messageId) {
    return _client
        .from('message_view_once_opens')
        .stream(primaryKey: ['message_id', 'user_id'])
        .eq('message_id', messageId)
        .map(
          (rows) => [
            for (final row in rows)
              ViewOnceOpen(
                userId: row['user_id'] as String,
                openedAt: DateTime.parse(row['opened_at'] as String).toUtc(),
              ),
          ],
        );
  }
}

class _UninitializedViewOnceRepository implements ViewOnceRepository {
  const _UninitializedViewOnceRepository();

  @override
  Future<ViewOnceFile> open(String messageId) {
    throw const ViewOnceUnavailable();
  }

  @override
  Stream<List<ViewOnceOpen>> watchOpens(String messageId) =>
      Stream.value(const <ViewOnceOpen>[]);
}

final viewOnceRepositoryProvider = Provider<ViewOnceRepository>((ref) {
  try {
    return SupabaseViewOnceRepository(ref.watch(supabaseClientProvider));
  } on ProviderException {
    return const _UninitializedViewOnceRepository();
  }
});

/// The opens of a view-once message; empty when they cannot be read.
final viewOnceOpensProvider = StreamProvider.autoDispose
    .family<List<ViewOnceOpen>, String>((ref, messageId) {
      return ref
          .watch(viewOnceRepositoryProvider)
          .watchOpens(messageId)
          .handleError((Object _) {});
    });

/// A view-once photo or video inside its message bubble: what it is, and
/// whether it has been opened. The recipient taps to open it (once, after a
/// reminder that screenshots can't be blocked); the sender sees "Opened" or
/// "Not opened". Nothing of the picture shows before it is opened.
class ViewOnceMessageContent extends ConsumerStatefulWidget {
  const ViewOnceMessageContent({
    required this.message,
    required this.textColor,
    super.key,
  });

  final ChatMessage message;
  final Color textColor;

  @override
  ConsumerState<ViewOnceMessageContent> createState() =>
      _ViewOnceMessageContentState();
}

class _ViewOnceMessageContentState
    extends ConsumerState<ViewOnceMessageContent> {
  var _opening = false;
  var _openedHere = false;

  bool get _isVideo => widget.message.type == MessageType.file;

  Future<void> _open() async {
    if (_opening) {
      return;
    }
    // A screen that is being recorded would keep the only look: wait until
    // the recording stops (iPhone and iPad can tell; other devices cannot).
    final capture = ref.read(screenCaptureServiceProvider);
    if (await capture.isRecording()) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              tr(
                'Stop recording your screen, then open it. It can only be opened once.',
              ),
            ),
          ),
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(
          _isVideo ? tr('Open this video once?') : tr('Open this photo once?'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr(
                'Once you close it, it is gone and you can\'t open it again. WeCord can\'t stop screenshots or screen recordings, so the sender is trusting you with it.',
              ),
            ),
            const SizedBox(height: 10),
            Text(
              capture.detects
                  ? tr(
                      'If this device notices a screenshot or a screen recording, the sender is told.',
                    )
                  : tr(
                      'This device can\'t notice screenshots, so the sender is not told about them.',
                    ),
              key: const ValueKey('view-once-capture-note'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            key: const ValueKey('view-once-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Open')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _opening = true);
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final file = await ref
          .read(viewOnceRepositoryProvider)
          .open(widget.message.id);
      if (!mounted) {
        return;
      }
      setState(() => _openedHere = true);
      await Navigator.of(context, rootNavigator: true).push<void>(
        PageRouteBuilder<void>(
          opaque: true,
          fullscreenDialog: true,
          pageBuilder: (context, _, _) =>
              ViewOnceViewer(file: file, messageId: widget.message.id),
          transitionsBuilder: (context, animation, _, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    } on ViewOnceAlreadyOpened {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('You already opened this one.'))),
      );
    } on ViewOnceUnavailable {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('This can\'t be opened any more.'))),
      );
    } catch (_) {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not open it. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final message = widget.message;
    final me = ref.watch(authRepositoryProvider).currentUser?.id;
    final mine = message.isSentBy(me);
    final pending = isPendingMessageId(message.id);
    final opens = pending
        ? const <ViewOnceOpen>[]
        : ref.watch(viewOnceOpensProvider(message.id)).value ??
              const <ViewOnceOpen>[];
    final openedByMe = _openedHere || opens.any((open) => open.userId == me);
    // Only the sender reads the others' reports (the database says so too).
    final captureNote = mine && !pending
        ? viewOnceCaptureNote(
            ref.watch(viewOnceCaptureReportsProvider(message.id)).value ??
                const <ViewOnceCaptureReport>[],
          )
        : null;
    final kind = _isVideo ? tr('Video') : tr('Photo');

    final String status;
    final bool dim;
    if (mine) {
      dim = false;
      status = pending
          ? tr('Sending…')
          : opens.isEmpty
          ? tr('Not opened')
          : opens.length == 1
          ? tr('Opened')
          : tr('Opened by {count}', {'count': opens.length});
    } else if (openedByMe) {
      dim = true;
      status = tr('Opened');
    } else {
      dim = false;
      status = tr('Tap to open · View once');
    }
    final statusLine = captureNote == null ? status : '$status · $captureNote';
    final canOpen = !mine && !openedByMe && !pending && !_opening;
    final muted = widget.textColor.withValues(alpha: 0.72);
    final label = tr('{kind}, view once, {status}', {
      'kind': kind,
      'status': statusLine,
    });

    final tile = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _OnceBadge(
            color: dim ? muted : (canOpen ? c.accent : widget.textColor),
            busy: _opening,
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  kind,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: dim ? muted : widget.textColor,
                  ),
                ),
                Text(
                  statusLine,
                  key: ValueKey('view-once-status-${message.id}'),
                  style: TextStyle(fontSize: 12.5, color: muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Semantics(
      container: true,
      label: label,
      button: canOpen,
      excludeSemantics: true,
      onTap: canOpen ? _open : null,
      child: canOpen
          ? WeCordPressable(
              key: ValueKey('view-once-${message.id}'),
              onPressed: _open,
              pressedScale: 0.98,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              builder: (context, states) => tile,
            )
          : KeyedSubtree(key: ValueKey('view-once-${message.id}'), child: tile),
    );
  }
}

/// A dashed ring around a "1": the mark of view-once media.
class _OnceBadge extends StatelessWidget {
  const _OnceBadge({required this.color, required this.busy});

  final Color color;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: 36,
      child: busy
          ? Padding(
              padding: const EdgeInsets.all(7),
              child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
            )
          : CustomPaint(
              painter: _DashedRingPainter(color),
              child: Center(
                child: Text(
                  '1',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ),
            ),
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  const _DashedRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final rect = Offset.zero & size;
    final inner = rect.deflate(1.5);
    const dashes = 12;
    const sweep = 3.14159265 * 2 / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(inner, i * sweep, sweep * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// The full-screen look at a view-once photo or video: black, no save, no
/// share, no forward. Closing it ends the look.
///
/// On an iPhone or iPad it also notices a screenshot or a screen recording
/// (best effort, after the fact): it tells the sender through [messageId], and
/// while the screen is recorded it hides the picture. Other devices cannot
/// notice, and the viewer says so.
class ViewOnceViewer extends ConsumerStatefulWidget {
  const ViewOnceViewer({required this.file, this.messageId, super.key});

  final ViewOnceFile file;

  /// The message being looked at; null reports nothing.
  final String? messageId;

  @override
  ConsumerState<ViewOnceViewer> createState() => _ViewOnceViewerState();
}

class _ViewOnceViewerState extends ConsumerState<ViewOnceViewer> {
  VideoPlayerController? _video;
  var _videoReady = false;
  var _videoFailed = false;

  StreamSubscription<ScreenCaptureEvent>? _captureEvents;

  /// The screen is being recorded: the picture is hidden until it stops.
  var _covered = false;

  /// Shown at the top after a screenshot or recording was noticed.
  String? _captureNotice;

  @override
  void initState() {
    super.initState();
    if (widget.file.isVideo) {
      unawaited(_startVideo());
    }
    final capture = ref.read(screenCaptureServiceProvider);
    if (capture.detects) {
      _captureEvents = capture.events.listen(_onCapture);
      unawaited(
        capture.isRecording().then((recording) {
          if (recording && mounted) {
            _onCapture(ScreenCaptureEvent.recordingStarted);
          }
        }),
      );
    }
  }

  void _onCapture(ScreenCaptureEvent event) {
    switch (event) {
      case ScreenCaptureEvent.screenshot:
        _report(ViewOnceCaptureKind.screenshot);
        setState(
          () => _captureNotice = tr('Screenshot noticed. The sender is told.'),
        );
      case ScreenCaptureEvent.recordingStarted:
        _report(ViewOnceCaptureKind.recording);
        unawaited(_video?.pause());
        setState(() {
          _covered = true;
          _captureNotice = tr('Screen recording noticed. The sender is told.');
        });
      case ScreenCaptureEvent.recordingStopped:
        setState(() => _covered = false);
    }
  }

  /// Best effort: a report that cannot be sent is not worth interrupting a
  /// look for.
  void _report(ViewOnceCaptureKind kind) {
    final id = widget.messageId;
    if (id == null) {
      return;
    }
    unawaited(
      ref
          .read(viewOnceScreenshotRepositoryProvider)
          .report(id, kind)
          .then((_) {}, onError: (Object _) {}),
    );
  }

  Future<void> _startVideo() async {
    final controller = ref.read(videoControllerFactoryProvider)(
      url: Uri.parse(widget.file.url),
    );
    _video = controller;
    try {
      await controller.initialize();
      await controller.setLooping(false);
      await controller.play();
      if (mounted) {
        setState(() => _videoReady = true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _videoFailed = true);
      }
    }
  }

  @override
  void dispose() {
    unawaited(_captureEvents?.cancel());
    unawaited(_video?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = _video;
    final Widget media;
    if (widget.file.isVideo) {
      media = _videoFailed
          ? _ViewerNote(text: tr('Could not play this video.'))
          : !_videoReady || video == null
          ? const Center(child: CircularProgressIndicator(color: Colors.white))
          : GestureDetector(
              onTap: () => video.value.isPlaying ? video.pause() : video.play(),
              child: Center(
                child: AspectRatio(
                  aspectRatio: video.value.aspectRatio,
                  child: VideoPlayer(video),
                ),
              ),
            );
    } else {
      media = InteractiveViewer(
        maxScale: 5,
        child: Center(
          child: Image.network(
            widget.file.url,
            fit: BoxFit.contain,
            semanticLabel: tr('View-once photo'),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
            errorBuilder: (context, error, stackTrace) =>
                _ViewerNote(text: tr('Could not load this photo.')),
          ),
        ),
      );
    }
    final detects = ref.watch(screenCaptureDetectsProvider);
    return Scaffold(
      key: const ValueKey('view-once-viewer'),
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_covered)
            _ViewerNote(
              key: const ValueKey('view-once-covered'),
              text: tr('Hidden while your screen is being recorded.'),
            )
          else
            media,
          SafeArea(
            child: Align(
              alignment: Alignment.topCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        WeCordIconButton(
                          key: const ValueKey('view-once-close'),
                          icon: Icons.close_rounded,
                          tooltip: tr('Close'),
                          variant: WeCordButtonVariant.ghost,
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            tr('View once · gone when you close it'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_captureNotice != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: Container(
                          key: const ValueKey('view-once-capture-notice'),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(WeCordRadii.md),
                          ),
                          child: Text(
                            _captureNotice!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                child: Text(
                  detects
                      ? tr(
                          'Screenshots and screen recordings can\'t be blocked. This device tells the sender if it notices one.',
                        )
                      : tr(
                          'Screenshots and screen recordings can\'t be blocked, and this device can\'t notice them.',
                        ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewerNote extends StatelessWidget {
  const _ViewerNote({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: Colors.white70)),
    );
  }
}

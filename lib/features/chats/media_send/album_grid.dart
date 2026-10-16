import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/file_message.dart';
import 'package:wecord/features/chats/media_cache.dart';
import 'package:wecord/features/chats/media_send/album_layout.dart';
import 'package:wecord/features/chats/media_send/blurhash.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/features/chats/offline/outbox_provider.dart';
import 'package:wecord/features/file_preview/file_preview_scope.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How a signed picture URL becomes an image to draw. The network in the
/// app; tests and screenshot tools swap in pictures from memory.
final chatImageProviderFactoryProvider =
    Provider<ImageProvider Function(String url)>((ref) => NetworkImage.new);

/// The pictures and videos of a message, or of the messages of an album,
/// as one grid in the bubble (1 to 10 tiles, see [AlbumLayout]); files that
/// are not pictures or videos stack under it as cards, and the caption (the
/// text of the first message) goes below.
///
/// Each tile shows its BlurHash at once in the right proportions, fades the
/// picture in, and while the message is still being sent draws the kept
/// file with a progress ring and a cancel button (or a retry button once it
/// failed).
class MessageMediaGroup extends StatelessWidget {
  const MessageMediaGroup({
    required this.messages,
    required this.textColor,
    this.desktop = false,
    this.framed = false,
    super.key,
  });

  /// The album's messages in order (one message for a single picture).
  final List<ChatMessage> messages;
  final Color textColor;
  final bool desktop;

  /// On its own (channel cards) rather than inside a bubble.
  final bool framed;

  /// Whether [message] is drawn as a tile of the grid (a picture or a
  /// video) rather than a card.
  static bool isTile(ChatMessage message) {
    if (message.recalledAt != null) {
      return false;
    }
    if (message.type == MessageType.image) {
      return _image(message) != null;
    }
    return message.fileAttachment?.isVideo == true;
  }

  static ImageAttachment? _image(ChatMessage message) {
    try {
      return message.imageAttachment;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tiles = [
      for (final message in messages)
        if (isTile(message)) message,
    ];
    final files = [
      for (final message in messages)
        if (!isTile(message) && message.fileAttachment != null) message,
    ];
    final caption = messages
        .map((message) => message.body)
        .firstWhere((body) => body.trim().isNotEmpty, orElse: () => '');
    final c = context.tokens.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        final limit = framed
            ? 420.0
            : desktop
            ? 340.0
            : 256.0;
        final width = math.min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : limit,
          limit,
        );
        final layout = AlbumLayout.compute(
          aspects: [for (final message in tiles) _aspectOf(message)],
          width: width,
        );
        return Padding(
          padding: EdgeInsets.only(top: framed ? 6 : 0),
          child: SizedBox(
            width: width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (tiles.isNotEmpty)
                  SizedBox(
                    key: ValueKey('album-grid-${tiles.first.id}'),
                    width: layout.size.width,
                    height: layout.size.height,
                    child: Stack(
                      children: [
                        for (final (index, message) in tiles.indexed)
                          Positioned.fromRect(
                            rect: layout.tiles[index],
                            child: ClipRRect(
                              borderRadius: _cornersOf(
                                layout.tiles[index],
                                layout.size,
                                framed: framed,
                              ),
                              child: MediaTile(
                                key: ValueKey('album-tile-${message.id}'),
                                message: message,
                                framed: framed,
                                compact: layout.tiles[index].shortestSide < 110,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                for (final message in files)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: FileMessageContent(
                      attachment: message.fileAttachment!,
                      textColor: textColor,
                      card: framed,
                      messageId: message.id,
                      conversationId: message.conversationId,
                      sentAt: message.createdAt,
                    ),
                  ),
                if (caption.trim().isNotEmpty)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      framed ? 0 : 10,
                      7,
                      framed ? 0 : 10,
                      framed ? 0 : 5,
                    ),
                    child: MessageMarkdownText(
                      body: caption,
                      mentions: messages.first.mentions,
                      color: framed ? c.ink : textColor,
                      enlargeEmojiOnly: false,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  static double? _aspectOf(ChatMessage message) {
    int? width;
    int? height;
    if (message.type == MessageType.image) {
      final image = _image(message);
      width = image?.width;
      height = image?.height;
    } else {
      final file = message.fileAttachment;
      width = file?.width;
      height = file?.height;
    }
    if (width == null || height == null || width <= 0 || height <= 0) {
      // Videos without a known shape are taken as landscape.
      return message.type == MessageType.file ? 16 / 9 : null;
    }
    return width / height;
  }

  /// Round the corners on the grid's edge, nearly square the ones inside.
  static BorderRadius _cornersOf(Rect tile, Size grid, {required bool framed}) {
    final big = Radius.circular(WeCordRadii.lg - (framed ? 0 : 0));
    const small = Radius.circular(4);
    bool left() => tile.left < 0.5;
    bool right() => (tile.right - grid.width).abs() < 0.5;
    bool top() => tile.top < 0.5;
    bool bottom() => (tile.bottom - grid.height).abs() < 0.5;
    return BorderRadius.only(
      topLeft: left() && top() ? big : small,
      topRight: right() && top() ? big : small,
      bottomLeft: left() && bottom() ? big : small,
      bottomRight: right() && bottom() ? big : small,
    );
  }
}

/// One picture or video of a [MessageMediaGroup].
class MediaTile extends ConsumerStatefulWidget {
  const MediaTile({
    required this.message,
    this.framed = false,
    this.compact = false,
    super.key,
  });

  final ChatMessage message;
  final bool framed;

  /// A small tile: smaller buttons.
  final bool compact;

  @override
  ConsumerState<MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends ConsumerState<MediaTile> {
  Future<String>? _imageUrl;
  Future<Uint8List?>? _poster;
  Future<Uint8List?>? _localPreview;

  /// Whether the URL was signed again after the image failed to load.
  bool _resigned = false;

  ChatMessage get _message => widget.message;

  bool get _isPending => isPendingMessageId(_message.id);

  ImageAttachment? get _image => _message.type == MessageType.image
      ? MessageMediaGroup._image(_message)
      : null;

  FileAttachment? get _video =>
      _message.type == MessageType.file ? _message.fileAttachment : null;

  String? get _urlKey {
    final image = _image;
    return image == null
        ? null
        : SignedUrlCache.keyFor(image.bucket, image.path);
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant MediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message.id != widget.message.id ||
        oldWidget.message.attachment?['path'] !=
            widget.message.attachment?['path']) {
      _resigned = false;
      _load();
    }
  }

  void _load() {
    _imageUrl = null;
    _poster = null;
    _localPreview = null;
    if (_isPending) {
      final clientId = _message.clientId;
      if (clientId != null) {
        _localPreview = ref
            .read(pendingMediaStoreProvider)
            .readPreview(clientId)
            .catchError((Object _) => null);
      }
      return;
    }
    final image = _image;
    if (image != null) {
      _imageUrl = _loadImageUrl(image);
    } else if (_video case final video?) {
      _poster = ref
          .read(thumbnailServiceProvider)
          .thumbnailFor(
            PreviewFile.fromFileAttachment(
              video,
              messageId: _message.id,
              conversationId: _message.conversationId,
            ),
          )
          .catchError((Object _) => null);
    }
  }

  /// Reused while valid, so scrolling back to an image does not sign and
  /// load it again.
  Future<String> _loadImageUrl(ImageAttachment image) {
    return ref
        .read(chatSignedUrlCacheProvider)
        .get(
          SignedUrlCache.keyFor(image.bucket, image.path),
          () => ref.read(chatsRepositoryProvider).createImageUrl(image),
        );
  }

  /// The signed URL may have expired while the chat stayed open: sign it
  /// again, once.
  void _resignAfterError() {
    final image = _image;
    if (_resigned || image == null) {
      return;
    }
    _resigned = true;
    scheduleMicrotask(() {
      if (mounted) {
        ref.read(chatSignedUrlCacheProvider).evict(_urlKey!);
        setState(() {
          _imageUrl = _loadImageUrl(image);
        });
      }
    });
  }

  void _open() {
    final image = _image;
    final video = _video;
    final file = image != null
        ? PreviewFile.fromImageAttachment(
            image,
            messageId: _message.id,
            conversationId: _message.conversationId,
            sentAt: _message.createdAt,
          )
        : video == null
        ? null
        : PreviewFile.fromFileAttachment(
            video,
            messageId: _message.id,
            conversationId: _message.conversationId,
            sentAt: _message.createdAt,
          );
    if (file != null) {
      unawaited(openFilePreviewInScope(context, file));
    }
  }

  Widget _fadeIn(Widget child, bool loaded) {
    return AnimatedOpacity(
      opacity: loaded ? 1 : 0,
      duration: WeCordMotion.durationOf(
        context,
        const Duration(milliseconds: 220),
      ),
      curve: Curves.easeOut,
      child: child,
    );
  }

  Widget _picture(Color well) {
    final hash = _image?.blurhash ?? _video?.blurhash;
    final blur = BlurHashView(hash: hash, fallback: well);

    Widget layered(Widget? picture) =>
        Stack(fit: StackFit.expand, children: [blur, ?picture]);

    if (_isPending) {
      return FutureBuilder<Uint8List?>(
        future: _localPreview,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          return layered(
            bytes == null
                ? null
                : Image.memory(
                    bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
          );
        },
      );
    }

    final image = _image;
    if (image != null) {
      return FutureBuilder<String>(
        future: _imageUrl,
        initialData: _resigned || _urlKey == null
            ? null
            : ref.read(chatSignedUrlCacheProvider).peek(_urlKey!),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url == null) {
            return layered(null);
          }
          return layered(
            Image(
              image: ref.read(chatImageProviderFactoryProvider)(url),
              fit: BoxFit.cover,
              gaplessPlayback: true,
              frameBuilder: (context, child, frame, synchronous) =>
                  _fadeIn(child, synchronous || frame != null),
              errorBuilder: (context, error, stackTrace) {
                _resignAfterError();
                return Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: context.tokens.colors.faint,
                    size: 28,
                  ),
                );
              },
            ),
          );
        },
      );
    }

    return FutureBuilder<Uint8List?>(
      future: _poster,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return layered(
          bytes == null
              ? null
              : Image.memory(
                  bytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  frameBuilder: (context, child, frame, synchronous) =>
                      _fadeIn(child, synchronous || frame != null),
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final video = _video;
    final isPending = _isPending;
    final entry = isPending && _message.clientId != null
        ? ref.watch(outboxEntryProvider(_message.clientId!))
        : null;
    final failed = entry?.state == OutboxState.failed;

    final tile = Stack(
      fit: StackFit.expand,
      children: [
        _picture(widget.framed ? c.raised : c.well),
        if (video != null && !isPending)
          Center(child: _PlayBadge(compact: widget.compact)),
        if (video != null && !isPending)
          Positioned(
            left: 6,
            bottom: 6,
            child: _Chip(text: formatFileSize(video.size)),
          ),
        if (isPending && entry != null)
          _PendingOverlay(
            entry: entry,
            failed: failed,
            compact: widget.compact,
            isVideo: video != null,
          ),
      ],
    );
    final label = video != null ? tr('Video') : tr('Image');
    if (isPending) {
      return Semantics(label: label, child: tile);
    }
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        border: widget.framed ? Border.all(color: c.lineSoft) : null,
      ),
      child: WeCordPressable(
        onPressed: _open,
        pressedScale: 1,
        semanticLabel: label,
        builder: (context, states) => tile,
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = WeCordPalette.dark;
    final size = compact ? 30.0 : 44.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: dark.paper.withValues(alpha: 0.62),
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.play_arrow_rounded, size: size * 0.68, color: dark.ink),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final dark = WeCordPalette.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: dark.paper.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: dark.ink,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          height: 1.1,
        ),
      ),
    );
  }
}

/// The scrim, ring and button over a tile that is still being sent.
class _PendingOverlay extends ConsumerWidget {
  const _PendingOverlay({
    required this.entry,
    required this.failed,
    required this.compact,
    required this.isVideo,
  });

  final OutboxEntry entry;
  final bool failed;
  final bool compact;
  final bool isVideo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = WeCordPalette.dark;
    final c = context.tokens.colors;
    final size = compact ? 34.0 : 46.0;
    final outbox = ref.read(outboxProvider.notifier);
    final progress = ref
        .watch(uploadProgressTrackerProvider)
        .of(entry.clientId);

    Widget button({
      required Widget child,
      required VoidCallback onPressed,
      required String label,
      Color? fill,
    }) {
      return WeCordPressable(
        key: ValueKey('album-pending-${entry.clientId}'),
        onPressed: onPressed,
        tooltip: label,
        semanticLabel: label,
        shape: const CircleBorder(),
        pressedScale: 0.92,
        builder: (context, states) => Container(
          width: failed ? size : size * 0.74,
          height: failed ? size : size * 0.74,
          decoration: BoxDecoration(
            color: fill ?? dark.paper.withValues(alpha: 0.62),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: child,
        ),
      );
    }

    return ColoredBox(
      color: (failed ? c.danger : dark.paper).withValues(
        alpha: failed ? 0.32 : 0.26,
      ),
      child: Center(
        child: failed
            ? button(
                label: tr('Retry upload'),
                fill: c.danger,
                onPressed: () => unawaited(outbox.retryMedia(entry)),
                child: Icon(
                  Icons.refresh_rounded,
                  color: dark.ink,
                  size: size * 0.55,
                ),
              )
            : ValueListenableBuilder<UploadProgress>(
                valueListenable: progress,
                builder: (context, upload, _) => Stack(
                  alignment: Alignment.center,
                  children: [
                    button(
                      label: tr('Cancel upload'),
                      onPressed: () => outbox.cancelMedia(entry.clientId),
                      child: Icon(
                        Icons.close_rounded,
                        color: dark.ink,
                        size: size * 0.38,
                      ),
                    ),
                    IgnorePointer(
                      child: SizedBox.square(
                        dimension: size,
                        child: CircularProgressIndicator(
                          key: ValueKey('album-progress-${entry.clientId}'),
                          // A running upload that cannot tell how far it
                          // is spins; one still waiting its turn shows an
                          // empty ring.
                          value: upload.running ? upload.value : 0,
                          strokeWidth: 2.5,
                          color: dark.ink,
                          backgroundColor: dark.ink.withValues(alpha: 0.28),
                          strokeCap: StrokeCap.round,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

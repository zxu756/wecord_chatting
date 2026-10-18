import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/file_message.dart';
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/file_preview_service.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/file_preview/thumbnails.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

final chatMediaProvider = FutureProvider.autoDispose
    .family<List<ConversationMediaItem>, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .listConversationMedia(conversationId);
    });

enum _MediaTab { images, voice, files }

/// A conversation's media center: photos and videos in a grid, voice
/// messages, and files. Everything opens in the file viewer.
class ChatMediaScreen extends ConsumerStatefulWidget {
  const ChatMediaScreen({required this.conversationId, super.key});

  static String pathFor(String conversationId) =>
      '/chats/$conversationId/media';

  final String conversationId;

  @override
  ConsumerState<ChatMediaScreen> createState() => _ChatMediaScreenState();
}

class _ChatMediaScreenState extends ConsumerState<ChatMediaScreen> {
  var _tab = _MediaTab.images;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final media = ref.watch(chatMediaProvider(widget.conversationId));
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(title: tr('Media')),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: WeCordSegmented<_MediaTab>(
                    expand: true,
                    selected: _tab,
                    onChanged: (tab) => setState(() => _tab = tab),
                    segments: [
                      WeCordSegment(
                        value: _MediaTab.images,
                        label: tr('Images'),
                      ),
                      WeCordSegment(value: _MediaTab.voice, label: tr('Voice')),
                      WeCordSegment(value: _MediaTab.files, label: tr('Files')),
                    ],
                  ),
                ),
                Expanded(
                  child: media.when(
                    loading: () => Center(
                      child: CircularProgressIndicator(color: c.muted),
                    ),
                    error: (error, stackTrace) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          errorText(error),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: c.dangerText),
                        ),
                      ),
                    ),
                    data: (items) => switch (_tab) {
                      _MediaTab.images => _MediaGrid(
                        conversationId: widget.conversationId,
                        items: items,
                      ),
                      _MediaTab.voice => _MediaList(
                        items: _filter(items, MessageType.voice),
                        emptyText: tr('No voice messages yet'),
                      ),
                      _MediaTab.files => _MediaList(
                        items: [
                          for (final item in _filter(items, MessageType.file))
                            if (!(PreviewFile.fromMediaItem(
                                  item,
                                )?.kind.isGalleryMedia ??
                                false))
                              item,
                        ],
                        emptyText: tr('No files yet'),
                      ),
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Photos and videos (also videos sent as files), newest first.
class _MediaGrid extends StatelessWidget {
  const _MediaGrid({required this.conversationId, required this.items});

  final String conversationId;
  final List<ConversationMediaItem> items;

  @override
  Widget build(BuildContext context) {
    final files = [
      for (final item in items)
        if (PreviewFile.fromMediaItem(item) case final file?
            when file.kind.isGalleryMedia)
          file,
    ];
    if (files.isEmpty) {
      return _Empty(text: tr('No images yet'));
    }
    final oldestFirst = files.reversed.toList(growable: false);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 130).floor().clamp(3, 6);
        return GridView.builder(
          key: const ValueKey('media-grid'),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: files.length,
          itemBuilder: (context, index) => _MediaTile(
            file: files[index],
            onOpen: () => unawaited(
              openFilePreview(
                context,
                file: files[index],
                gallery: oldestFirst,
                conversationId: conversationId,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MediaTile extends ConsumerStatefulWidget {
  const _MediaTile({required this.file, required this.onOpen});

  final PreviewFile file;
  final VoidCallback onOpen;

  @override
  ConsumerState<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends ConsumerState<_MediaTile> {
  late Future<Object?> _picture = _load();

  @override
  void didUpdateWidget(covariant _MediaTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.key != widget.file.key) {
      _picture = _load();
    }
  }

  /// A signed link for images, rendered poster bytes for videos.
  Future<Object?> _load() async {
    try {
      if (widget.file.kind == PreviewKind.image) {
        return await ref.read(filePreviewServiceProvider).fileUrl(widget.file);
      }
      return await ref.read(thumbnailServiceProvider).thumbnailFor(widget.file);
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final radius = BorderRadius.circular(WeCordRadii.sm);
    final video = widget.file.kind == PreviewKind.video;
    return WeCordPressable(
      key: ValueKey('media-tile-${widget.file.path}'),
      onPressed: widget.onOpen,
      pressedScale: 0.96,
      semanticLabel: widget.file.name,
      shape: RoundedRectangleBorder(borderRadius: radius),
      builder: (context, states) => ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: video ? WeCordPalette.dark.paper : c.raised),
            FutureBuilder<Object?>(
              future: _picture,
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (data is Uri) {
                  return Image.network(
                    data.toString(),
                    fit: BoxFit.cover,
                    cacheWidth: 360,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.broken_image_outlined, color: c.faint),
                  );
                }
                if (data is Uint8List) {
                  return Image.memory(data, fit: BoxFit.cover);
                }
                return const SizedBox.shrink();
              },
            ),
            if (states.contains(WidgetState.hovered))
              ColoredBox(color: c.ink.withValues(alpha: 0.08)),
            if (video)
              Positioned(
                left: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: ShapeDecoration(
                    color: WeCordPalette.dark.ink.withValues(alpha: 0.9),
                    shape: const StadiumBorder(),
                  ),
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: 16,
                    color: WeCordPalette.dark.onInk,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: c.muted,
        ),
      ),
    );
  }
}

class _MediaList extends StatelessWidget {
  const _MediaList({required this.items, required this.emptyText});

  final List<ConversationMediaItem> items;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return _Empty(text: emptyText);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _MediaRow(item: items[index]),
    );
  }
}

class _MediaRow extends StatelessWidget {
  const _MediaRow({required this.item});

  final ConversationMediaItem item;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final caption = Text(
      '${item.senderName} · ${formatPreviewTime(item.createdAt)}',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: c.muted,
      ),
    );
    final file = item.type == MessageType.file
        ? FileAttachment.maybeFromJson(item.attachment)
        : null;
    final voice = item.voiceAttachment;
    final Widget content;
    if (file != null) {
      content = FileMessageContent(
        attachment: file,
        textColor: c.ink,
        card: true,
        messageId: item.messageId,
        conversationId: item.conversationId,
        senderName: item.senderName,
        sentAt: item.createdAt,
      );
    } else if (voice != null) {
      content = VoiceMessagePlayer(
        attachment: voice,
        card: true,
        messageId: item.messageId,
        conversationId: item.conversationId,
      );
    } else {
      content = Text(_titleFor(item), style: TextStyle(color: c.ink));
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
        boxShadow: context.tokens.shadows.hairline,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [content, const SizedBox(height: 8), caption],
      ),
    );
  }
}

List<ConversationMediaItem> _filter(
  List<ConversationMediaItem> items,
  MessageType type,
) {
  return items.where((item) => item.type == type).toList(growable: false);
}

String _titleFor(ConversationMediaItem item) {
  final body = item.body.trim();
  if (body.isNotEmpty) {
    return body;
  }
  return switch (item.type) {
    MessageType.image => tr('[Image]'),
    MessageType.voice => tr('[Voice]'),
    MessageType.file => tr('[File]'),
    MessageType.poll => pollPreviewText(item.body),
    MessageType.sticker => stickerPreviewText(item.body),
    MessageType.text || MessageType.system => item.body,
  };
}

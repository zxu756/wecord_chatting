import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/features/home/home_screen.dart';
import 'package:wecord/features/note_to_self/note_to_self.dart';
import 'package:wecord/features/share_target/share_target_gateway.dart';
import 'package:wecord/features/share_target/shared_content.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/navigation/paper_page_header.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Share to WeCord": where a link, text or files another app shared land
/// (Android and ChromeOS, through the installed web app's share target). It
/// shows what was shared and lists the chats to send it to, with the note to
/// self first (the usual place for something to look at later).
class ShareTargetScreen extends ConsumerStatefulWidget {
  const ShareTargetScreen({super.key});

  static const path = '/share';

  @override
  ConsumerState<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends ConsumerState<ShareTargetScreen> {
  var _query = '';
  String? _sendingTo;
  String? _error;

  Future<void> _send(SharedContent content, ConversationSummary target) async {
    setState(() {
      _sendingTo = target.id;
      _error = null;
    });
    final router = GoRouter.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final gateway = ref.read(shareTargetGatewayProvider);
    final title = target.isNoteToSelf
        ? noteToSelfTitle()
        : (target.title?.trim().isNotEmpty == true
              ? target.title!.trim()
              : tr('Conversation'));
    try {
      var id = target.id;
      if (id == noteToSelfPlaceholderId) {
        id = await ref.read(noteToSelfRepositoryProvider).ensure();
      }
      await sendSharedContent(ref.read(chatsRepositoryProvider), id, content);
      await gateway.clear();
      ref.invalidate(conversationsProvider);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text(tr('Sent to {name}', {'name': title}))),
      );
      router.go(
        '${ChatsScreen.path}/$id',
        extra: ChatThreadRouteExtra(
          title: title,
          type: target.type,
          avatarUrl: target.avatarUrl,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sendingTo = null;
        _error = error is SendRefusedException || error is SlowmodeException
            ? error.toString()
            : error is ChatFileTooLargeException
            ? tr('A file is too large to send.')
            : tr('Could not send. Try again.');
      });
    }
  }

  Future<void> _discard() async {
    await ref.read(shareTargetGatewayProvider).clear();
    if (mounted) {
      GoRouter.of(context).go(HomeScreen.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final pending = ref.watch(pendingShareProvider);
    final Widget body = pending.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _NothingToShare(onDone: _discard),
      data: (content) => content == null || content.isEmpty
          ? _NothingToShare(onDone: _discard)
          : _buildShare(context, content),
    );
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                PaperPageHeader(
                  title: tr('Share to WeCord'),
                  actions: [
                    if (pending.value case final content?
                        when !content.isEmpty && _sendingTo == null)
                      WeCordButton(
                        key: const ValueKey('share-discard'),
                        label: tr('Discard'),
                        variant: WeCordButtonVariant.ghost,
                        size: WeCordButtonSize.small,
                        onPressed: () => unawaited(_discard()),
                      ),
                  ],
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildShare(BuildContext context, SharedContent content) {
    final c = context.tokens.colors;
    final conversations = ref.watch(listedConversationsProvider);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 24 + bottom),
      children: [
        _SharePreview(content: content),
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Semantics(
            header: true,
            child: Text(
              tr('Send to'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.muted,
              ),
            ),
          ),
        ),
        Semantics(
          label: tr('Search chats'),
          textField: true,
          child: WeCordTextField(
            fieldKey: const ValueKey('share-search'),
            hint: tr('Search chats'),
            prefixIcon: Icons.search_rounded,
            onPaper: true,
            textInputAction: TextInputAction.search,
            onChanged: (value) => setState(() => _query = value),
          ),
        ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                error,
                key: const ValueKey('share-error'),
                style: TextStyle(fontSize: 13.5, color: c.dangerText),
              ),
            ),
          ),
        const SizedBox(height: 8),
        ...conversations.when(
          loading: () => const [SheetSpinner()],
          error: (error, stackTrace) => [
            SheetNote(text: errorText(error), error: true),
          ],
          data: (list) => _rows(context, content, list),
        ),
      ],
    );
  }

  List<Widget> _rows(
    BuildContext context,
    SharedContent content,
    List<ConversationSummary> all,
  ) {
    final query = _query.trim().toLowerCase();
    // Direct and group chats: not circle channels or threads, which have
    // their own rules about who may post.
    final chats = withNoteToSelfFirst([
      for (final chat in all)
        if (!chat.isThread && chat.circleId == null) chat,
    ]);
    final shown = [
      for (final chat in chats)
        if (query.isEmpty ||
            (chat.isNoteToSelf
                ? noteToSelfTitle().toLowerCase().contains(query)
                : (chat.title?.toLowerCase().contains(query) ?? false)))
          chat,
    ];
    if (shown.isEmpty) {
      return [SheetNote(text: tr('No matching conversations'))];
    }
    final busy = _sendingTo != null;
    return [
      for (final chat in shown)
        _ShareTargetRow(
          key: ValueKey('share-target-${chat.id}'),
          chat: chat,
          sending: _sendingTo == chat.id,
          enabled: !busy,
          onTap: () => unawaited(_send(content, chat)),
        ),
    ];
  }
}

class _ShareTargetRow extends StatelessWidget {
  const _ShareTargetRow({
    required this.chat,
    required this.sending,
    required this.enabled,
    required this.onTap,
    super.key,
  });

  final ConversationSummary chat;
  final bool sending;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final title = chat.isNoteToSelf
        ? noteToSelfTitle()
        : (chat.title?.trim().isNotEmpty == true
              ? chat.title!.trim()
              : tr('Conversation'));
    final group = chat.type != ConversationType.direct;
    return SheetListRow(
      enabled: enabled,
      leading: chat.isNoteToSelf
          ? const NoteToSelfAvatar(size: 40)
          : ResolvedAvatar(
              name: title,
              avatarUrl: chat.avatarUrl,
              size: 40,
              squircle: group,
            ),
      title: title,
      subtitle: chat.isNoteToSelf
          ? noteToSelfHint()
          : switch (chat.type) {
              ConversationType.group => tr('Group'),
              ConversationType.channel => tr('Channel'),
              _ => tr('Direct'),
            },
      trailing: sending
          ? SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                semanticsLabel: tr('Sending…'),
              ),
            )
          : Icon(Icons.send_rounded, size: 18, color: c.faint),
      onTap: onTap,
    );
  }
}

/// What is about to be sent: the text, then each file.
class _SharePreview extends StatelessWidget {
  const _SharePreview({required this.content});

  final SharedContent content;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final text = content.messageText;
    return Container(
      key: const ValueKey('share-preview'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text != null)
            Text(
              text,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 15.5, height: 1.4, color: c.ink),
            ),
          for (final (index, file) in content.files.indexed) ...[
            if (index > 0 || text != null) const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  file.isImage
                      ? Icons.image_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 22,
                  color: c.muted,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    file.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  formatFileSize(file.size),
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
              ],
            ),
          ],
          if (content.skippedFiles > 0) ...[
            const SizedBox(height: 10),
            Text(
              tr(
                'Some files were left out: up to 10 files of 50 MB each can be shared at once.',
              ),
              key: const ValueKey('share-skipped'),
              style: TextStyle(fontSize: 13, height: 1.35, color: c.muted),
            ),
          ],
        ],
      ),
    );
  }
}

class _NothingToShare extends StatelessWidget {
  const _NothingToShare({required this.onDone});

  final Future<void> Function() onDone;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.ios_share_rounded, size: 40, color: c.faint),
            const SizedBox(height: 14),
            Text(
              tr('Nothing to share'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              tr(
                "Use another app's Share button and choose WeCord to send a link, text or files here.",
              ),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14.5, height: 1.4, color: c.muted),
            ),
            const SizedBox(height: 18),
            WeCordButton(
              key: const ValueKey('share-done'),
              label: tr('Back to chats'),
              onPressed: () => unawaited(onDone()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Sends [content] to [conversationId]: the text as one message, then each
/// file (pictures as chat pictures, the rest as files).
Future<void> sendSharedContent(
  ChatsRepository repository,
  String conversationId,
  SharedContent content,
) async {
  final text = content.messageText;
  if (text != null) {
    await repository.sendTextMessage(
      conversationId: conversationId,
      body: text,
    );
  }
  for (final file in content.files) {
    final bytes = await file.read();
    final image = file.isImage ? await _decodeSize(bytes) : null;
    if (image != null) {
      await repository.sendImageMessage(
        conversationId: conversationId,
        image: ChatImageUpload(
          bytes: bytes,
          fileName: file.name,
          mimeType: file.mimeType.toLowerCase(),
          width: image.$1,
          height: image.$2,
        ),
      );
    } else {
      await repository.sendFileMessage(
        conversationId: conversationId,
        fileName: file.name,
        mimeType: file.mimeType.isEmpty
            ? 'application/octet-stream'
            : file.mimeType,
        bytes: bytes,
      );
    }
  }
}

/// A picture's width and height, or null when it cannot be decoded (it is
/// then sent as a file).
Future<(int, int)?> _decodeSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final size = (frame.image.width, frame.image.height);
    frame.image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

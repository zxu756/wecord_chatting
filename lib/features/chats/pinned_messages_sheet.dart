import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/message_author.dart';
import 'package:wecord/features/chats/message_markdown.dart';
import 'package:wecord/features/chats/sheet_rows.dart';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/features/profile/profile_avatar.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/circle_emoji.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/poll.dart';
import 'package:wecord/shared/models/pinned_message.dart';
import 'package:wecord/shared/ui/ui.dart';

final pinnedMessagesProvider = FutureProvider.autoDispose
    .family<List<PinnedMessage>, String>((ref, conversationId) {
      return ref
          .watch(chatsRepositoryProvider)
          .listPinnedMessages(conversationId);
    });

final canPinMessagesProvider = FutureProvider.autoDispose.family<bool, String>((
  ref,
  conversationId,
) {
  return ref.watch(chatsRepositoryProvider).canPinMessages(conversationId);
});

/// Lists a conversation's pinned messages. Tapping one pops the sheet with
/// that message's id so the thread can scroll to it.
class PinnedMessagesSheet extends ConsumerWidget {
  const PinnedMessagesSheet({
    required this.conversationId,
    required this.canManagePins,
    required this.onUnpin,
    super.key,
  });

  final String conversationId;
  final bool canManagePins;
  final Future<void> Function(String messageId) onUnpin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pinned = ref.watch(pinnedMessagesProvider(conversationId));

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.7,
        ),
        child: pinned.when(
          loading: () => const SheetSpinner(),
          error: (error, stackTrace) => SheetNote(
            text: tr('Could not load pinned messages.'),
            error: true,
          ),
          data: (items) {
            if (items.isEmpty) {
              return SheetNote(text: tr('No pinned messages yet'));
            }
            return ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _PinnedMessageTile(
                  item: item,
                  canManagePins: canManagePins,
                  onOpen: () {
                    Navigator.of(context).pop(item.message.id);
                  },
                  onUnpin: () => unawaited(onUnpin(item.message.id)),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _PinnedMessageTile extends StatelessWidget {
  const _PinnedMessageTile({
    required this.item,
    required this.canManagePins,
    required this.onOpen,
    required this.onUnpin,
  });

  final PinnedMessage item;
  final bool canManagePins;
  final VoidCallback onOpen;
  final VoidCallback onUnpin;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final pinnedByName = item.pinnedByName?.trim();
    // Webhook messages show the webhook, not its creator.
    final webhookName = item.message.webhookName;
    final authorName = webhookName ?? item.sender.displayLabel;
    return SheetListRow(
      key: ValueKey('pinned-message-${item.message.id}'),
      onTap: onOpen,
      leading: ProfileAvatar(
        name: authorName,
        avatarUrl: webhookName != null
            ? item.message.webhookAvatarUrl
            : item.sender.avatarUrl,
        size: 40,
      ),
      title: authorName,
      titleTrailing: webhookName != null ? const MessageBotTag() : null,
      subtitleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            pinnedMessagePreview(item.message),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, height: 1.35, color: c.ink),
          ),
          if (pinnedByName != null && pinnedByName.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                tr('Pinned by {name}', {'name': pinnedByName}),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: c.subtle,
                ),
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (PreviewFile.fromMessage(item.message, senderName: authorName)
              case final file?)
            WeCordIconButton(
              key: ValueKey('pinned-preview-${item.message.id}'),
              icon: Icons.visibility_outlined,
              tooltip: tr('Preview'),
              variant: WeCordButtonVariant.ghost,
              size: 36,
              onPressed: () => unawaited(
                openFilePreview(
                  context,
                  file: file,
                  gallery: [file],
                  conversationId: item.message.conversationId,
                ),
              ),
            ),
          if (canManagePins)
            WeCordIconButton(
              key: ValueKey('pinned-unpin-${item.message.id}'),
              icon: Icons.close_rounded,
              tooltip: tr('Unpin'),
              variant: WeCordButtonVariant.ghost,
              size: 36,
              onPressed: onUnpin,
            ),
        ],
      ),
    );
  }
}

String pinnedMessagePreview(ChatMessage message) {
  final body = message.body.trim();
  return switch (message.type) {
    MessageType.text =>
      body.isEmpty ? tr('Message') : plainTextFromMarkdown(body),
    MessageType.system => body.isEmpty ? tr('Message') : body,
    MessageType.image => tr('Image'),
    MessageType.file => message.fileAttachment?.name ?? tr('File'),
    MessageType.voice => tr('Voice message'),
    MessageType.poll => pollPreviewText(body),
    MessageType.sticker => stickerPreviewText(body),
  };
}

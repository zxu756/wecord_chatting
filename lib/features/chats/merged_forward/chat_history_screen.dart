import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/file_message.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/chats/merged_forward/chat_history_card.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_repository.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/voice_message_player.dart';
import 'package:wecord/features/contact_cards/contact_card_models.dart';
import 'package:wecord/features/contact_cards/contact_card_view.dart';
import 'package:wecord/features/file_preview/file_preview_scope.dart';
import 'package:wecord/features/file_preview/preview_file.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/layout/adaptive_layout.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/spoken.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the chat-history message [messageId] as a read-only page. A
/// history that came along inside another one passes its [bundle], which
/// is already at hand.
Future<void> openChatHistory(
  BuildContext context, {
  required String messageId,
  required String title,
  ChatHistoryBundle? bundle,
}) {
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      builder: (context) =>
          ChatHistoryScreen(messageId: messageId, title: title, bundle: bundle),
    ),
  );
}

/// The messages of a merged forward as they were: sender names, avatars,
/// times, text, pictures and files that open. Nothing can be done with
/// them but reading and opening.
class ChatHistoryScreen extends ConsumerWidget {
  const ChatHistoryScreen({
    required this.messageId,
    required this.title,
    this.bundle,
    super.key,
  });

  final String messageId;

  /// The name of the conversation it came from, shown while it loads.
  final String title;
  final ChatHistoryBundle? bundle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final wide = isWideLayout(MediaQuery.sizeOf(context).width);
    final loaded =
        bundle ?? ref.watch(chatHistoryBundleProvider(messageId)).value;
    final failed =
        bundle == null &&
        ref.watch(chatHistoryBundleProvider(messageId)).hasError;
    final heading = tr('Chat history: {name}', {
      'name': loaded?.title ?? title,
    });

    final Widget body;
    if (loaded != null) {
      body = _HistoryList(items: loaded.items, messageId: messageId);
    } else if (failed) {
      body = _HistoryNote(
        icon: Icons.error_outline_rounded,
        text: tr('Could not load the chat history.'),
        action: WeCordButton(
          variant: WeCordButtonVariant.secondary,
          size: WeCordButtonSize.medium,
          label: tr('Try again'),
          onPressed: () => ref.invalidate(chatHistoryBundleProvider(messageId)),
        ),
      );
    } else {
      body = Center(
        child: Semantics(
          label: tr('Loading'),
          child: CircularProgressIndicator(strokeWidth: 2.5, color: c.muted),
        ),
      );
    }

    final page = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HistoryHeader(
          title: heading,
          subtitle: loaded == null
              ? null
              : loaded.items.length == 1
              ? tr('1 message')
              : tr('{count} messages', {'count': loaded.items.length}),
        ),
        Expanded(child: body),
      ],
    );

    return Scaffold(
      key: const ValueKey('chat-history-screen'),
      backgroundColor: wide ? c.paper : c.panel,
      body: SafeArea(
        bottom: false,
        child: wide
            ? Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: Container(
                    margin: const EdgeInsets.only(top: 24),
                    decoration: BoxDecoration(
                      color: c.panel,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(WeCordRadii.xxl),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: page,
                  ),
                ),
              )
            : page,
      ),
    );
  }
}

class _HistoryHeader extends StatelessWidget {
  const _HistoryHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        children: [
          WeCordIconButton(
            key: const ValueKey('chat-history-back'),
            tooltip: tr('Back'),
            icon: Icons.arrow_back_ios_new_rounded,
            iconSize: 19,
            variant: WeCordButtonVariant.ghost,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              header: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 17,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: c.ink,
                    ),
                  ),
                  if (subtitle case final subtitle?)
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 12.5, color: c.muted),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryNote extends StatelessWidget {
  const _HistoryNote({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: c.faint),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.muted),
            ),
            if (action != null) ...[const SizedBox(height: 14), action!],
          ],
        ),
      ),
    );
  }
}

/// A bundle item as the message it was, for the picture, video and file
/// widgets of the chat.
ChatMessage _asMessage(BundleItem item, String bundleId) {
  return ChatMessage(
    id: item.messageId.isEmpty ? '$bundleId-${item.createdAt}' : item.messageId,
    conversationId: bundleId,
    senderId: item.senderId,
    type: item.type,
    body: item.type == MessageType.text ? item.body : '',
    createdAt: item.createdAt,
    attachment: item.attachment,
  );
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.items, required this.messageId});

  final List<BundleItem> items;
  final String messageId;

  @override
  Widget build(BuildContext context) {
    // Pictures, videos and files open into a gallery of the whole history.
    final gallery = [
      for (final item in items)
        if (item.image != null || item.file != null)
          ?PreviewFile.fromMessage(
            _asMessage(item, messageId),
            senderName: item.senderName,
          ),
    ];
    if (items.isEmpty) {
      return _HistoryNote(
        icon: Icons.forum_outlined,
        text: tr('This chat history is empty.'),
      );
    }
    return FilePreviewScope(
      conversationId: null,
      files: () => gallery,
      child: LayoutBuilder(
        builder: (context, constraints) => ListView.builder(
          key: const ValueKey('chat-history-list'),
          padding: EdgeInsets.fromLTRB(
            16,
            6,
            16,
            24 + MediaQuery.paddingOf(context).bottom,
          ),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final previous = index == 0 ? null : items[index - 1];
            final newDay =
                previous == null ||
                !_sameDay(previous.createdAt, item.createdAt);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (newDay) _DayLabel(time: item.createdAt),
                _BundleRow(
                  item: item,
                  bundleId: messageId,
                  isLast: index == items.length - 1,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) {
    final left = a.toLocal();
    final right = b.toLocal();
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.time});

  final DateTime time;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Semantics(
        header: true,
        child: Text(
          chatDayLabel(time),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: c.subtle,
          ),
        ),
      ),
    );
  }
}

class _BundleRow extends StatelessWidget {
  const _BundleRow({
    required this.item,
    required this.bundleId,
    required this.isLast,
  });

  final BundleItem item;
  final String bundleId;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final name = item.senderName.isEmpty ? tr('Someone') : item.senderName;
    final message = _asMessage(item, bundleId);
    final image = item.image;
    final file = item.file;
    final voice = item.voice;
    final contact = item.type == MessageType.text
        ? ContactCard.maybeFromAttachment(item.attachment)
        : null;
    final history = item.history;

    final Widget content;
    var readsAsOne = false;
    if (image != null || (file != null && file.isVideo)) {
      content = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: MessageMediaGroup(
          messages: [message],
          textColor: c.ink,
          desktop: isWideLayout(MediaQuery.sizeOf(context).width),
          framed: true,
        ),
      );
    } else if (file != null) {
      content = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: FileMessageContent(
            attachment: file,
            textColor: c.ink,
            card: true,
            sentAt: item.createdAt,
            senderName: name,
          ),
        ),
      );
    } else if (voice != null) {
      content = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: VoiceMessagePlayer(
            attachment: voice,
            foregroundColor: c.ink,
            card: true,
          ),
        ),
      );
    } else if (contact != null) {
      content = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: ContactCardView(card: contact),
      );
    } else if (history != null) {
      content = Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _NestedHistory(
          card: history,
          nested: item.nested,
          messageId: item.messageId,
        ),
      );
    } else {
      readsAsOne = true;
      content = MessageMarkdownText(
        body: item.body,
        mentions: const [],
        color: c.ink,
        enlargeEmojiOnly: true,
      );
    }

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: c.muted,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          chatClockTime(item.createdAt),
          style: TextStyle(fontSize: 12, color: c.subtle),
        ),
      ],
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: ChatAvatar(
              name: name,
              avatarUrl: item.senderAvatar,
              size: 36,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [header, const SizedBox(height: 2), content],
            ),
          ),
        ],
      ),
    );

    final spoken = spokenList([name, spokenClock(item.createdAt)]);
    return Container(
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: c.lineSoft)),
      ),
      child: readsAsOne
          ? Semantics(
              container: true,
              label: '$spoken: ${item.body}',
              excludeSemantics: true,
              child: row,
            )
          : Semantics(container: true, label: spoken, child: row),
    );
  }
}

/// A chat history that was forwarded inside this one: a small card that
/// opens its messages when they came along.
class _NestedHistory extends StatelessWidget {
  const _NestedHistory({
    required this.card,
    required this.nested,
    required this.messageId,
  });

  final ChatHistoryCard card;
  final BundleNested? nested;
  final String messageId;

  @override
  Widget build(BuildContext context) {
    final nested = this.nested;
    final preview = nested == null
        ? card.preview
        : [
            for (final item in nested.items.take(4))
              ChatHistoryLine(
                name: item.senderName,
                kind: switch (item.type) {
                  MessageType.image => ChatHistoryLineKind.image,
                  MessageType.voice => ChatHistoryLineKind.voice,
                  MessageType.file =>
                    item.file?.isVideo == true
                        ? ChatHistoryLineKind.video
                        : ChatHistoryLineKind.file,
                  _ =>
                    item.history != null
                        ? ChatHistoryLineKind.history
                        : ChatHistoryLineKind.text,
                },
                text: item.file?.name ?? item.body,
              ),
          ];
    final shown = ChatHistoryCard(
      title: card.title,
      count: nested?.count ?? card.count,
      preview: preview,
    );
    return ChatHistoryCardView(
      card: shown,
      messageId: messageId,
      enabled: nested != null,
      onOpen: nested == null
          ? null
          : () => unawaited(
              openChatHistory(
                context,
                messageId: messageId,
                title: nested.title,
                bundle: ChatHistoryBundle(
                  title: nested.title,
                  items: nested.items,
                ),
              ),
            ),
    );
  }
}

import 'package:clock/clock.dart';
import 'package:flutter/material.dart';
import 'package:wecord/features/inbox/digest/digest_models.dart';
import 'package:wecord/features/inbox/inbox_card_shell.dart';
import 'package:wecord/features/later/later_time.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// How many chats a digest card shows before "Show all".
const digestCardCollapsedChats = 3;

/// "Plan", or "#general · Hikers" for a circle channel.
String digestChatLabel(DigestChatSummary item) {
  final title = item.title.trim();
  final circle = item.circleName?.trim() ?? '';
  if (circle.isEmpty) {
    return title.isEmpty ? tr('Chat') : title;
  }
  return [if (title.isNotEmpty) '#$title', circle].join(' · ');
}

String _messageCount(int count) {
  return count == 1
      ? tr('1 message')
      : tr('{count} messages', {'count': count});
}

String _chatCount(int count) {
  return count == 1
      ? tr('1 chat had news')
      : tr('{count} chats had news', {'count': count});
}

/// The daily digest in Notifications: what happened in the chats the person
/// follows, a few bullet points for each, written by WeCord AI. Tapping a
/// chat opens it. It does not ask for an answer, so it has no colored edge:
/// the blue dot says it is new.
class AiDigestCard extends StatefulWidget {
  const AiDigestCard({
    required this.digest,
    required this.onOpenChat,
    required this.onMarkRead,
    super.key,
  });

  final AiDigest digest;

  /// Opens the chat with this id.
  final void Function(String conversationId) onOpenChat;
  final VoidCallback onMarkRead;

  @override
  State<AiDigestCard> createState() => _AiDigestCardState();
}

class _AiDigestCardState extends State<AiDigestCard> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final digest = widget.digest;
    final items = digest.items;
    final shown = _expanded || items.length <= digestCardCollapsedChats
        ? items
        : items.take(digestCardCollapsedChats).toList();
    final time = describeWhen(
      MaterialLocalizations.of(context),
      digest.createdAt.toLocal(),
      clock.now(),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final subtitle = _chatCount(items.length);
    return Semantics(
      container: true,
      label: '${tr('Daily digest')}, $subtitle',
      child: InboxCardShell(
        key: ValueKey('inbox-digest-${digest.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SettingsIconTile(
                  icon: Icons.auto_awesome_rounded,
                  tone: SettingsTone.accent,
                  size: 40,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              tr('Daily digest'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: c.ink,
                              ),
                            ),
                          ),
                          if (digest.isUnread)
                            Container(
                              key: const ValueKey('inbox-digest-unread-dot'),
                              margin: const EdgeInsets.only(left: 8),
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: c.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    time,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: c.muted,
                    ),
                  ),
                ),
              ],
            ),
            for (final item in shown) ...[
              const SizedBox(height: 10),
              _ChatBlock(
                key: ValueKey('digest-chat-${item.conversationId}'),
                item: item,
                onPressed: () => widget.onOpenChat(item.conversationId),
              ),
            ],
            if (items.length > digestCardCollapsedChats || digest.isUnread) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (items.length > digestCardCollapsedChats)
                    WeCordButton(
                      key: ValueKey('digest-expand-${digest.id}'),
                      label: _expanded
                          ? tr('Show less')
                          : tr('Show all {count} chats', {
                              'count': items.length,
                            }),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.secondary,
                      onPressed: () => setState(() => _expanded = !_expanded),
                    ),
                  if (digest.isUnread)
                    WeCordButton(
                      key: ValueKey('digest-read-${digest.id}'),
                      label: tr('Mark as read'),
                      size: WeCordButtonSize.small,
                      variant: WeCordButtonVariant.ghost,
                      onPressed: widget.onMarkRead,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// One chat's bullets in a quiet box; tapping opens the chat.
class _ChatBlock extends StatelessWidget {
  const _ChatBlock({required this.item, required this.onPressed, super.key});

  final DigestChatSummary item;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(WeCordRadii.md),
    );
    final label = digestChatLabel(item);
    return Semantics(
      button: true,
      label: '$label, ${_messageCount(item.messageCount)}',
      excludeSemantics: true,
      onTap: onPressed,
      child: WeCordPressable(
        onPressed: onPressed,
        shape: shape,
        pressedScale: 0.99,
        builder: (context, states) {
          final hovered =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed);
          return AnimatedContainer(
            duration: WeCordMotion.quick,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
            decoration: ShapeDecoration(
              color: hovered
                  ? Color.alphaBlend(c.ink.withValues(alpha: 0.03), c.well)
                  : c.well,
              shape: shape,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ),
                    if (item.messageCount > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        _messageCount(item.messageCount),
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                for (final bullet in item.bullets)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 1, right: 8),
                          child: Text(
                            '•',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: c.muted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            bullet,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.4,
                              color: c.ink,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

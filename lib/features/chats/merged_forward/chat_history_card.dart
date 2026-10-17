import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:wecord/features/chats/merged_forward/chat_history_screen.dart';
import 'package:wecord/features/chats/merged_forward/merged_forward_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// A merged forward in a chat: "Chat history: {name}", the first lines
/// and how many messages it holds. A tap opens the read-only page.
class ChatHistoryCardView extends StatelessWidget {
  const ChatHistoryCardView({
    required this.card,
    required this.messageId,
    this.onOpen,
    this.enabled = true,
    super.key,
  });

  final ChatHistoryCard card;

  /// The chat-history message, whose items the page reads.
  final String messageId;

  /// Opens the page; by default [openChatHistory].
  final VoidCallback? onOpen;

  /// False for a history whose messages did not come along: it shows what
  /// there is but opens nothing.
  final bool enabled;

  static const _maxLines = 4;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final lines = card.preview.take(_maxLines).toList(growable: false);
    final countLabel = card.count == 1
        ? tr('1 message')
        : tr('{count} messages', {'count': card.count});
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 280.0,
          280.0,
        );
        return SizedBox(
          width: width,
          child: WeCordPressable(
            key: ValueKey('chat-history-card-$messageId'),
            onPressed: !enabled
                ? null
                : onOpen ??
                      () => openChatHistory(
                        context,
                        messageId: messageId,
                        title: card.title,
                      ),
            semanticLabel: '${card.heading}, $countLabel',
            hint: enabled ? tr('Opens the chat history') : null,
            mergeSemantics: false,
            pressedScale: 0.99,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            builder: (context, states) => Container(
              decoration: BoxDecoration(
                color: c.panel,
                borderRadius: BorderRadius.circular(WeCordRadii.lg),
                border: Border.all(
                  color: states.contains(WidgetState.hovered)
                      ? c.faint
                      : c.line,
                ),
              ),
              padding: const EdgeInsets.fromLTRB(12, 11, 12, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    card.heading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      height: 1.3,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  if (lines.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    for (final line in lines)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          line.name.isEmpty
                              ? line.summary
                              : '${line.name}: ${line.summary}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: c.muted,
                          ),
                        ),
                      ),
                  ],
                  const SizedBox(height: 9),
                  Container(height: 1, color: c.lineSoft),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Icon(Icons.forum_outlined, size: 14, color: c.subtle),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            tr('Chat history'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: c.subtle,
                            ),
                          ),
                        ),
                        Text(
                          countLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: c.subtle,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

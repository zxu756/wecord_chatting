import 'package:flutter/material.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_editor.dart';
import 'package:wecord/features/chat_folders/chat_folder_rules.dart';
import 'package:wecord/features/home/conversation_preview.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The folded folder's chats as one row of the Messages list, like WeChat's
/// "Folded group chats": a folder tile, the folder's name, the newest
/// message among its chats, a gray count of unread chats and a red dot when
/// one mentions the person. Tapping it opens the folder.
class FoldedFolderRow extends StatelessWidget {
  const FoldedFolderRow({
    required this.entry,
    required this.currentUserId,
    required this.onOpen,
    this.dense = false,
    this.selected = false,
    super.key,
  });

  final FoldedEntry entry;
  final String? currentUserId;
  final VoidCallback onOpen;

  /// The desktop sidebar's smaller row.
  final bool dense;

  /// The folder is the one the list is showing.
  final bool selected;

  /// The newest chat in the fold.
  ConversationSummary? get _newest {
    ConversationSummary? newest;
    for (final chat in entry.members) {
      final at = chat.lastMessageAt;
      if (at == null) {
        continue;
      }
      final best = newest?.lastMessageAt;
      if (best == null || at.isAfter(best)) {
        newest = chat;
      }
    }
    return newest;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final c = tokens.colors;
    final folder = entry.folder;
    final newest = _newest;
    final preview = newest == null
        ? null
        : conversationPreviewText(newest, currentUserId: currentUserId);
    final subtitle = newest == null || preview == null || preview.isEmpty
        ? chatCountLabel(entry.members.length)
        : '${chatFolderChatTitle(newest)}: $preview';
    final lastMessageAt = newest?.lastMessageAt;
    final summary = entry.summary;
    final emphasized = summary.unread > 0 || summary.mention;
    final avatarSize = dense ? 36.0 : 46.0;
    final label = spokenFolded(
      folder.name,
      count: entry.members.length,
      summary: summary,
      subtitle: subtitle,
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: dense ? 0.5 : 0),
      child: WeCordPressable(
        key: const ValueKey('folded-folder-row'),
        semanticLabel: label,
        excludeSemantics: true,
        hint: tr('Opens the folder'),
        selected: selected,
        onPressed: onOpen,
        pressedScale: 0.98,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(dense ? 12 : WeCordRadii.lg),
        ),
        builder: (context, states) {
          final hovered =
              states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.pressed);
          final background = dense
              ? (selected
                    ? (tokens.isDark ? c.raised : c.panel)
                    : hovered
                    ? c.raised
                    : c.raised.withValues(alpha: 0))
              : emphasized
              ? c.accentSoft
              : hovered
              ? c.raised
              : c.panel;
          return AnimatedContainer(
            duration: WeCordMotion.quick,
            curve: WeCordMotion.standard,
            padding: EdgeInsets.symmetric(
              horizontal: dense ? 10 : 12,
              vertical: dense
                  ? context.density.space(7)
                  : context.density.space(9),
            ),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(dense ? 12 : WeCordRadii.lg),
              boxShadow: dense && selected ? tokens.shadows.hairline : null,
            ),
            child: Row(
              children: [
                ThingAvatar(
                  icon: chatFolderIcon(folder.icon),
                  size: avatarSize,
                  color: c.raised,
                  foregroundColor: c.muted,
                  semanticLabel: folder.name,
                ),
                SizedBox(width: dense ? 10 : 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              folder.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: dense ? 14 : 16,
                                height: 1.3,
                                color: c.ink,
                                fontWeight: emphasized
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (lastMessageAt != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              compactAge(lastMessageAt),
                              style: TextStyle(
                                fontSize: dense ? 11 : 12,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: dense ? 12.5 : 14,
                                height: 1.35,
                                color: emphasized ? c.ink : c.muted,
                                fontWeight: emphasized
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ),
                          if (summary.unread > 0) ...[
                            const SizedBox(width: 6),
                            CountBadge(
                              key: const ValueKey('folded-folder-count'),
                              count: summary.unread,
                              size: dense ? 17 : 20,
                            ),
                          ],
                          if (summary.mention) ...[
                            const SizedBox(width: 4),
                            const CountBadge.dot(
                              key: ValueKey('folded-folder-mention'),
                              tone: BadgeTone.mention,
                            ),
                          ],
                        ],
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

/// What a screen reader says for the folded row: the name, how many chats
/// are in it, how many are unread, a mention and the newest message.
String spokenFolded(
  String name, {
  required int count,
  required FolderSummary summary,
  required String subtitle,
}) {
  return [
    name,
    chatCountLabel(count),
    if (summary.unread > 0) tr('{count} unread', {'count': summary.unread}),
    if (summary.mention) tr('You are mentioned'),
    subtitle,
  ].join(', ');
}

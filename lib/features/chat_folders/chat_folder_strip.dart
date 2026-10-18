import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_editor.dart';
import 'package:wecord/features/chat_folders/chat_folder_rules.dart';
import 'package:wecord/features/chat_folders/chat_folders_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// What a screen reader says for a folder chip: its name, how many chats
/// are unread and whether one mentions the person.
String folderChipLabel(String name, FolderSummary summary) {
  return [
    name,
    if (summary.unread > 0) tr('{count} unread', {'count': summary.unread}),
    if (summary.mention) tr('You are mentioned'),
  ].join(', ');
}

/// The strip of chips under the "Messages" title: All, Unread and each of
/// the person's folders, scrolling sideways. A folder's chip shows how many
/// of its chats are unread in a gray pill, and a red dot when one of them
/// mentions the person. Hold a folder (or right-click it) to edit it.
class ChatFolderStrip extends ConsumerStatefulWidget {
  const ChatFolderStrip({
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 8),
    super.key,
  });

  final EdgeInsetsGeometry padding;

  @override
  ConsumerState<ChatFolderStrip> createState() => _ChatFolderStripState();
}

class _ChatFolderStripState extends ConsumerState<ChatFolderStrip> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// A mouse wheel moves the strip sideways, since it has no vertical room.
  void _wheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dx != 0 ||
        !_scroll.hasClients) {
      return;
    }
    GestureBinding.instance.pointerSignalResolver.register(event, (event) {
      final position = _scroll.position;
      final target =
          (position.pixels + (event as PointerScrollEvent).scrollDelta.dy)
              .clamp(position.minScrollExtent, position.maxScrollExtent);
      _scroll.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final folders =
        ref.watch(chatFoldersProvider).value ?? const <ChatFolder>[];
    final chats = ref.watch(chatFolderChatsProvider);
    final userId = ref.watch(authStateProvider).value?.id;
    final selected = ref.watch(effectiveChatFolderSelectionProvider);
    final selection = ref.read(chatFolderSelectionProvider.notifier);

    Widget folderChip({
      required Key key,
      required String label,
      required bool isSelected,
      required FolderSummary? summary,
      required VoidCallback onPressed,
      VoidCallback? onEdit,
    }) {
      final trailing =
          summary == null || (summary.unread == 0 && !summary.mention)
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (summary.unread > 0)
                  CountBadge(
                    count: summary.unread,
                    size: 17,
                    semanticLabel: '',
                  ),
                if (summary.mention) ...[
                  if (summary.unread > 0) const SizedBox(width: 4),
                  const CountBadge.dot(
                    key: ValueKey('chat-folder-mention-dot'),
                    tone: BadgeTone.mention,
                    size: 9,
                    semanticLabel: '',
                  ),
                ],
              ],
            );
      Widget chip = WeCordChip(
        key: key,
        label: label,
        selected: isSelected,
        trailing: trailing,
        semanticLabel: summary == null
            ? label
            : folderChipLabel(label, summary),
        hint: onEdit == null ? null : tr('Hold to edit this folder'),
        onPressed: onPressed,
        onLongPress: onEdit,
      );
      if (onEdit != null) {
        chip = GestureDetector(
          onSecondaryTap: onEdit,
          excludeFromSemantics: true,
          behavior: HitTestBehavior.translucent,
          child: chip,
        );
      }
      return chip;
    }

    final unreadSummary = FolderSummary.of(chats, userId);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: tr('Chat folders'),
      child: Listener(
        onPointerSignal: _wheel,
        child: SingleChildScrollView(
          key: const ValueKey('chat-folder-strip'),
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          padding: widget.padding,
          child: Row(
            children: [
              folderChip(
                key: const ValueKey('chat-folder-all'),
                label: tr('All'),
                isSelected: selected == null,
                summary: null,
                onPressed: () => selection.select(null),
              ),
              const SizedBox(width: 8),
              folderChip(
                key: const ValueKey('chat-folder-unread'),
                label: tr('Unread'),
                isSelected: selected == unreadFilterId,
                summary: unreadSummary,
                onPressed: () => selection.select(unreadFilterId),
              ),
              for (final folder in folders) ...[
                const SizedBox(width: 8),
                folderChip(
                  key: ValueKey('chat-folder-${folder.id}'),
                  label: folder.name,
                  isSelected: selected == folder.id,
                  summary: FolderSummary.of(
                    chatsInFolder(folder, chats),
                    userId,
                  ),
                  onPressed: () => selection.select(folder.id),
                  onEdit: () =>
                      unawaited(showChatFolderEditor(context, folder: folder)),
                ),
              ],
              if (folders.length < maxChatFolders) ...[
                const SizedBox(width: 8),
                WeCordIconButton(
                  key: const ValueKey('chat-folder-new'),
                  icon: Icons.add_rounded,
                  tooltip: tr('New folder'),
                  variant: WeCordButtonVariant.secondary,
                  size: 34,
                  iconSize: 18,
                  onPressed: () => unawaited(showChatFolderEditor(context)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// What the list says when the selected entry of the strip has no chats:
/// everything is read, or the folder's rules take nothing yet.
class ChatFolderEmptyNote extends StatelessWidget {
  const ChatFolderEmptyNote({
    required this.selected,
    required this.folders,
    super.key,
  });

  /// The strip's selection ([unreadFilterId] or a folder's id).
  final String? selected;
  final List<ChatFolder> folders;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final folder = folders.where((f) => f.id == selected).firstOrNull;
    final text = folder == null
        ? tr('Nothing unread')
        : tr('No chats in this folder yet.');
    return Padding(
      key: const ValueKey('chat-folder-empty'),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text, style: TextStyle(fontSize: 14, color: c.muted)),
          if (folder != null) ...[
            const SizedBox(height: 10),
            WeCordButton(
              key: const ValueKey('chat-folder-empty-edit'),
              label: tr('Edit folder'),
              variant: WeCordButtonVariant.secondary,
              size: WeCordButtonSize.small,
              onPressed: () =>
                  unawaited(showChatFolderEditor(context, folder: folder)),
            ),
          ],
        ],
      ),
    );
  }
}

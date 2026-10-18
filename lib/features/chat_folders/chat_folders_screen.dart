import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_editor.dart';
import 'package:wecord/features/chat_folders/chat_folders_repository.dart';
import 'package:wecord/features/settings/settings_page.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens Settings -> Chats -> Chat folders.
void openChatFolders(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (context) => const ChatFoldersScreen()),
  );
}

/// A few words on what a folder takes: "Groups · Unread only · 3 chats
/// picked".
String chatFolderRulesSummary(ChatFolder folder) {
  final parts = <String>[
    if (folder.includeTypes.contains(ConversationType.direct))
      tr('Direct messages'),
    if (folder.includeTypes.contains(ConversationType.group)) tr('Groups'),
    if (folder.includeTypes.isNotEmpty && folder.onlyUnread) tr('Unread only'),
    if (folder.includeTypes.isNotEmpty && folder.excludeMuted) tr('Not muted'),
    if (folder.includeTypes.isNotEmpty && folder.onlyMuted) tr('Muted only'),
    if (folder.includeIds.isNotEmpty)
      tr('{count} picked', {'count': folder.includeIds.length}),
    if (folder.excludeIds.isNotEmpty)
      tr('{count} left out', {'count': folder.excludeIds.length}),
    if (folder.folded) tr('Folded'),
  ];
  return parts.isEmpty ? tr('Nothing yet') : parts.join(' · ');
}

/// Settings -> Chats -> Chat folders: the person's folders to make, arrange
/// (drag a row, or use the reorder actions a screen reader offers), edit
/// and delete, and templates to start from. Folders are private; only the
/// rules are stored and the chat list is filtered on this device.
class ChatFoldersScreen extends ConsumerStatefulWidget {
  const ChatFoldersScreen({super.key});

  @override
  ConsumerState<ChatFoldersScreen> createState() => _ChatFoldersScreenState();
}

class _ChatFoldersScreenState extends ConsumerState<ChatFoldersScreen> {
  /// The order just chosen, until the server's list has caught up.
  List<String>? _pending;

  List<ChatFolder> _arranged(List<ChatFolder> folders) {
    final pending = _pending;
    if (pending == null) {
      return folders;
    }
    if (listEquals([for (final folder in folders) folder.id], pending)) {
      _pending = null;
      return folders;
    }
    final byId = {for (final folder in folders) folder.id: folder};
    return [
      for (final id in pending) ?byId[id],
      for (final folder in folders)
        if (!pending.contains(folder.id)) folder,
    ];
  }

  Future<void> _reorder(List<ChatFolder> folders, int from, int to) async {
    final next = [...folders];
    next.insert(to, next.removeAt(from));
    final ids = [for (final folder in next) folder.id];
    setState(() => _pending = ids);
    try {
      await ref.read(chatFoldersRepositoryProvider).reorder(ids);
      ref.invalidate(chatFoldersProvider);
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _pending = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(tr('Could not change the order. Try again.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final data = ref.watch(chatFoldersProvider);
    final loaded = data.value;
    final folders = loaded == null ? const <ChatFolder>[] : _arranged(loaded);
    final canAdd = folders.length < maxChatFolders;
    return SettingsPage(
      title: tr('Chat folders'),
      actions: [
        if (canAdd)
          WeCordButton(
            key: const ValueKey('chat-folders-new'),
            label: tr('New folder'),
            icon: Icons.add_rounded,
            size: WeCordButtonSize.small,
            variant: WeCordButtonVariant.accent,
            onPressed: () => unawaited(showChatFolderEditor(context)),
          ),
      ],
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 12),
          child: Text(
            tr(
              'Folders sort your chats on the Messages list. They are private to you and follow you to your other devices.',
            ),
            style: TextStyle(fontSize: 13.5, height: 1.4, color: c.muted),
          ),
        ),
        if (loaded == null && data.isLoading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (loaded == null)
          Center(
            child: WeCordButton(
              label: tr('Try again'),
              onPressed: () => ref.invalidate(chatFoldersProvider),
            ),
          )
        else if (folders.isEmpty)
          _EmptyFolders(
            onCreate: () => unawaited(showChatFolderEditor(context)),
          )
        else
          _FolderList(
            folders: folders,
            onReorder: (from, to) => unawaited(_reorder(folders, from, to)),
          ),
        if (loaded != null && canAdd) ...[
          SettingsSectionHeader(tr('Start from a template')),
          SettingsGroup(
            children: [
              for (final template in ChatFolderTemplate.values)
                SettingsRow(
                  key: ValueKey('chat-folder-template-row-${template.name}'),
                  icon: _templateIcon(template),
                  tone: template == ChatFolderTemplate.foldedGroups
                      ? SettingsTone.warning
                      : SettingsTone.neutral,
                  title: chatFolderTemplateName(template),
                  subtitle: chatFolderTemplateHint(template),
                  onTap: () => unawaited(
                    showChatFolderEditor(context, template: template),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

IconData _templateIcon(ChatFolderTemplate template) {
  return switch (template) {
    ChatFolderTemplate.unread => Icons.mark_chat_unread_outlined,
    ChatFolderTemplate.groups => Icons.groups_outlined,
    ChatFolderTemplate.directMessages => Icons.person_outline_rounded,
    ChatFolderTemplate.muted => Icons.notifications_off_outlined,
    ChatFolderTemplate.foldedGroups => Icons.unfold_less_rounded,
  };
}

class _FolderList extends StatelessWidget {
  const _FolderList({required this.folders, required this.onReorder});

  final List<ChatFolder> folders;
  final void Function(int from, int to) onReorder;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: ReorderableListView.builder(
        key: const ValueKey('chat-folders-list'),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        itemCount: folders.length,
        onReorderItem: onReorder,
        proxyDecorator: (child, index, animation) => Material(
          color: c.panel,
          elevation: 0,
          shadowColor: Colors.transparent,
          child: child,
        ),
        itemBuilder: (context, index) {
          final folder = folders[index];
          return _FolderRow(
            key: ValueKey('chat-folder-row-${folder.id}'),
            folder: folder,
            index: index,
            first: index == 0,
          );
        },
      ),
    );
  }
}

class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.index,
    required this.first,
    super.key,
  });

  final ChatFolder folder;
  final int index;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.panel,
        border: first ? null : Border(top: BorderSide(color: c.lineSoft)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SettingsRow(
              icon: chatFolderIcon(folder.icon),
              tone: SettingsTone.accent,
              title: folder.name,
              subtitle: chatFolderRulesSummary(folder),
              onTap: () =>
                  unawaited(showChatFolderEditor(context, folder: folder)),
            ),
          ),
          // The handle is for the mouse and the finger; a screen reader gets
          // "move up / move down" actions on the row instead.
          ExcludeSemantics(
            child: ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 16, 12),
                child: Icon(
                  Icons.drag_handle_rounded,
                  size: 22,
                  color: c.faint,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyFolders extends StatelessWidget {
  const _EmptyFolders({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Container(
      key: const ValueKey('chat-folders-empty'),
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      decoration: BoxDecoration(
        color: c.panel,
        borderRadius: BorderRadius.circular(WeCordRadii.xl),
      ),
      child: Column(
        children: [
          const SettingsIconTile(
            icon: Icons.folder_outlined,
            tone: SettingsTone.accent,
            size: 52,
          ),
          const SizedBox(height: 14),
          Text(
            tr('No folders yet'),
            style: Theme.of(
              context,
            ).textTheme.displaySmall?.copyWith(fontSize: 22, color: c.ink),
          ),
          const SizedBox(height: 6),
          Text(
            tr('Make one for work, family or the groups you rarely read.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
          ),
          const SizedBox(height: 16),
          WeCordButton(label: tr('New folder'), onPressed: onCreate),
        ],
      ),
    );
  }
}

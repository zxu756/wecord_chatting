import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folder_editor.dart';
import 'package:wecord/features/chat_folders/chat_folder_rules.dart';
import 'package:wecord/features/chat_folders/chat_folders_repository.dart';
import 'package:wecord/features/friend_tags/friend_picker.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// "Add to folder…": a sheet of the person's folders for [conversation],
/// each switched on or off with a tap, and a row to make a new one with
/// this chat in it.
Future<void> showAddToFolderSheet(
  BuildContext context,
  ConversationSummary conversation,
) async {
  final makeNew = await showWeCordSheet<bool>(
    context,
    title: tr('Add to folder'),
    builder: (context, _) => AddToFolderSheet(conversation: conversation),
  );
  if (makeNew == true && context.mounted) {
    await showChatFolderEditor(
      context,
      seed: ChatFolder.draft(name: '', includeIds: {conversation.id}),
    );
  }
}

class AddToFolderSheet extends ConsumerStatefulWidget {
  const AddToFolderSheet({required this.conversation, super.key});

  final ConversationSummary conversation;

  @override
  ConsumerState<AddToFolderSheet> createState() => _AddToFolderSheetState();
}

class _AddToFolderSheetState extends ConsumerState<AddToFolderSheet> {
  String? _error;
  final _busy = <String>{};

  Future<void> _toggle(ChatFolder folder) async {
    if (_busy.contains(folder.id)) {
      return;
    }
    final taken = folderTakes(folder, widget.conversation);
    final next = withChatIn(folder, widget.conversation, include: !taken);
    setState(() {
      _busy.add(folder.id);
      _error = null;
    });
    try {
      await ref.read(chatFoldersRepositoryProvider).update(next);
      ref.invalidate(chatFoldersProvider);
    } catch (_) {
      if (mounted) {
        setState(() => _error = tr('Could not update the folder. Try again.'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(folder.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final folders =
        ref.watch(chatFoldersProvider).value ?? const <ChatFolder>[];
    final chat = widget.conversation;
    return SafeArea(
      top: false,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
            child: Text(
              chatFolderChatTitle(chat),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ),
          if (folders.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                tr(
                  'You have no folders yet. Make one and this chat goes in it.',
                ),
                key: const ValueKey('add-to-folder-empty'),
                style: TextStyle(fontSize: 14, height: 1.4, color: c.muted),
              ),
            ),
          for (final folder in folders)
            _FolderCheckRow(
              folder: folder,
              chat: chat,
              busy: _busy.contains(folder.id),
              onToggle: () => unawaited(_toggle(folder)),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  _error!,
                  key: const ValueKey('add-to-folder-error'),
                  style: TextStyle(fontSize: 13.5, color: c.dangerText),
                ),
              ),
            ),
          if (folders.length < maxChatFolders) ...[
            const SizedBox(height: 6),
            SettingsGroup(
              color: c.well,
              children: [
                SettingsRow(
                  key: const ValueKey('add-to-folder-new'),
                  icon: Icons.create_new_folder_outlined,
                  tone: SettingsTone.accent,
                  title: tr('New folder'),
                  showChevron: false,
                  onTap: () => Navigator.of(context).pop(true),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FolderCheckRow extends StatelessWidget {
  const _FolderCheckRow({
    required this.folder,
    required this.chat,
    required this.busy,
    required this.onToggle,
  });

  final ChatFolder folder;
  final ConversationSummary chat;
  final bool busy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final taken = folderTakes(folder, chat);
    final listed = folder.includeIds.contains(chat.id);
    final subtitle = taken && !listed
        ? tr('Included by its rules')
        : folder.folded
        ? tr('Folded into one row')
        : null;
    return WeCordPressable(
      key: ValueKey('add-to-folder-${folder.id}'),
      toggled: taken,
      semanticLabel: subtitle == null
          ? folder.name
          : '${folder.name}, $subtitle',
      excludeSemantics: true,
      onPressed: busy ? null : onToggle,
      pressedScale: 0.98,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: hovered ? c.raised : c.panel,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              SettingsIconTile(
                icon: chatFolderIcon(folder.icon),
                tone: SettingsTone.accent,
                size: 40,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      folder.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: c.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              CheckCircle(checked: taken),
            ],
          ),
        );
      },
    );
  }
}

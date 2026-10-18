import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chat_folders/chat_folder.dart';
import 'package:wecord/features/chat_folders/chat_folders_repository.dart';
import 'package:wecord/features/friend_tags/friend_picker.dart';
import 'package:wecord/features/home/home_avatars.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/ui/ui.dart';

/// The name a template gives its folder.
String chatFolderTemplateName(ChatFolderTemplate template) {
  return switch (template) {
    ChatFolderTemplate.unread => tr('Unread (not muted)'),
    ChatFolderTemplate.groups => tr('Groups'),
    ChatFolderTemplate.directMessages => tr('Direct messages'),
    ChatFolderTemplate.muted => tr('Muted'),
    ChatFolderTemplate.foldedGroups => tr('Folded group chats'),
  };
}

/// What a template does, in a few words.
String chatFolderTemplateHint(ChatFolderTemplate template) {
  return switch (template) {
    ChatFolderTemplate.unread => tr('Chats with something new, except muted'),
    ChatFolderTemplate.groups => tr('Every group chat'),
    ChatFolderTemplate.directMessages => tr('Every one-to-one chat'),
    ChatFolderTemplate.muted => tr('Chats you muted'),
    ChatFolderTemplate.foldedGroups => tr(
      'Pick groups to fold into a single row',
    ),
  };
}

/// The words for a problem saving a folder.
String chatFolderProblemText(ChatFolderProblem problem) {
  return switch (problem) {
    ChatFolderProblem.limit => tr('You can have up to {count} folders.', {
      'count': maxChatFolders,
    }),
    ChatFolderProblem.alreadyFolded => tr(
      'Only one folder can be folded. Turn it off in the other folder first.',
    ),
    ChatFolderProblem.name => tr(
      'Give the folder a name of up to {count} characters.',
      {'count': maxChatFolderNameLength},
    ),
  };
}

/// "No chats" / "1 chat" / "3 chats".
String chatCountLabel(int count) {
  return switch (count) {
    0 => tr('No chats'),
    1 => tr('1 chat'),
    _ => tr('{count} chats', {'count': count}),
  };
}

/// The title a chat is listed under.
String chatFolderChatTitle(ConversationSummary chat) {
  final title = chat.title?.trim();
  return title == null || title.isEmpty ? tr('Conversation') : title;
}

/// Makes a folder (when [folder] is null; [template] fills it in) or edits
/// one: its name, icon, rules, chats and whether it folds. Resolves to true
/// when something changed.
Future<bool?> showChatFolderEditor(
  BuildContext context, {
  ChatFolder? folder,
  ChatFolderTemplate? template,
  ChatFolder? seed,
}) {
  return showWeCordSheet<bool>(
    context,
    title: folder == null ? tr('New folder') : tr('Edit folder'),
    detents: const [0.6, 0.94],
    initialDetent: 0.94,
    builder: (context, scrollController) => ChatFolderEditor(
      folder: folder,
      template: template,
      seed: seed,
      scroll: scrollController,
    ),
  );
}

enum _MutedFilter { any, notMuted, onlyMuted }

class ChatFolderEditor extends ConsumerStatefulWidget {
  const ChatFolderEditor({
    this.folder,
    this.template,
    this.seed,
    this.scroll,
    super.key,
  });

  final ChatFolder? folder;
  final ChatFolderTemplate? template;

  /// Rules to start a new folder from (a chat that is put in it, say).
  final ChatFolder? seed;
  final ScrollController? scroll;

  @override
  ConsumerState<ChatFolderEditor> createState() => _ChatFolderEditorState();
}

class _ChatFolderEditorState extends ConsumerState<ChatFolderEditor> {
  late final TextEditingController _name;
  late String _icon;
  late Set<ConversationType> _types;
  late Set<String> _includeIds;
  late Set<String> _excludeIds;
  late bool _onlyUnread;
  late _MutedFilter _muted;
  late bool _folded;
  String? _problem;
  String? _error;
  var _saving = false;

  ChatFolder? get _existing => widget.folder;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _load(
      widget.folder ??
          widget.template?.build(chatFolderTemplateName(widget.template!)) ??
          widget.seed ??
          const ChatFolder.draft(name: ''),
    );
  }

  void _load(ChatFolder source) {
    _name.text = source.name;
    _icon = source.icon;
    _types = {...source.includeTypes};
    _includeIds = {...source.includeIds};
    _excludeIds = {...source.excludeIds};
    _onlyUnread = source.onlyUnread;
    _muted = source.onlyMuted
        ? _MutedFilter.onlyMuted
        : source.excludeMuted
        ? _MutedFilter.notMuted
        : _MutedFilter.any;
    _folded = source.folded;
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  ChatFolder _build() {
    final base = _existing;
    return ChatFolder(
      id: base?.id ?? '',
      name: _name.text.trim(),
      icon: _icon,
      sortKey: base?.sortKey ?? 0,
      includeTypes: _types,
      includeIds: _includeIds,
      excludeIds: _excludeIds,
      onlyUnread: _onlyUnread,
      excludeMuted: _muted == _MutedFilter.notMuted,
      onlyMuted: _muted == _MutedFilter.onlyMuted,
      folded: _folded,
    );
  }

  Future<void> _save() async {
    final draft = _build();
    if (checkChatFolderName(draft.name) != null) {
      setState(() => _problem = chatFolderProblemText(ChatFolderProblem.name));
      return;
    }
    setState(() {
      _saving = true;
      _problem = null;
      _error = null;
    });
    final repository = ref.read(chatFoldersRepositoryProvider);
    try {
      if (_existing == null) {
        final folders = ref.read(chatFoldersProvider).value ?? const [];
        final last = folders.fold<int>(
          0,
          (top, folder) => folder.sortKey > top ? folder.sortKey : top,
        );
        final created = await repository.create(
          ChatFolder(
            id: '',
            name: draft.name,
            icon: draft.icon,
            sortKey: last + 1,
            includeTypes: draft.includeTypes,
            includeIds: draft.includeIds,
            excludeIds: draft.excludeIds,
            onlyUnread: draft.onlyUnread,
            excludeMuted: draft.excludeMuted,
            onlyMuted: draft.onlyMuted,
            folded: draft.folded,
          ),
        );
        // Show what was just made.
        ref.read(chatFolderSelectionProvider.notifier).select(created.id);
      } else {
        await repository.update(draft);
      }
      ref.invalidate(chatFoldersProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ChatFolderException catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = chatFolderProblemText(error.problem);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not save the folder. Try again.');
        });
      }
    }
  }

  Future<void> _delete() async {
    final folder = _existing!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete folder?')),
        content: Text(
          tr('"{name}" is removed. Your chats stay where they are.', {
            'name': folder.name,
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            key: const ValueKey('chat-folder-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(chatFoldersRepositoryProvider).delete(folder.id);
      ref.invalidate(chatFoldersProvider);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = tr('Could not delete the folder. Try again.');
        });
      }
    }
  }

  Future<void> _pickChats({required bool include}) async {
    final chats = ref.read(chatFolderChatsProvider);
    final current = include ? _includeIds : _excludeIds;
    final picked = await showChatPicker(
      context,
      title: include ? tr('Always include') : tr('Never include'),
      chats: [
        for (final chat in chats)
          if (!chat.isNoteToSelf) chat,
      ],
      selected: current,
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      if (include) {
        _includeIds = picked;
        _excludeIds = _excludeIds.difference(picked);
      } else {
        _excludeIds = picked;
        _includeIds = _includeIds.difference(picked);
      }
    });
  }

  void _toggleType(ConversationType type, bool on) {
    setState(() {
      on ? _types.add(type) : _types.remove(type);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final folders = ref.watch(chatFoldersProvider).value ?? const [];
    final otherFolded = folders.any(
      (folder) => folder.folded && folder.id != _existing?.id,
    );
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                controller: widget.scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: [
                  if (_existing == null) ...[
                    SettingsSectionHeader(tr('Start from')),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final template in ChatFolderTemplate.values)
                          WeCordChip(
                            key: ValueKey(
                              'chat-folder-template-${template.name}',
                            ),
                            label: chatFolderTemplateName(template),
                            onPressed: () => setState(
                              () => _load(
                                template.build(
                                  chatFolderTemplateName(template),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  SizedBox(height: _existing == null ? 8 : 0),
                  WeCordTextField(
                    fieldKey: const ValueKey('chat-folder-name-field'),
                    controller: _name,
                    label: tr('Name'),
                    hint: tr('Work, Family, Climbing…'),
                    inputFormatters: [
                      LengthLimitingTextInputFormatter(
                        maxChatFolderNameLength * 2,
                      ),
                    ],
                    errorText: _problem,
                    textInputAction: TextInputAction.done,
                    autofocus: _existing == null && _name.text.isEmpty,
                    onChanged: (_) {
                      if (_problem != null) {
                        setState(() => _problem = null);
                      }
                    },
                  ),
                  SettingsSectionHeader(tr('Icon')),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final MapEntry(key: key, value: icon)
                          in chatFolderIcons.entries)
                        _IconChoice(
                          key: ValueKey('chat-folder-icon-$key'),
                          icon: icon,
                          selected: _icon == key,
                          label: _iconName(key),
                          onPressed: () => setState(() => _icon = key),
                        ),
                    ],
                  ),
                  SettingsSectionHeader(tr('Chats it takes by itself')),
                  SettingsGroup(
                    color: c.well,
                    children: [
                      SettingsRow.toggle(
                        key: const ValueKey('chat-folder-direct'),
                        icon: Icons.person_outline_rounded,
                        title: tr('Direct messages'),
                        value: _types.contains(ConversationType.direct),
                        onChanged: (on) =>
                            _toggleType(ConversationType.direct, on),
                      ),
                      SettingsRow.toggle(
                        key: const ValueKey('chat-folder-group'),
                        icon: Icons.groups_outlined,
                        title: tr('Groups'),
                        value: _types.contains(ConversationType.group),
                        onChanged: (on) =>
                            _toggleType(ConversationType.group, on),
                      ),
                      SettingsRow.toggle(
                        key: const ValueKey('chat-folder-only-unread'),
                        icon: Icons.mark_chat_unread_outlined,
                        title: tr('Only unread chats'),
                        value: _onlyUnread,
                        onChanged: (on) => setState(() => _onlyUnread = on),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  WeCordSegmented<_MutedFilter>(
                    expand: true,
                    semanticLabel: tr('Muted chats'),
                    selected: _muted,
                    onChanged: (value) => setState(() => _muted = value),
                    segments: [
                      WeCordSegment(
                        key: const ValueKey('chat-folder-muted-any'),
                        value: _MutedFilter.any,
                        label: tr('Any'),
                      ),
                      WeCordSegment(
                        key: const ValueKey('chat-folder-muted-hide'),
                        value: _MutedFilter.notMuted,
                        label: tr('Not muted'),
                      ),
                      WeCordSegment(
                        key: const ValueKey('chat-folder-muted-only'),
                        value: _MutedFilter.onlyMuted,
                        label: tr('Muted'),
                      ),
                    ],
                  ),
                  SettingsSectionHeader(tr('Chats you pick')),
                  SettingsGroup(
                    color: c.well,
                    children: [
                      SettingsRow(
                        key: const ValueKey('chat-folder-include'),
                        icon: Icons.add_circle_outline_rounded,
                        tone: SettingsTone.success,
                        title: tr('Always include'),
                        value: chatCountLabel(_includeIds.length),
                        onTap: () => unawaited(_pickChats(include: true)),
                      ),
                      SettingsRow(
                        key: const ValueKey('chat-folder-exclude'),
                        icon: Icons.remove_circle_outline_rounded,
                        tone: SettingsTone.danger,
                        title: tr('Never include'),
                        value: chatCountLabel(_excludeIds.length),
                        onTap: () => unawaited(_pickChats(include: false)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    color: c.well,
                    footer: otherFolded && !_folded
                        ? tr(
                            'Only one folder can be folded. Turn it off in the other folder first.',
                          )
                        : tr(
                            'Its chats leave the Messages list and show as one row.',
                          ),
                    children: [
                      SettingsRow.toggle(
                        key: const ValueKey('chat-folder-folded'),
                        icon: Icons.unfold_less_rounded,
                        title: tr('Fold into one row'),
                        value: _folded,
                        onChanged: otherFolded && !_folded
                            ? null
                            : (on) => setState(() => _folded = on),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Save and delete stay in reach however long the form is.
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          key: const ValueKey('chat-folder-error'),
                          style: TextStyle(fontSize: 13.5, color: c.dangerText),
                        ),
                      ),
                    ),
                  WeCordButton(
                    key: const ValueKey('chat-folder-save'),
                    label: _existing == null ? tr('Create folder') : tr('Save'),
                    size: WeCordButtonSize.large,
                    expand: true,
                    loading: _saving,
                    onPressed: _save,
                  ),
                  if (_existing != null) ...[
                    const SizedBox(height: 4),
                    WeCordButton(
                      key: const ValueKey('chat-folder-delete'),
                      label: tr('Delete folder'),
                      variant: WeCordButtonVariant.ghost,
                      expand: true,
                      onPressed: _saving ? null : _delete,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _iconName(String key) {
  return switch (key) {
    'work' => tr('Work'),
    'home' => tr('House'),
    'people' => tr('People'),
    'chat' => tr('Chat'),
    'star' => tr('Star'),
    'heart' => tr('Heart'),
    'school' => tr('School'),
    'game' => tr('Games'),
    'shopping' => tr('Shopping'),
    'travel' => tr('Travel'),
    'mail' => tr('Mail'),
    _ => tr('Folder'),
  };
}

/// One icon to pick, as a round tile with the accent ring when chosen.
class _IconChoice extends StatelessWidget {
  const _IconChoice({
    required this.icon,
    required this.selected,
    required this.label,
    required this.onPressed,
    super.key,
  });

  final IconData icon;
  final bool selected;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return WeCordPressable(
      selected: selected,
      semanticLabel: label,
      excludeSemantics: true,
      exclusiveGroup: true,
      onPressed: () {
        WeCordHaptics.selection();
        onPressed();
      },
      shape: const CircleBorder(),
      builder: (context, states) => AnimatedContainer(
        duration: WeCordMotion.quick,
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? c.accentSoft : c.raised,
          border: Border.all(
            color: selected ? c.accent : Colors.transparent,
            width: 2,
          ),
        ),
        child: Icon(icon, size: 20, color: selected ? c.accentText : c.muted),
      ),
    );
  }
}

/// Picks chats from [chats] with check circles; resolves to the chosen ids
/// when the person taps Done, or null if they close the sheet.
Future<Set<String>?> showChatPicker(
  BuildContext context, {
  required String title,
  required List<ConversationSummary> chats,
  required Set<String> selected,
}) {
  return showWeCordSheet<Set<String>>(
    context,
    title: title,
    detents: const [0.6, 0.94],
    initialDetent: 0.94,
    builder: (context, scrollController) =>
        _ChatPicker(chats: chats, selected: selected, scroll: scrollController),
  );
}

class _ChatPicker extends StatefulWidget {
  const _ChatPicker({required this.chats, required this.selected, this.scroll});

  final List<ConversationSummary> chats;
  final Set<String> selected;
  final ScrollController? scroll;

  @override
  State<_ChatPicker> createState() => _ChatPickerState();
}

class _ChatPickerState extends State<_ChatPicker> {
  late final Set<String> _selected = {...widget.selected};

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: widget.chats.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      tr('No conversations yet'),
                      style: TextStyle(fontSize: 15, color: c.muted),
                    ),
                  )
                : ListView(
                    controller: widget.scroll,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                    children: [
                      for (final chat in widget.chats)
                        _ChatCheckRow(
                          chat: chat,
                          checked: _selected.contains(chat.id),
                          onToggle: () => setState(() {
                            if (!_selected.remove(chat.id)) {
                              _selected.add(chat.id);
                            }
                          }),
                        ),
                    ],
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: WeCordButton(
              key: const ValueKey('chat-picker-done'),
              label: _selected.isEmpty
                  ? tr('Done')
                  : tr('Done · {count}', {'count': _selected.length}),
              size: WeCordButtonSize.large,
              expand: true,
              onPressed: () => Navigator.of(context).pop(_selected),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatCheckRow extends StatelessWidget {
  const _ChatCheckRow({
    required this.chat,
    required this.checked,
    required this.onToggle,
  });

  final ConversationSummary chat;
  final bool checked;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final title = chatFolderChatTitle(chat);
    return WeCordPressable(
      key: ValueKey('chat-pick-${chat.id}'),
      toggled: checked,
      semanticLabel: title,
      excludeSemantics: true,
      onPressed: onToggle,
      pressedScale: 0.98,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      builder: (context, states) {
        final hovered = states.contains(WidgetState.hovered);
        final background = hovered ? c.raised : c.panel;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(WeCordRadii.lg),
          ),
          child: Row(
            children: [
              ResolvedAvatar(
                name: title,
                avatarUrl: chat.avatarUrl,
                size: 40,
                squircle: chat.type == ConversationType.group,
                ringColor: background,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              CheckCircle(checked: checked),
            ],
          ),
        );
      },
    );
  }
}

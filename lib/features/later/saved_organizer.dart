import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/later/saved_filters.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/shared/l10n/error_text.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Asks for a folder's name (a new one, or a new name for [initial]).
/// Null when cancelled.
Future<String?> promptFolderName(BuildContext context, {String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      initial: initial,
      title: initial.isEmpty ? tr('New folder') : tr('Rename'),
      hint: tr('Folder name'),
      maxLength: 40,
    ),
  );
}

/// Asks for a tag's new name ([initial] is the old one). Null when
/// cancelled; the name comes back tidied.
Future<String?> promptTagName(BuildContext context, {String initial = ''}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _NameDialog(
      initial: initial,
      title: tr('Rename tag'),
      hint: tr('Tag name'),
      maxLength: maxSavedTagLength,
      tidy: tidySavedTag,
    ),
  );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({
    required this.initial,
    required this.title,
    required this.hint,
    required this.maxLength,
    this.tidy,
  });

  final String initial;
  final String title;
  final String hint;
  final int maxLength;
  final String Function(String)? tidy;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _name = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final raw = _name.text.trim();
    final name = widget.tidy?.call(raw) ?? raw;
    if (name.isNotEmpty) {
      Navigator.of(context).pop(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        key: const ValueKey('saved-name-field'),
        controller: _name,
        autofocus: true,
        textInputAction: TextInputAction.done,
        inputFormatters: [LengthLimitingTextInputFormatter(widget.maxLength)],
        decoration: InputDecoration(hintText: widget.hint),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          key: const ValueKey('saved-name-save'),
          onPressed: _submit,
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}

/// Chooses a folder (or none) from the person's folders, with a chip to make
/// a new one.
class SavedFolderPicker extends ConsumerStatefulWidget {
  const SavedFolderPicker({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final String? selected;
  final ValueChanged<String?> onChanged;

  @override
  ConsumerState<SavedFolderPicker> createState() => _SavedFolderPickerState();
}

class _SavedFolderPickerState extends ConsumerState<SavedFolderPicker> {
  String? _problem;

  Future<void> _newFolder() async {
    final name = await promptFolderName(context);
    if (name == null || !mounted) {
      return;
    }
    try {
      final id = await ref
          .read(savedMessagesRepositoryProvider)
          .createFolder(name);
      ref.invalidate(savedFoldersProvider);
      await ref.read(savedFoldersProvider.future);
      if (mounted) {
        setState(() => _problem = null);
        widget.onChanged(id);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _problem = errorText(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final folders = ref.watch(savedFoldersProvider).value ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            WeCordChip(
              key: const ValueKey('saved-pick-folder-none'),
              label: tr('No folder'),
              selected: widget.selected == null,
              onPressed: () => widget.onChanged(null),
            ),
            for (final folder in folders)
              WeCordChip(
                key: ValueKey('saved-pick-folder-${folder.id}'),
                label: folder.name,
                icon: Icons.folder_outlined,
                selected: widget.selected == folder.id,
                onPressed: () => widget.onChanged(folder.id),
              ),
            WeCordChip(
              key: const ValueKey('saved-pick-folder-new'),
              label: tr('New folder'),
              icon: Icons.add_rounded,
              onPressed: () => unawaited(_newFolder()),
            ),
          ],
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              _problem!,
              style: TextStyle(fontSize: 13, color: c.dangerText),
            ),
          ),
      ],
    );
  }
}

/// The tags of one entry: the ones it has (tap to take one off), a field to
/// add one, and the person's other tags as suggestions.
class SavedTagsEditor extends ConsumerStatefulWidget {
  const SavedTagsEditor({
    required this.tags,
    required this.onChanged,
    super.key,
  });

  final List<String> tags;
  final ValueChanged<List<String>> onChanged;

  @override
  ConsumerState<SavedTagsEditor> createState() => _SavedTagsEditorState();
}

class _SavedTagsEditorState extends ConsumerState<SavedTagsEditor> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  bool _has(String tag) =>
      widget.tags.any((t) => t.toLowerCase() == tag.toLowerCase());

  void _add(String raw) {
    final next = [...widget.tags];
    for (final part in raw.split(RegExp('[,，、\n]'))) {
      final tag = tidySavedTag(part);
      if (tag.isEmpty ||
          next.any((t) => t.toLowerCase() == tag.toLowerCase()) ||
          next.length >= maxSavedTags) {
        continue;
      }
      next.add(tag);
    }
    if (next.length != widget.tags.length) {
      widget.onChanged(next);
    }
    _input.clear();
  }

  void _remove(String tag) {
    widget.onChanged([
      for (final t in widget.tags)
        if (t != tag) t,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final known = tagCounts(
      ref.watch(savedMessagesProvider).value ?? const <SavedMessage>[],
    );
    final suggestions = [
      for (final entry in known)
        if (!_has(entry.tag)) entry.tag,
    ].take(8).toList();
    final full = widget.tags.length >= maxSavedTags;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.tags.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in widget.tags)
                  WeCordChip(
                    key: ValueKey('saved-tag-chip-$tag'),
                    label: '#$tag',
                    selected: true,
                    trailing: Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: c.onInk,
                    ),
                    semanticLabel: tr('Remove tag {tag}', {'tag': tag}),
                    onPressed: () => _remove(tag),
                  ),
              ],
            ),
          ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: WeCordTextField(
                fieldKey: const ValueKey('saved-tag-field'),
                controller: _input,
                hint: full
                    ? tr('Up to {count} tags', {'count': maxSavedTags})
                    : tr('Add a tag'),
                enabled: !full,
                textInputAction: TextInputAction.done,
                inputFormatters: [LengthLimitingTextInputFormatter(60)],
                onSubmitted: _add,
              ),
            ),
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: WeCordIconButton(
                key: const ValueKey('saved-tag-add'),
                icon: Icons.add_rounded,
                tooltip: tr('Add tag'),
                variant: WeCordButtonVariant.secondary,
                onPressed: full ? null : () => _add(_input.text),
              ),
            ),
          ],
        ),
        if (suggestions.isNotEmpty && !full)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tag in suggestions)
                  WeCordChip(
                    key: ValueKey('saved-tag-suggest-$tag'),
                    label: '#$tag',
                    height: 30,
                    onPressed: () => _add(tag),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// The frame of a form sheet: a scrolling body, then the action (and an
/// error) that stay in reach above the keyboard.
class SavedSheetFrame extends StatelessWidget {
  const SavedSheetFrame({
    required this.scroll,
    required this.children,
    required this.actionKey,
    required this.actionLabel,
    required this.onAction,
    required this.busy,
    this.error,
    this.actionEnabled = true,
    super.key,
  });

  final ScrollController? scroll;
  final List<Widget> children;
  final Key actionKey;
  final String actionLabel;
  final VoidCallback onAction;
  final bool busy;
  final bool actionEnabled;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Expanded(
              child: ListView(
                controller: scroll,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                children: children,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          error!,
                          key: const ValueKey('saved-sheet-error'),
                          style: TextStyle(fontSize: 13.5, color: c.dangerText),
                        ),
                      ),
                    ),
                  WeCordButton(
                    key: actionKey,
                    label: actionLabel,
                    size: WeCordButtonSize.large,
                    expand: true,
                    loading: busy,
                    onPressed: actionEnabled && !busy ? onAction : null,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small heading above a part of a form.
class SavedFormLabel extends StatelessWidget {
  const SavedFormLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: context.tokens.colors.muted,
          ),
        ),
      ),
    );
  }
}

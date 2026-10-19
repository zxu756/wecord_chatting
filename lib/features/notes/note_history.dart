import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/notes/note_block_views.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/note_table.dart';
import 'package:wecord/features/notes/note_table_view.dart';
import 'package:wecord/features/notes/note_text_controller.dart';
import 'package:wecord/features/notes/note_text_ops.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Shows a note's version history: snapshots taken while people worked and
/// on demand, each viewable and restorable by editors. A restore brings the
/// snapshot back for everyone and keeps what it replaced as a version.
Future<void> showNoteHistory(
  BuildContext context, {
  required String noteId,
  required bool canEdit,
  required VoidCallback onRestored,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Version history'),
    detents: const [0.5, 0.9],
    initialDetent: 0.9,
    builder: (context, scrollController) => NoteHistory(
      noteId: noteId,
      canEdit: canEdit,
      scrollController: scrollController,
      onRestored: onRestored,
    ),
  );
}

final noteVersionsProvider = FutureProvider.autoDispose
    .family<List<NoteVersionSummary>, String>((ref, noteId) {
      return ref.watch(notesRepositoryProvider).listVersions(noteId);
    });

final noteVersionProvider = FutureProvider.autoDispose
    .family<NoteVersion, String>((ref, versionId) {
      return ref.watch(notesRepositoryProvider).getVersion(versionId);
    });

class NoteHistory extends ConsumerStatefulWidget {
  const NoteHistory({
    required this.noteId,
    required this.canEdit,
    required this.onRestored,
    this.scrollController,
    super.key,
  });

  final String noteId;
  final bool canEdit;
  final VoidCallback onRestored;
  final ScrollController? scrollController;

  @override
  ConsumerState<NoteHistory> createState() => _NoteHistoryState();
}

class _NoteHistoryState extends ConsumerState<NoteHistory> {
  NoteVersionSummary? _selected;
  var _busy = false;

  Future<void> _saveVersion() async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Save a version')),
        content: SizedBox(
          width: 380,
          child: WeCordTextField(
            controller: controller,
            label: tr('Name (optional)'),
            hint: tr('Before the rewrite'),
            autofocus: true,
            maxLength: 120,
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
    controller.dispose();
    if (label == null || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref
          .read(notesRepositoryProvider)
          .createVersion(widget.noteId, label: label.trim());
      ref.invalidate(noteVersionsProvider(widget.noteId));
    } on Object {
      _toast(tr('Could not save a version.'));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _restore(NoteVersionSummary version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Restore this version?')),
        content: Text(
          tr(
            'The note goes back to how it was. What is there now is kept as '
            'a version, so you can come back to it.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Restore')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(notesRepositoryProvider).restoreVersion(version.id);
      ref.invalidate(noteVersionsProvider(widget.noteId));
      widget.onRestored();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } on Object {
      _toast(tr('Could not restore this version.'));
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _toast(String message) {
    if (mounted) {
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    if (selected != null) {
      return _VersionPreview(
        version: selected,
        canRestore: widget.canEdit && !_busy,
        scrollController: widget.scrollController,
        onBack: () => setState(() => _selected = null),
        onRestore: () => unawaited(_restore(selected)),
      );
    }
    final c = context.tokens.colors;
    final versions = ref.watch(noteVersionsProvider(widget.noteId));
    return Column(
      children: [
        if (widget.canEdit)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: WeCordButton(
                label: tr('Save a version now'),
                icon: Icons.bookmark_add_outlined,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.small,
                onPressed: _busy ? null : () => unawaited(_saveVersion()),
              ),
            ),
          ),
        Expanded(
          child: versions.when(
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            error: (error, stackTrace) => Center(
              child: Text(
                tr('Could not load the history.'),
                style: TextStyle(color: c.dangerText),
              ),
            ),
            data: (items) => items.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        tr(
                          'No versions yet. They are saved while people edit, '
                          'and you can save one yourself.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: c.muted, height: 1.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    controller: widget.scrollController,
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                    itemCount: items.length,
                    itemBuilder: (context, index) => _VersionRow(
                      version: items[index],
                      onTap: () => setState(() => _selected = items[index]),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

String versionTitle(NoteVersionSummary version) {
  final label = version.label?.trim();
  if (label != null && label.isNotEmpty) {
    return label;
  }
  return switch (version.kind) {
    'manual' => tr('Saved version'),
    'restore' => tr('Before a restore'),
    _ => tr('Autosave'),
  };
}

class _VersionRow extends StatelessWidget {
  const _VersionRow({required this.version, required this.onTap});

  final NoteVersionSummary version;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final when = MaterialLocalizations.of(context);
    final local = version.createdAt.toLocal();
    final time =
        '${when.formatShortDate(local)} '
        '${when.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
    final by = version.createdByName;
    return WeCordPressable(
      onPressed: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.lg),
      ),
      pressedScale: 0.99,
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 56),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: states.contains(WidgetState.hovered)
              ? c.raised
              : Colors.transparent,
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: c.raised,
                borderRadius: BorderRadius.circular(WeCordRadii.md),
              ),
              child: Icon(
                version.kind == 'manual'
                    ? Icons.bookmark_outline_rounded
                    : Icons.history_rounded,
                size: 20,
                color: c.muted,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    versionTitle(version),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: c.ink,
                    ),
                  ),
                  Text(
                    by == null || by.isEmpty ? time : '$time · $by',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: c.faint),
          ],
        ),
      ),
    );
  }
}

class _VersionPreview extends ConsumerWidget {
  const _VersionPreview({
    required this.version,
    required this.canRestore,
    required this.onBack,
    required this.onRestore,
    this.scrollController,
  });

  final NoteVersionSummary version;
  final bool canRestore;
  final VoidCallback onBack;
  final VoidCallback onRestore;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.tokens.colors;
    final content = ref.watch(noteVersionProvider(version.id));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 16, 8),
          child: Row(
            children: [
              WeCordIconButton(
                icon: Icons.chevron_left_rounded,
                iconSize: 24,
                tooltip: tr('Back to versions'),
                variant: WeCordButtonVariant.ghost,
                onPressed: onBack,
              ),
              Expanded(
                child: Text(
                  versionTitle(version),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
              ),
              if (canRestore)
                WeCordButton(
                  label: tr('Restore'),
                  size: WeCordButtonSize.small,
                  onPressed: onRestore,
                ),
            ],
          ),
        ),
        Expanded(
          child: content.when(
            loading: () => const Center(
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            error: (error, stackTrace) => Center(
              child: Text(
                tr('Could not load this version.'),
                style: TextStyle(color: c.dangerText),
              ),
            ),
            data: (data) => ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
              children: [
                Text(
                  '${data.icon} ${data.title.isEmpty ? tr('Untitled') : data.title}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 12),
                NoteBlocksPreview(blocks: data.blocks),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Blocks drawn read only, without any editing machinery.
class NoteBlocksPreview extends StatelessWidget {
  const NoteBlocksPreview({
    required this.blocks,
    this.imageBuilder,
    this.onOpenLink,
    super.key,
  });

  /// Makes links tappable (the page on the web); without it they are only
  /// drawn.
  final void Function(String url)? onOpenLink;

  final List<NoteBlock> blocks;

  /// Draws a picture block; without it a picture is a gray line with its
  /// name (a version in the history does not load the files).
  final Widget Function(BuildContext context, NoteBlock block)? imageBuilder;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final numbers = listNumbers(blocks);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, block) in blocks.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: switch (block.kind) {
              NoteBlockKind.divider => Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, color: c.line),
              ),
              NoteBlockKind.table => NoteTableReadOnly(
                table: NoteTable.fromProps(block.props),
              ),
              NoteBlockKind.image when imageBuilder != null => imageBuilder!(
                context,
                block,
              ),
              NoteBlockKind.image => Container(
                height: 64,
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(WeCordRadii.md),
                ),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, color: c.muted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${block.props['name'] ?? tr('Picture')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.muted),
                      ),
                    ),
                  ],
                ),
              ),
              _ => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (block.kind == NoteBlockKind.bullet)
                    const SizedBox(width: 20, child: Text('•')),
                  if (block.kind == NoteBlockKind.numbered)
                    SizedBox(width: 28, child: Text('${numbers[index]}.')),
                  if (block.kind == NoteBlockKind.todo)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, top: 3),
                      child: Icon(
                        block.checked
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: block.checked ? c.success : c.faint,
                      ),
                    ),
                  Expanded(
                    child: Container(
                      padding: block.kind == NoteBlockKind.code
                          ? const EdgeInsets.all(10)
                          : block.kind == NoteBlockKind.quote
                          ? const EdgeInsets.only(left: 12)
                          : EdgeInsets.zero,
                      decoration: BoxDecoration(
                        color: block.kind == NoteBlockKind.code
                            ? c.raised
                            : null,
                        borderRadius: BorderRadius.circular(WeCordRadii.sm),
                        border: block.kind == NoteBlockKind.quote
                            ? Border(
                                left: BorderSide(color: c.accent, width: 3),
                              )
                            : null,
                      ),
                      child: NoteLinkedText(
                        text: block.text,
                        marks: block.marks,
                        style: noteTextStyle(context, block),
                        onOpenLink: onOpenLink,
                      ),
                    ),
                  ),
                ],
              ),
            },
          ),
      ],
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_audit_log_screen.dart'
    show formatAuditTime;
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_models.dart';
import 'package:wecord/features/circles/mod_tools/mod_tools_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the moderators' notes and warnings about one member.
void openModNotes(
  BuildContext context, {
  required String circleId,
  required String userId,
  required String name,
  DateTime Function()? now,
}) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => ModNotesScreen(
        circleId: circleId,
        userId: userId,
        name: name,
        now: now,
      ),
    ),
  );
}

/// What moderators wrote down about a member: notes, and warnings that add
/// up. Only people who can time members out see it; the member is not told.
class ModNotesScreen extends ConsumerStatefulWidget {
  const ModNotesScreen({
    required this.circleId,
    required this.userId,
    required this.name,
    this.now,
    super.key,
  });

  final String circleId;
  final String userId;
  final String name;
  final DateTime Function()? now;

  @override
  ConsumerState<ModNotesScreen> createState() => _ModNotesScreenState();
}

class _ModNotesScreenState extends ConsumerState<ModNotesScreen> {
  final _body = TextEditingController();
  var _kind = ModNoteKind.note;
  var _saving = false;

  ModNotesKey get _key => (circleId: widget.circleId, userId: widget.userId);

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _body.text.trim();
    if (text.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _saving = true);
    try {
      await ref
          .read(modToolsRepositoryProvider)
          .addNote(widget.circleId, widget.userId, _kind, text);
      _body.clear();
      ref.invalidate(modNotesProvider(_key));
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            _kind == ModNoteKind.warning
                ? tr('Warning added.')
                : tr('Note added.'),
          ),
        ),
      );
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not save this. Try again.'))),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete(ModNote note) async {
    final confirmed = await confirmCircleAction(
      context,
      title: note.kind == ModNoteKind.warning
          ? tr('Delete this warning?')
          : tr('Delete this note?'),
      confirmLabel: tr('Delete'),
    );
    if (!confirmed || !mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await ref.read(modToolsRepositoryProvider).deleteNote(note.id);
      ref.invalidate(modNotesProvider(_key));
    } on Object {
      messenger?.showSnackBar(
        SnackBar(content: Text(tr('Could not delete this. Try again.'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final notes = ref.watch(modNotesProvider(_key));
    final now = (widget.now ?? DateTime.now)();
    return CirclePageScaffold(
      title: tr('Notes'),
      subtitle: widget.name,
      body: ListView(
        padding: circlePagePadding(context),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
            child: Text(
              tr(
                'Only moderators see notes and warnings. {name} is not told.',
                {'name': widget.name},
              ),
              style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
            ),
          ),
          CircleCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                WeCordSegmented<ModNoteKind>(
                  expand: true,
                  semanticLabel: tr('Type'),
                  selected: _kind,
                  onChanged: (kind) => setState(() => _kind = kind),
                  segments: [
                    WeCordSegment(
                      key: const ValueKey('mod-note-kind-note'),
                      value: ModNoteKind.note,
                      label: tr('Note'),
                    ),
                    WeCordSegment(
                      key: const ValueKey('mod-note-kind-warning'),
                      value: ModNoteKind.warning,
                      label: tr('Warning'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                WeCordTextField(
                  fieldKey: const ValueKey('mod-note-body'),
                  controller: _body,
                  minLines: 2,
                  maxLines: 5,
                  inputFormatters: [LengthLimitingTextInputFormatter(1000)],
                  hint: _kind == ModNoteKind.warning
                      ? tr('What was the warning for?')
                      : tr('Write a note for the other moderators'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: WeCordButton(
                    key: const ValueKey('mod-note-add'),
                    label: _kind == ModNoteKind.warning
                        ? tr('Add warning')
                        : tr('Add note'),
                    size: WeCordButtonSize.small,
                    loading: _saving,
                    onPressed: _saving || _body.text.trim().isEmpty
                        ? null
                        : () => unawaited(_add()),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          notes.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, stackTrace) => CircleEmptyState(
              icon: Icons.error_outline,
              title: tr('Could not load the notes.'),
              action: WeCordButton(
                label: tr('Try again'),
                onPressed: () => ref.invalidate(modNotesProvider(_key)),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tr('No notes yet.'),
                    key: const ValueKey('mod-notes-empty'),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: c.muted),
                  ),
                );
              }
              final warnings = items
                  .where((note) => note.kind == ModNoteKind.warning)
                  .length;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    child: Semantics(
                      header: true,
                      child: Text(
                        warnings == 0
                            ? tr('Notes')
                            : warnings == 1
                            ? tr('Notes · 1 warning')
                            : tr('Notes · {count} warnings', {
                                'count': warnings,
                              }),
                        key: const ValueKey('mod-notes-header'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                          color: c.ink,
                        ),
                      ),
                    ),
                  ),
                  for (final note in items) ...[
                    _NoteCard(
                      key: ValueKey('mod-note-${note.id}'),
                      note: note,
                      now: now,
                      onDelete: note.canDelete
                          ? () => unawaited(_delete(note))
                          : null,
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({
    required this.note,
    required this.now,
    required this.onDelete,
    super.key,
  });

  final ModNote note;
  final DateTime now;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final warning = note.kind == ModNoteKind.warning;
    final author = note.authorName;
    final when = formatAuditTime(note.createdAt, now: now);
    return CircleCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              warning
                  ? Icons.warning_amber_rounded
                  : Icons.sticky_note_2_outlined,
              size: 20,
              color: warning ? c.warningText : c.muted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  [
                    warning ? tr('Warning') : tr('Note'),
                    if (author != null && author.isNotEmpty) author,
                    when,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: warning ? c.warningText : c.subtle,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  note.body,
                  style: TextStyle(fontSize: 15, height: 1.4, color: c.ink),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              key: ValueKey('mod-note-delete-${note.id}'),
              tooltip: warning ? tr('Delete warning') : tr('Delete note'),
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, size: 20, color: c.muted),
            ),
        ],
      ),
    );
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes2_models.dart';
import 'package:wecord/features/notes/notes2_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

NoteTemplateBlock _block(
  NoteBlockKind kind, [
  String text = '',
  Map<String, Object?> props = const {},
]) => NoteTemplateBlock(kind: kind, text: text, props: props);

Map<String, Object?> _table(List<List<String>> rows) => {
  'header': true,
  'cols': [for (var c = 0; c < rows.first.length; c++) 'c${c + 1}'],
  'rows': [
    for (final (r, row) in rows.indexed)
      {
        'id': 'r${r + 1}',
        'c': {
          for (final (c, cell) in row.indexed)
            if (cell.isNotEmpty) 'c${c + 1}': cell,
        },
      },
  ],
};

/// The templates that come with the app, in the person's language: meeting
/// notes, a weekly report and a trip plan.
List<NoteTemplate> builtInNoteTemplates() {
  const h2 = NoteBlockKind.heading2;
  const text = NoteBlockKind.paragraph;
  const bullet = NoteBlockKind.bullet;
  const todo = NoteBlockKind.todo;
  const numbered = NoteBlockKind.numbered;
  return [
    NoteTemplate(
      name: tr('Meeting notes'),
      icon: '\u{1F4CB}',
      title: tr('Meeting notes'),
      blocks: [
        _block(h2, tr('Date and people')),
        _block(text, tr('Date:')),
        _block(text, tr('Attendees:')),
        _block(h2, tr('Agenda')),
        _block(numbered),
        _block(numbered),
        _block(h2, tr('Notes')),
        _block(text),
        _block(h2, tr('Decisions')),
        _block(bullet),
        _block(h2, tr('Action items')),
        _block(todo),
        _block(todo),
      ],
    ),
    NoteTemplate(
      name: tr('Weekly report'),
      icon: '\u{1F4C8}',
      title: tr('Weekly report'),
      blocks: [
        _block(h2, tr('Done this week')),
        _block(bullet),
        _block(h2, tr('Plan for next week')),
        _block(bullet),
        _block(h2, tr('Progress')),
        _block(
          NoteBlockKind.table,
          '',
          _table([
            [tr('Task'), tr('Status'), tr('Owner')],
            ['', '', ''],
            ['', '', ''],
          ]),
        ),
        _block(h2, tr('Blockers')),
        _block(bullet),
      ],
    ),
    NoteTemplate(
      name: tr('Trip plan'),
      icon: '\u{1F9F3}',
      title: tr('Trip plan'),
      blocks: [
        _block(h2, tr('Overview')),
        _block(text, tr('Where:')),
        _block(text, tr('When:')),
        _block(text, tr('Who is going:')),
        _block(h2, tr('Itinerary')),
        _block(
          NoteBlockKind.table,
          '',
          _table([
            [tr('Date'), tr('Plan'), tr('Notes')],
            ['', '', ''],
            ['', '', ''],
            ['', '', ''],
          ]),
        ),
        _block(h2, tr('Packing list')),
        _block(todo),
        _block(todo),
        _block(todo),
        _block(h2, tr('Budget')),
        _block(
          NoteBlockKind.table,
          '',
          _table([
            [tr('Item'), tr('Cost')],
            ['', ''],
            ['', ''],
          ]),
        ),
      ],
    ),
  ];
}

/// What the person chose for a new note: blank ([template] null) or a
/// template.
typedef NewNoteChoice = ({NoteTemplate? template});

/// My own templates, newest first.
final noteTemplatesProvider =
    FutureProvider.autoDispose<List<NoteTemplateSummary>>(
      (ref) => ref.watch(notes2RepositoryProvider).listTemplates(),
    );

/// Asks how a new note starts: blank, one of the templates that come with
/// the app, or one of the person's own. Null when the sheet is dismissed.
Future<NewNoteChoice?> showNewNoteSheet(BuildContext context) {
  return showWeCordSheet<NewNoteChoice>(
    context,
    title: tr('New note'),
    detents: const [0.6, 0.92],
    initialDetent: 0.6,
    builder: (context, scrollController) =>
        NewNoteSheet(scrollController: scrollController),
  );
}

class NewNoteSheet extends ConsumerStatefulWidget {
  const NewNoteSheet({this.scrollController, super.key});

  final ScrollController? scrollController;

  @override
  ConsumerState<NewNoteSheet> createState() => _NewNoteSheetState();
}

class _NewNoteSheetState extends ConsumerState<NewNoteSheet> {
  var _busy = false;

  Future<void> _usePersonal(NoteTemplateSummary summary) async {
    setState(() => _busy = true);
    try {
      final template = await ref
          .read(notes2RepositoryProvider)
          .getTemplate(summary.id);
      if (mounted) {
        Navigator.of(context).pop((template: template));
      }
    } on Object {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not open the template.'))),
        );
      }
    }
  }

  Future<void> _delete(NoteTemplateSummary summary) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this template?')),
        content: Text(tr('Notes made from it stay as they are.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    try {
      await ref.read(notes2RepositoryProvider).deleteTemplate(summary.id);
      ref.invalidate(noteTemplatesProvider);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(tr('Could not delete the template.'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final personal = ref.watch(noteTemplatesProvider);
    final builtIn = builtInNoteTemplates();

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: c.subtle,
          ),
        ),
      ),
    );

    Widget row({
      required Key key,
      required String icon,
      required String title,
      String? subtitle,
      required VoidCallback onTap,
      Widget? trailing,
    }) {
      return WeCordPressable(
        key: key,
        onPressed: _busy ? null : onTap,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WeCordRadii.lg),
        ),
        pressedScale: 0.99,
        builder: (context, states) => Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          constraints: const BoxConstraints(minHeight: 56),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.raised,
                  borderRadius: BorderRadius.circular(WeCordRadii.md),
                ),
                child: Text(icon, style: const TextStyle(fontSize: 21)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: c.ink,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
        ),
      );
    }

    return ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.only(bottom: 20),
      children: [
        row(
          key: const ValueKey('new-note-blank'),
          icon: NoteMeta.defaultIcon,
          title: tr('Blank note'),
          subtitle: tr('Start with an empty page'),
          onTap: () => Navigator.of(context).pop((template: null)),
        ),
        header(tr('Templates')),
        for (final (index, template) in builtIn.indexed)
          row(
            key: ValueKey('new-note-template-$index'),
            icon: template.icon,
            title: template.name,
            subtitle: tr('{count} blocks', {
              'count': '${template.blocks.length}',
            }),
            onTap: () => Navigator.of(context).pop((template: template)),
          ),
        ...personal.when(
          loading: () => const <Widget>[],
          error: (_, _) => const <Widget>[],
          data: (items) => [
            if (items.isNotEmpty) header(tr('My templates')),
            for (final item in items)
              row(
                key: ValueKey('new-note-mine-${item.id}'),
                icon: item.icon,
                title: item.name,
                subtitle: tr('{count} blocks', {'count': '${item.blockCount}'}),
                onTap: () => unawaited(_usePersonal(item)),
                trailing: WeCordIconButton(
                  icon: Icons.delete_outline_rounded,
                  tooltip: tr('Delete template'),
                  size: 36,
                  iconSize: 19,
                  variant: WeCordButtonVariant.ghost,
                  onPressed: () => unawaited(_delete(item)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// Asks for a name for a personal template; null when cancelled.
Future<String?> askTemplateName(
  BuildContext context, {
  required String initial,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (context) => _TemplateNameDialog(initial: initial),
  );
  final trimmed = name?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

class _TemplateNameDialog extends StatefulWidget {
  const _TemplateNameDialog({required this.initial});

  final String initial;

  @override
  State<_TemplateNameDialog> createState() => _TemplateNameDialogState();
}

class _TemplateNameDialogState extends State<_TemplateNameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr('Save as a template')),
      content: SizedBox(
        width: 380,
        child: WeCordTextField(
          controller: _controller,
          label: tr('Template name'),
          autofocus: true,
          maxLength: 80,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}

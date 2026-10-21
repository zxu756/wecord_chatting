import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wecord/features/circles/circle_ui.dart';
import 'package:wecord/features/knowledge_base/kb_models.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Asks for the title of a new page. Null when cancelled; an empty title is
/// allowed (the page is then "Untitled" until someone names it).
Future<String?> showNewKbPageDialog(
  BuildContext context, {
  String? parentTitle,
}) {
  return showCircleDialog<String>(
    context,
    builder: (context) => _NewPageDialog(parentTitle: parentTitle),
  );
}

class _NewPageDialog extends StatefulWidget {
  const _NewPageDialog({this.parentTitle});

  final String? parentTitle;

  @override
  State<_NewPageDialog> createState() => _NewPageDialogState();
}

class _NewPageDialogState extends State<_NewPageDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _create() => Navigator.of(context).pop(_controller.text.trim());

  @override
  Widget build(BuildContext context) {
    final parent = widget.parentTitle;
    return CircleDialog(
      title: parent == null ? tr('New page') : tr('New page inside'),
      message: parent == null
          ? null
          : (parent.trim().isEmpty ? tr('Untitled') : parent),
      content: WeCordTextField(
        fieldKey: const ValueKey('kb-new-page-title'),
        controller: _controller,
        autofocus: true,
        maxLength: KnowledgeBaseLimits.titleLength,
        label: tr('Title'),
        hint: tr('Untitled'),
        textInputAction: TextInputAction.done,
        inputFormatters: [
          LengthLimitingTextInputFormatter(KnowledgeBaseLimits.titleLength),
        ],
        onSubmitted: (_) => _create(),
      ),
      actions: [
        CircleDialogAction(
          label: tr('Cancel'),
          onPressed: () => Navigator.of(context).pop(),
        ),
        CircleDialogAction.primary(
          key: const ValueKey('kb-new-page-create'),
          label: tr('Create'),
          onPressed: _create,
        ),
      ],
    );
  }
}

/// Where a page goes: a parent, or the top level (null).
class KbMoveChoice {
  const KbMoveChoice(this.parentId);

  final String? parentId;
}

/// Lists the places [page] can go: the top level and every page that is not
/// inside it and leaves room (pages nest [KnowledgeBaseLimits.depth] levels).
Future<KbMoveChoice?> showKbMoveSheet(
  BuildContext context, {
  required KbTree tree,
  required KbPage page,
}) {
  final inside = tree.subtreeOf(page.id);
  final height = tree.heightBelow(page.id);
  final rows = [
    for (final row in tree.rows())
      if (!inside.contains(row.page.id) &&
          row.depth + 1 + height <= KnowledgeBaseLimits.depth)
        row,
  ];
  return showWeCordSheet<KbMoveChoice>(
    context,
    title: tr('Move to'),
    detents: const [0.6, 0.92],
    builder: (sheetContext, controller) {
      final c = sheetContext.tokens.colors;
      return ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Text(
              page.title.trim().isEmpty ? tr('Untitled') : page.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 14, color: c.muted),
            ),
          ),
          SettingsGroup(
            color: c.well,
            children: [
              SettingsRow(
                key: const ValueKey('kb-move-top'),
                icon: Icons.vertical_align_top_rounded,
                title: tr('Top level'),
                value: page.parentId == null ? tr('Here now') : null,
                showChevron: false,
                onTap: () =>
                    Navigator.of(sheetContext).pop(const KbMoveChoice(null)),
              ),
              for (final row in rows)
                _MoveRow(
                  row: row,
                  current: row.page.id == page.parentId,
                  onTap: () =>
                      Navigator.of(sheetContext).pop(KbMoveChoice(row.page.id)),
                ),
            ],
          ),
        ],
      );
    },
  );
}

class _MoveRow extends StatelessWidget {
  const _MoveRow({
    required this.row,
    required this.current,
    required this.onTap,
  });

  final KbRow row;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final title = row.page.title.trim().isEmpty
        ? tr('Untitled')
        : row.page.title;
    return WeCordPressable(
      key: ValueKey('kb-move-${row.page.id}'),
      onPressed: onTap,
      shape: const RoundedRectangleBorder(),
      pressedScale: 1,
      semanticLabel: current
          ? tr('{title}, here now', {'title': title})
          : title,
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: EdgeInsets.fromLTRB(16.0 + (row.depth - 1) * 18, 6, 16, 6),
        color: states.contains(WidgetState.hovered)
            ? c.raised
            : Colors.transparent,
        child: Row(
          children: [
            Text(row.page.icon, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.ink,
                ),
              ),
            ),
            if (current)
              Icon(Icons.check_rounded, size: 18, color: c.accentText),
          ],
        ),
      ),
    );
  }
}

/// Lists every page of the tree and hands back the one picked (the page a
/// newcomer task asks to read).
Future<KbPage?> showKbPagePicker(BuildContext context, {required KbTree tree}) {
  final rows = tree.rows();
  return showWeCordSheet<KbPage>(
    context,
    title: tr('Choose a page'),
    detents: const [0.6, 0.92],
    builder: (sheetContext, controller) {
      return ListView(
        controller: controller,
        padding: EdgeInsets.fromLTRB(
          16,
          4,
          16,
          16 + MediaQuery.paddingOf(sheetContext).bottom,
        ),
        children: [
          SettingsGroup(
            color: sheetContext.tokens.colors.well,
            children: [
              for (final row in rows)
                _MoveRow(
                  row: row,
                  current: false,
                  onTap: () => Navigator.of(sheetContext).pop(row.page),
                ),
            ],
          ),
        ],
      );
    },
  );
}

/// What the access sheet hands back.
class KbAccessChoice {
  const KbAccessChoice({required this.viewRoleIds, required this.editRoleIds});

  final List<String> viewRoleIds;
  final List<String> editRoleIds;
}

/// Who may read and who may edit [pageTitle]: everyone, or some roles. A
/// [KbPageAccess.locked] page can be looked at, not changed.
Future<KbAccessChoice?> showKbAccessSheet(
  BuildContext context, {
  required String pageTitle,
  required KbPageAccess access,
}) {
  return showWeCordSheet<KbAccessChoice>(
    context,
    title: tr('Who can read and edit'),
    detents: const [0.75, 0.95],
    builder: (sheetContext, controller) => _AccessSheet(
      controller: controller,
      pageTitle: pageTitle,
      access: access,
    ),
  );
}

class _AccessSheet extends StatefulWidget {
  const _AccessSheet({
    required this.controller,
    required this.pageTitle,
    required this.access,
  });

  final ScrollController? controller;
  final String pageTitle;
  final KbPageAccess access;

  @override
  State<_AccessSheet> createState() => _AccessSheetState();
}

class _AccessSheetState extends State<_AccessSheet> {
  late final Set<String> _view = {...widget.access.viewRoleIds};
  late final Set<String> _edit = {...widget.access.editRoleIds};
  late bool _limitView = widget.access.viewRoleIds.isNotEmpty;
  late bool _extraEditors = widget.access.editRoleIds.isNotEmpty;

  bool get _locked => widget.access.locked;

  bool get _valid =>
      (!_limitView || _view.isNotEmpty) && (!_extraEditors || _edit.isNotEmpty);

  void _save() {
    Navigator.of(context).pop(
      KbAccessChoice(
        viewRoleIds: _limitView ? _view.toList() : const [],
        editRoleIds: _extraEditors ? _edit.toList() : const [],
      ),
    );
  }

  Widget _roles(Set<String> picked, String keyPrefix) {
    final c = context.tokens.colors;
    final roles = widget.access.roles;
    if (roles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Text(
          tr('This circle has no roles yet. Create one in the roles page.'),
          style: TextStyle(fontSize: 13.5, color: c.muted, height: 1.4),
        ),
      );
    }
    return SettingsGroup(
      color: c.well,
      children: [
        for (final role in roles)
          SettingsRow.toggle(
            key: ValueKey('$keyPrefix-${role.id}'),
            title: role.name,
            value: picked.contains(role.id),
            onChanged: _locked
                ? null
                : (on) => setState(() {
                    if (on) {
                      if (picked.length < KnowledgeBaseLimits.rolesPerSetting) {
                        picked.add(role.id);
                      }
                    } else {
                      picked.remove(role.id);
                    }
                  }),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListView(
      controller: widget.controller,
      padding: EdgeInsets.fromLTRB(
        16,
        4,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
          child: Text(
            widget.pageTitle.trim().isEmpty ? tr('Untitled') : widget.pageTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 14, color: c.muted),
          ),
        ),
        if (_locked) ...[
          Container(
            key: const ValueKey('kb-access-locked'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.warningSoft,
              borderRadius: BorderRadius.circular(WeCordRadii.lg),
            ),
            child: Text(
              tr(
                'A higher role limited this page. You can look at the '
                'settings, but not change them.',
              ),
              style: TextStyle(
                fontSize: 13.5,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: c.warningText,
              ),
            ),
          ),
          const SizedBox(height: 14),
        ],
        _sectionTitle(tr('Who can read')),
        SettingsGroup(
          color: c.well,
          children: [
            _ChoiceRow(
              key: const ValueKey('kb-view-everyone'),
              title: tr('Everyone in the circle'),
              selected: !_limitView,
              onTap: _locked ? null : () => setState(() => _limitView = false),
            ),
            _ChoiceRow(
              key: const ValueKey('kb-view-roles'),
              title: tr('Only some roles'),
              selected: _limitView,
              onTap: _locked ? null : () => setState(() => _limitView = true),
            ),
          ],
        ),
        if (_limitView) ...[
          const SizedBox(height: 12),
          _roles(_view, 'kb-view-role'),
        ],
        const SizedBox(height: 18),
        _sectionTitle(tr('Who can edit')),
        SettingsGroup(
          color: c.well,
          children: [
            _ChoiceRow(
              key: const ValueKey('kb-edit-managers'),
              title: tr('Only people who manage channels'),
              selected: !_extraEditors,
              onTap: _locked
                  ? null
                  : () => setState(() => _extraEditors = false),
            ),
            _ChoiceRow(
              key: const ValueKey('kb-edit-roles'),
              title: tr('Also some roles'),
              selected: _extraEditors,
              onTap: _locked
                  ? null
                  : () => setState(() => _extraEditors = true),
            ),
          ],
        ),
        if (_extraEditors) ...[
          const SizedBox(height: 12),
          _roles(_edit, 'kb-edit-role'),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 18),
          child: Text(
            tr(
              'People who manage channels can always read and edit. The pages '
              'inside follow the same limits. Whoever edits a page can add '
              'pages inside it.',
            ),
            style: TextStyle(fontSize: 13, height: 1.4, color: c.muted),
          ),
        ),
        WeCordButton(
          key: const ValueKey('kb-access-save'),
          label: tr('Save'),
          size: WeCordButtonSize.large,
          expand: true,
          onPressed: _locked || !_valid ? null : _save,
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    final c = context.tokens.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Semantics(
        header: true,
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: c.subtle,
          ),
        ),
      ),
    );
  }
}

/// One of a few choices, with a check on the one that is picked.
class _ChoiceRow extends StatelessWidget {
  const _ChoiceRow({
    required this.title,
    required this.selected,
    required this.onTap,
    super.key,
  });

  final String title;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return Semantics(
      selected: selected,
      inMutuallyExclusiveGroup: true,
      child: SettingsRow(
        title: title,
        onTap: onTap,
        showChevron: false,
        trailing: selected
            ? Icon(Icons.check_rounded, size: 20, color: c.accentText)
            : null,
      ),
    );
  }
}

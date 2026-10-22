import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds_registrations.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/features/group_tabs/group_tabs_repository.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Opens the list of a chat's tabs: everybody can open one; the people who
/// may change them can also add, rename, reorder and remove.
Future<void> showGroupTabsSheet(
  BuildContext context, {
  required String conversationId,
  required String title,
  String? circleId,
  bool canSend = true,
}) {
  return showWeCordSheet<void>(
    context,
    title: tr('Tabs'),
    detents: const [0.6, 0.92],
    builder: (context, scrollController) => GroupTabsSheet(
      conversationId: conversationId,
      chatTitle: title,
      circleId: circleId,
      canSend: canSend,
      scrollController: scrollController,
    ),
  );
}

class GroupTabsSheet extends ConsumerStatefulWidget {
  const GroupTabsSheet({
    required this.conversationId,
    required this.chatTitle,
    this.circleId,
    this.canSend = true,
    this.scrollController,
    super.key,
  });

  final String conversationId;
  final String chatTitle;
  final String? circleId;
  final bool canSend;
  final ScrollController? scrollController;

  @override
  ConsumerState<GroupTabsSheet> createState() => _GroupTabsSheetState();
}

class _GroupTabsSheetState extends ConsumerState<GroupTabsSheet> {
  var _busy = false;

  GroupTabContext _ctx() => GroupTabContext(
    context: context,
    conversationId: widget.conversationId,
    title: widget.chatTitle,
    circleId: widget.circleId,
    canSend: widget.canSend,
  );

  void _snack(String text) {
    ScaffoldMessenger.maybeOf(
      context,
    )?.showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) {
      return;
    }
    setState(() => _busy = true);
    try {
      await action();
      refreshGroupTabs(ref, widget.conversationId);
    } on GroupTabException catch (error) {
      refreshGroupTabs(ref, widget.conversationId);
      if (mounted) {
        _snack(error.message);
      }
    } on Object {
      if (mounted) {
        _snack(tr("That didn't work. Try again."));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _add(GroupTabs tabs) async {
    final registry = ref.read(groupTabKindRegistryProvider);
    final kinds = [
      for (final kind in registry.addable(_ctx()))
        // A kind with no target (events, the knowledge base ...) goes in once.
        if (kind.pick != null || !tabs.tabs.any((tab) => tab.kind == kind.kind))
          kind,
    ];
    final chosen = await showWeCordSheet<GroupTabKindContribution>(
      context,
      title: tr('Add a tab'),
      builder: (context, _) => _KindList(kinds: kinds),
    );
    if (chosen == null || !mounted) {
      return;
    }
    GroupTabPick? pick;
    if (chosen.pick != null) {
      pick = await chosen.pick!(_ctx());
      if (pick == null || !mounted) {
        return;
      }
    }
    final title = pick?.title?.trim().isNotEmpty == true
        ? pick!.title
        : chosen.defaultTitle?.call();
    await _run(
      () async => ref
          .read(groupTabsRepositoryProvider)
          .add(
            widget.conversationId,
            kind: chosen.kind,
            target: pick?.target,
            title: title,
          ),
    );
  }

  Future<void> _rename(GroupTab tab) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: tab.title),
    );
    final clean = name?.trim();
    if (clean == null || clean.isEmpty || clean == tab.title || !mounted) {
      return;
    }
    await _run(
      () => ref.read(groupTabsRepositoryProvider).rename(tab.id, clean),
    );
  }

  Future<void> _move(List<GroupTab> tabs, int from, int to) async {
    if (to < 0 || to >= tabs.length || from == to) {
      return;
    }
    final ids = [for (final tab in tabs) tab.id];
    ids.insert(to, ids.removeAt(from));
    await _run(
      () => ref
          .read(groupTabsRepositoryProvider)
          .reorder(widget.conversationId, ids),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final async = ref.watch(groupTabsAllProvider(widget.conversationId));
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            tr("The tabs couldn't load. Try again."),
            style: TextStyle(fontSize: 15, color: c.muted),
          ),
        ),
      ),
      data: (data) {
        final registry = ref.watch(groupTabKindRegistryProvider);
        final tabs = data.tabs;
        final manage = data.canManage;
        final canAdd = manage && tabs.length < maxGroupTabs;
        return ListView(
          controller: widget.scrollController,
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            if (tabs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  manage
                      ? tr(
                          'No tabs yet. Pin a note, a list, a form or a link under the chat header.',
                        )
                      : tr('This chat has no tabs yet.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, height: 1.4, color: c.muted),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: c.well,
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                ),
                clipBehavior: Clip.antiAlias,
                child: ReorderableListView.builder(
                  key: const ValueKey('group-tabs-list'),
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: tabs.length,
                  onReorderItem: manage
                      ? (from, to) => unawaited(_move(tabs, from, to))
                      : (_, _) {},
                  itemBuilder: (context, index) {
                    final tab = tabs[index];
                    final kind = registry.kindOf(tab.kind);
                    return _TabRow(
                      key: ValueKey('group-tab-row-${tab.id}'),
                      tab: tab,
                      index: index,
                      count: tabs.length,
                      kind: kind,
                      manage: manage,
                      busy: _busy,
                      onOpen: kind == null || !tab.available
                          ? null
                          : () {
                              Navigator.of(context).pop();
                              kind.open(_ctx(), tab);
                            },
                      onRename: () => unawaited(_rename(tab)),
                      onRemove: () => unawaited(
                        _run(
                          () => ref
                              .read(groupTabsRepositoryProvider)
                              .remove(tab.id),
                        ),
                      ),
                      onMove: (delta) =>
                          unawaited(_move(tabs, index, index + delta)),
                    );
                  },
                ),
              ),
            if (manage) ...[
              const SizedBox(height: 14),
              WeCordButton(
                key: const ValueKey('group-tab-add'),
                label: tr('Add a tab'),
                icon: Icons.add_rounded,
                variant: WeCordButtonVariant.secondary,
                size: WeCordButtonSize.large,
                expand: true,
                onPressed: canAdd && !_busy
                    ? () => unawaited(_add(data))
                    : null,
              ),
              if (!canAdd)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    tr('A chat can have up to 12 tabs.'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: c.subtle),
                  ),
                ),
            ] else if (tabs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
                child: Text(
                  tr('Only admins can change the tabs.'),
                  style: TextStyle(fontSize: 12.5, color: c.subtle),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Asks for a tab's new name. Owns its text box, so closing the dialog
/// cannot pull it out from under the field while the dialog fades.
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
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
      title: Text(tr('Rename tab')),
      content: WeCordTextField(
        fieldKey: const ValueKey('group-tab-rename-field'),
        controller: _controller,
        maxLength: 40,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          key: const ValueKey('group-tab-rename-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(tr('Save')),
        ),
      ],
    );
  }
}

class _KindList extends StatelessWidget {
  const _KindList({required this.kinds});

  final List<GroupTabKindContribution> kinds;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      children: [
        if (kinds.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              tr('Everything that can be a tab here already is.'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.muted),
            ),
          )
        else
          SettingsGroup(
            color: c.well,
            children: [
              for (final kind in kinds)
                SettingsRow(
                  key: ValueKey('group-tab-kind-${kind.kind}'),
                  icon: kind.icon,
                  title: kind.label(),
                  onTap: () => Navigator.of(context).pop(kind),
                ),
            ],
          ),
      ],
    );
  }
}

class _TabRow extends StatelessWidget {
  const _TabRow({
    required this.tab,
    required this.index,
    required this.count,
    required this.kind,
    required this.manage,
    required this.busy,
    required this.onOpen,
    required this.onRename,
    required this.onRemove,
    required this.onMove,
    super.key,
  });

  final GroupTab tab;
  final int index;
  final int count;
  final GroupTabKindContribution? kind;
  final bool manage;
  final bool busy;
  final VoidCallback? onOpen;
  final VoidCallback onRename;
  final VoidCallback onRemove;
  final ValueChanged<int> onMove;

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final broken = !tab.available;
    final unknown = kind == null;
    final subtitle = broken
        ? tr('No longer available')
        : unknown
        ? tr('Needs a newer version of WeCord')
        : tab.closed
        ? tr('Closed')
        : kind!.label();
    return Semantics(
      customSemanticsActions: {
        if (manage && index > 0)
          CustomSemanticsAction(label: tr('Move up')): () => onMove(-1),
        if (manage && index < count - 1)
          CustomSemanticsAction(label: tr('Move down')): () => onMove(1),
      },
      child: Material(
        color: Colors.transparent,
        child: Row(
          children: [
            Expanded(
              child: SettingsRow(
                icon: kind?.icon ?? Icons.extension_outlined,
                title: tab.icon == null
                    ? tab.title
                    : '${tab.icon} ${tab.title}',
                subtitle: subtitle,
                showChevron: onOpen != null && !manage,
                onTap: onOpen,
              ),
            ),
            if (manage) ...[
              WeCordIconButton(
                key: ValueKey('group-tab-rename-${tab.id}'),
                tooltip: tr('Rename tab'),
                icon: Icons.edit_outlined,
                variant: WeCordButtonVariant.ghost,
                size: 40,
                iconSize: 19,
                onPressed: busy ? null : onRename,
              ),
              WeCordIconButton(
                key: ValueKey('group-tab-remove-${tab.id}'),
                tooltip: tr('Remove tab'),
                icon: Icons.close_rounded,
                variant: WeCordButtonVariant.ghost,
                size: 40,
                iconSize: 19,
                onPressed: busy ? null : onRemove,
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12, left: 4),
                  child: ExcludeSemantics(
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 22,
                      color: c.subtle,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

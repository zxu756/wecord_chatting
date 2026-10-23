import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds_registrations.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/features/group_tabs/group_tabs_repository.dart';
import 'package:wecord/features/group_tabs/group_tabs_sheet.dart';
import 'package:wecord/features/notes/note_models.dart' show NoteMeta;
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/shared/l10n/l10n.dart';
import 'package:wecord/shared/ui/ui.dart';

/// Whether a chat has tabs to show (the page hides the pinned-note banner
/// then: the note is the strip's first tab).
final groupTabsPresentProvider = Provider.autoDispose.family<bool, String>(
  (ref, conversationId) => ref.watch(
    groupTabsProvider(
      conversationId,
    ).select((async) => async.value?.tabs.any((tab) => tab.available) ?? false),
  ),
);

/// The row of tabs under the chat header. Folded by default into one slim line
/// ("Tabs 4"), so the header keeps its few main actions; opened, it is a
/// single row of chips that scrolls sideways. Shows nothing while the chat has
/// no tabs.
class GroupTabStrip extends ConsumerStatefulWidget {
  const GroupTabStrip({
    required this.conversationId,
    required this.title,
    this.circleId,
    this.pinnedNote,
    this.canSend = true,
    this.desktop = false,
    super.key,
  });

  final String conversationId;
  final String title;
  final String? circleId;

  /// The conversation's pinned note: it is the first tab while there are any.
  final NoteMeta? pinnedNote;
  final bool canSend;
  final bool desktop;

  /// Chats whose strip the person opened, for as long as the app runs.
  static final _expanded = <String>{};

  @visibleForTesting
  static void forgetExpanded() => _expanded.clear();

  @override
  ConsumerState<GroupTabStrip> createState() => _GroupTabStripState();
}

class _GroupTabStripState extends ConsumerState<GroupTabStrip> {
  bool get _open => GroupTabStrip._expanded.contains(widget.conversationId);

  void _toggle() {
    setState(() {
      if (_open) {
        GroupTabStrip._expanded.remove(widget.conversationId);
      } else {
        GroupTabStrip._expanded.add(widget.conversationId);
      }
    });
  }

  GroupTabContext _ctx() => GroupTabContext(
    context: context,
    conversationId: widget.conversationId,
    title: widget.title,
    circleId: widget.circleId,
    canSend: widget.canSend,
  );

  @override
  Widget build(BuildContext context) {
    final c = context.tokens.colors;
    final tabs = ref.watch(groupTabsProvider(widget.conversationId)).value;
    final registry = ref.watch(groupTabKindRegistryProvider);
    final shown = [
      for (final tab in tabs?.tabs ?? const <GroupTab>[])
        if (tab.available && registry.opens(tab.kind)) tab,
    ];
    if (shown.isEmpty) {
      return const SizedBox.shrink();
    }
    final pinned = widget.pinnedNote;
    final count = shown.length + (pinned == null ? 0 : 1);
    final margin = widget.desktop
        ? const EdgeInsets.fromLTRB(20, 10, 20, 0)
        : EdgeInsets.zero;
    final open = _open;

    final folded = WeCordPressable(
      key: const ValueKey('group-tabs-fold'),
      onPressed: _toggle,
      semanticLabel: tr('Tabs, {count}', {'count': count}),
      excludeSemantics: true,
      hint: open ? tr('Hides the tabs') : tr('Shows the tabs'),
      pressedScale: 0.99,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(WeCordRadii.pill),
      ),
      builder: (context, states) => Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.fromLTRB(12, 6, 10, 6),
        decoration: BoxDecoration(
          color: c.raised,
          borderRadius: BorderRadius.circular(WeCordRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.tab_outlined, size: 16, color: c.muted),
            const SizedBox(width: 6),
            Text(
              tr('Tabs'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
            ),
            const SizedBox(width: 6),
            Text('$count', style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(width: 2),
            Icon(
              open
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 18,
              color: c.muted,
            ),
          ],
        ),
      ),
    );

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Align(alignment: Alignment.centerLeft, child: folded),
          if (open)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              // Opaque, so the messages scrolling under it do not show
              // through the gaps between the chips.
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                decoration: BoxDecoration(
                  color: c.panel,
                  borderRadius: BorderRadius.circular(WeCordRadii.lg),
                  border: Border.all(color: c.lineSoft),
                ),
                child: SizedBox(
                  height: MediaQuery.textScalerOf(context).scale(36),
                  child: ListView(
                    key: const ValueKey('group-tabs-row'),
                    scrollDirection: Axis.horizontal,
                    children: [
                      if (pinned != null)
                        _chip(
                          key: const ValueKey('group-tab-pinned-note'),
                          label: pinned.title.trim().isEmpty
                              ? tr('Untitled')
                              : '${pinned.icon} ${pinned.title}',
                          icon: Icons.push_pin_outlined,
                          onPressed: () => openWorkspace(
                            context,
                            conversationId: widget.conversationId,
                            noteId: pinned.id,
                            title: widget.title,
                          ),
                        ),
                      for (final tab in shown)
                        _chip(
                          key: ValueKey('group-tab-${tab.id}'),
                          label: tab.icon == null
                              ? tab.title
                              : '${tab.icon} ${tab.title}',
                          icon: registry.kindOf(tab.kind)!.icon,
                          locked: tab.closed,
                          onPressed: () =>
                              registry.kindOf(tab.kind)!.open(_ctx(), tab),
                        ),
                      _chip(
                        key: const ValueKey('group-tabs-all'),
                        label: tabs?.canManage ?? false
                            ? tr('Manage')
                            : tr('All'),
                        icon: Icons.tune_rounded,
                        onPressed: () => unawaited(
                          showGroupTabsSheet(
                            context,
                            conversationId: widget.conversationId,
                            title: widget.title,
                            circleId: widget.circleId,
                            canSend: widget.canSend,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _chip({
    required Key key,
    required String label,
    required IconData icon,
    required VoidCallback onPressed,
    bool locked = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: WeCordChip(
        key: key,
        label: _clip(label),
        semanticLabel: label,
        icon: locked ? Icons.lock_outline_rounded : icon,
        onPressed: onPressed,
      ),
    );
  }
}

/// A chip's words, cut so a long name does not push the row wide.
String _clip(String label, [int max = 20]) {
  final chars = label.characters;
  return chars.length <= max ? label : '${chars.take(max)}…';
}

// A whiteboard (D10) as a kind of tab: opens one board of the chat. Picked
// from the chat's boards, like a note. Registered in
// group_tab_kinds_registrations.dart.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/features/group_tabs/group_tab_pickers.dart';
import 'package:wecord/features/whiteboard/whiteboard_routes.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The boards of a chat as things a tab can point at.
final _boardCandidatesProvider = FutureProvider.autoDispose
    .family<List<GroupTabCandidate>, String>((ref, conversationId) async {
      final boards = await ref.watch(
        whiteboardListProvider(conversationId).future,
      );
      return [
        for (final board in boards)
          GroupTabCandidate(
            target: board.id,
            title: board.title.isEmpty ? tr('Untitled whiteboard') : board.title,
          ),
      ];
    });

final whiteboardGroupTabKind = GroupTabKindContribution(
  kind: GroupTabKinds.whiteboard,
  order: 680,
  label: () => tr('Whiteboard'),
  icon: Icons.draw_outlined,
  open: (ctx, tab) {
    final id = tab.target;
    if (id != null) {
      openWhiteboard(
        ctx.context,
        conversationId: ctx.conversationId,
        boardId: id,
        title: tab.title,
      );
    }
  },
  pick: (ctx) => pickGroupTabCandidate(
    ctx.context,
    title: tr('Pick a whiteboard'),
    items: _boardCandidatesProvider(ctx.conversationId),
    emptyText: tr(
      'This chat has no whiteboards yet. Start one from the + menu first.',
    ),
  ),
);

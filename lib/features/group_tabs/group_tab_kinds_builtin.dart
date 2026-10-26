// The kinds of tab the app opens itself: a note, a task list, a form, a
// check-in, a link, the circle's knowledge base and the chat's events.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/chats/conversation_navigation.dart'
    show openPage;
import 'package:wecord/features/chats/events/chat_event_widgets.dart'
    show showChatEventsList;
import 'package:wecord/features/chats/message_markdown_text.dart'
    show linkLauncherProvider;
import 'package:wecord/features/check_in/check_in_page.dart';
import 'package:wecord/features/circles/circle_routes.dart';
import 'package:wecord/features/forms/form_fill_page.dart';
import 'package:wecord/features/group_tabs/group_tab_kinds.dart';
import 'package:wecord/features/group_tabs/group_tab_models.dart';
import 'package:wecord/features/group_tabs/group_tab_pickers.dart';
import 'package:wecord/features/group_tabs/group_tabs_repository.dart';
import 'package:wecord/features/workspace/workspace_navigation.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// The notes of a chat as things a tab can point at.
final _noteCandidatesProvider = FutureProvider.autoDispose
    .family<List<GroupTabCandidate>, String>((ref, conversationId) async {
      final notes = await ref.watch(notesListProvider(conversationId).future);
      return [
        for (final note in notes)
          GroupTabCandidate(
            target: note.id,
            title: note.title,
            icon: note.icon,
          ),
      ];
    });

/// The task lists of a chat as things a tab can point at.
final _listCandidatesProvider = FutureProvider.autoDispose
    .family<List<GroupTabCandidate>, String>((ref, conversationId) async {
      final lists = await ref.watch(taskListsProvider(conversationId).future);
      return [
        for (final list in lists)
          GroupTabCandidate(
            target: list.id,
            title: list.title,
            icon: list.icon,
          ),
      ];
    });

/// The built-in kinds, in the order of the "Add a tab" list.
final List<GroupTabKindContribution> builtInGroupTabKinds = [
  GroupTabKindContribution(
    kind: GroupTabKinds.note,
    order: 100,
    label: () => tr('Note'),
    icon: Icons.description_outlined,
    open: (ctx, tab) => openWorkspace(
      ctx.context,
      conversationId: ctx.conversationId,
      tab: WorkspaceTab.notes,
      noteId: tab.target,
      title: ctx.title,
    ),
    pick: (ctx) => pickGroupTabCandidate(
      ctx.context,
      title: tr('Pick a note'),
      items: _noteCandidatesProvider(ctx.conversationId),
      emptyText: tr('This chat has no notes yet. Make one from Notes first.'),
    ),
  ),
  GroupTabKindContribution(
    kind: GroupTabKinds.list,
    order: 200,
    label: () => tr('Task list'),
    icon: Icons.checklist_rounded,
    open: (ctx, tab) => openWorkspace(
      ctx.context,
      conversationId: ctx.conversationId,
      tab: WorkspaceTab.lists,
      listId: tab.target,
      title: ctx.title,
    ),
    pick: (ctx) => pickGroupTabCandidate(
      ctx.context,
      title: tr('Pick a list'),
      items: _listCandidatesProvider(ctx.conversationId),
      emptyText: tr('This chat has no lists yet. Make one from Lists first.'),
    ),
  ),
  GroupTabKindContribution(
    kind: GroupTabKinds.form,
    order: 300,
    label: () => tr('Form'),
    icon: Icons.assignment_outlined,
    open: (ctx, tab) {
      final id = tab.target;
      if (id != null) {
        unawaited(openFormFill(ctx.context, formId: id));
      }
    },
    pick: (ctx) => pickGroupTabCandidate(
      ctx.context,
      title: tr('Pick a form'),
      items: groupTabCandidatesProvider((
        conversationId: ctx.conversationId,
        kind: GroupTabKinds.form,
      )),
      emptyText: tr(
        'This chat has no forms yet. Post one from the + menu first.',
      ),
    ),
  ),
  GroupTabKindContribution(
    kind: GroupTabKinds.checkIn,
    order: 400,
    label: () => tr('Daily check-in'),
    icon: Icons.event_available_outlined,
    open: (ctx, tab) {
      final id = tab.target;
      if (id != null) {
        unawaited(openCheckIn(ctx.context, checkInId: id));
      }
    },
    pick: (ctx) => pickGroupTabCandidate(
      ctx.context,
      title: tr('Pick a check-in'),
      items: groupTabCandidatesProvider((
        conversationId: ctx.conversationId,
        kind: GroupTabKinds.checkIn,
      )),
      emptyText: tr(
        'This chat has no check-ins yet. Post one from the + menu first.',
      ),
    ),
  ),
  GroupTabKindContribution(
    kind: GroupTabKinds.link,
    order: 500,
    label: () => tr('Link'),
    icon: Icons.link_rounded,
    open: (ctx, tab) {
      final uri = Uri.tryParse(tab.target ?? '');
      if (uri != null) {
        unawaited(ctx.container.read(linkLauncherProvider)(ctx.context, uri));
      }
    },
    pick: (ctx) => pickGroupTabLink(ctx.context),
  ),
  GroupTabKindContribution(
    kind: GroupTabKinds.knowledgeBase,
    order: 600,
    label: () => tr('Knowledge base'),
    icon: Icons.menu_book_outlined,
    canAdd: (ctx) => ctx.circleId != null,
    defaultTitle: () => tr('Knowledge base'),
    open: (ctx, tab) {
      final circleId = tab.circleId ?? ctx.circleId;
      if (circleId != null) {
        openPage(ctx.context, '${CircleRoutes.path}/$circleId/knowledge');
      }
    },
  ),
  GroupTabKindContribution(
    kind: GroupTabKinds.events,
    order: 700,
    label: () => tr('Events'),
    icon: Icons.event_outlined,
    defaultTitle: () => tr('Events'),
    open: (ctx, tab) {
      final circleId = tab.circleId ?? ctx.circleId;
      if (circleId != null) {
        openPage(ctx.context, '${CircleRoutes.path}/$circleId/events');
      } else {
        unawaited(
          showChatEventsList(
            ctx.context,
            conversationId: ctx.conversationId,
            canCreate: ctx.canSend,
          ),
        );
      }
    },
  ),
];

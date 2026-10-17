import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/workspace/workspace_panel.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../mobile/phone_test_support.dart';
import 'workspace_world.dart';

Future<void> openDirect(WidgetTester tester, PhoneWorld world) {
  return world.open(
    tester,
    '${ChatsScreen.path}/dm-1',
    extra: ChatThreadRouteExtra(
      title: bart.displayName,
      type: ConversationType.direct,
    ),
  );
}

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

void main() {
  group('phone', () {
    testWidgets('the pinned note is a banner that opens the note', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final workspace = WorkspaceWorld()..install();
      await openDirect(tester, workspace.world);
      expect(find.byKey(const ValueKey('pinned-note-banner')), findsOneWidget);
      expect(find.text('Trip plan'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pinned-note-banner')));
      await settle(tester);
      expect(find.byKey(const ValueKey('note-title')), findsOneWidget);
      expect(find.text('Saturday'), findsOneWidget);
      await workspace.world.close(tester);
    });

    testWidgets('no pinned note, no banner', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final workspace = WorkspaceWorld();
      workspace.notes.pinned = null;
      workspace.install();
      await openDirect(tester, workspace.world);
      expect(find.byKey(const ValueKey('pinned-note-banner')), findsNothing);
      await workspace.world.close(tester);
    });

    testWidgets('Notes and Lists are in the header menu', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final workspace = WorkspaceWorld()..install();
      await openDirect(tester, workspace.world);
      await tester.tap(find.byTooltip('More'));
      await settle(tester);
      expect(find.text('Notes'), findsOneWidget);
      expect(find.text('Lists'), findsOneWidget);
      await tester.tap(find.text('Lists'));
      await settle(tester);
      expect(find.text('Launch checklist'), findsOneWidget);
      await workspace.world.close(tester);
    });

    testWidgets('Create task in the message menu, with the message as title', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final workspace = WorkspaceWorld()..install();
      await openDirect(tester, workspace.world);
      await tester.longPress(
        find.textContaining('Also this', findRichText: true).first,
      );
      await settle(tester);
      await tester.tap(find.text('Create task'));
      await settle(tester);
      // The title starts from the message.
      expect(find.textContaining('Also this'), findsWidgets);
      await tester.tap(
        find.byKey(const ValueKey('create-task-list-list-launch')),
      );
      await tester.pump();
      await tester.tap(find.text('Create task').last);
      await settle(tester);
      expect(workspace.lists.createdFromMessage, ['m7']);
      final created = workspace.lists.items.values.firstWhere(
        (item) => item.sourceMessageId == 'm7',
      );
      expect(created.title, startsWith('Also this'));
      expect(find.text('Task created.'), findsOneWidget);
      await workspace.world.close(tester);
    });

    testWidgets('a shared note is a card in the chat', (tester) async {
      usePhoneViewport(tester, notchedPhone);
      final workspace = WorkspaceWorld();
      workspace.world.chats.messages = [
        phoneMessage(
          'note-card',
          bart,
          '\u{1F5FA} Trip plan',
          minutesAgo: 3,
          attachment: const {
            'kind': 'note',
            'note_id': 'note-plan',
            'title': 'Trip plan',
            'icon': '\u{1F5FA}',
          },
        ),
        phoneMessage(
          'task-card',
          bart,
          '☑ Design the banner',
          minutesAgo: 2,
          attachment: const {
            'kind': 'task',
            'item_id': 'item-design',
            'list_id': 'list-launch',
            'title': 'Design the banner',
          },
        ),
      ];
      workspace.install();
      await openDirect(tester, workspace.world);
      expect(
        find.byKey(const ValueKey('workspace-card-note-plan')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('workspace-card-item-design')),
        findsOneWidget,
      );
      // The card shows the live task (its date comes from the list).
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('workspace-card-item-design')),
          matching: find.byIcon(Icons.event_outlined),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('workspace-card-note-plan')));
      await settle(tester);
      expect(find.byKey(const ValueKey('note-title')), findsOneWidget);
      await workspace.world.close(tester);
    });

    testWidgets('a message made into a task shows it, with a check box', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final workspace = WorkspaceWorld();
      workspace.lists.messageTaskList = const [
        MessageTask(
          messageId: 'm7',
          itemId: 'item-copy',
          listId: 'list-launch',
          title: 'Write the launch copy',
          isDone: false,
        ),
      ];
      workspace.install();
      await openDirect(tester, workspace.world);
      expect(
        find.byKey(const ValueKey('message-task-item-copy')),
        findsOneWidget,
      );
      await tester.tap(
        find.bySemanticsLabel('Mark "Write the launch copy" as done'),
      );
      await settle(tester);
      expect(workspace.lists.items['item-copy']!.status, 'done');
      await workspace.world.close(tester);
    });

    testWidgets('notifications list assignments and due reminders', (
      tester,
    ) async {
      usePhoneViewport(tester, notchedPhone);
      final workspace = WorkspaceWorld();
      workspace.lists.notificationList = [
        TaskNotification(
          id: 'tn-1',
          kind: TaskNotificationKind.assigned,
          itemId: 'item-design',
          listId: 'list-launch',
          conversationId: WorkspaceWorld.conversationId,
          title: 'Design the banner',
          createdAt: minutesAgo(4),
          isUnread: true,
          isDone: false,
          actorName: 'Bart',
          dueAt: DateTime.now().add(const Duration(days: 3)),
        ),
        TaskNotification(
          id: 'tn-2',
          kind: TaskNotificationKind.overdue,
          itemId: 'item-copy',
          listId: 'list-launch',
          conversationId: WorkspaceWorld.conversationId,
          title: 'Write the launch copy',
          createdAt: minutesAgo(40),
          isUnread: false,
          isDone: false,
        ),
      ];
      workspace.install();
      await workspace.world.open(tester, InboxScreen.path);
      expect(
        find.textContaining('assigned you a task', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('Task overdue', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('Design the banner'), findsOneWidget);

      // The Tasks chip narrows the page to them.
      await tester.ensureVisible(
        find.byKey(const ValueKey('inbox-filter-tasks')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('inbox-filter-tasks')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('inbox-item-inbox-mention')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('inbox-task-tn-1')), findsOneWidget);

      // Opening one marks it read and opens the list.
      await tester.tap(find.byKey(const ValueKey('inbox-task-open-tn-1')));
      await settle(tester);
      expect(
        workspace.lists.notificationList
            .firstWhere((n) => n.id == 'tn-1')
            .isUnread,
        isFalse,
      );
      expect(find.text('Launch checklist'), findsWidgets);
      await workspace.world.close(tester);
    });
  });

  group('desktop', () {
    void desktopTest(
      String description,
      Future<void> Function(WidgetTester tester, WorkspaceWorld workspace) body,
    ) {
      testWidgets(description, (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        try {
          usePhoneViewport(tester, _desktop);
          addTearDown(tester.view.reset);
          final workspace = WorkspaceWorld()..install();
          await body(tester, workspace);
          await workspace.world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    desktopTest('Notes opens a panel beside the chat, which closes again', (
      tester,
      workspace,
    ) async {
      await openDirect(tester, workspace.world);
      expect(find.byType(WorkspacePanel), findsNothing);
      await tester.tap(find.byTooltip('Notes and lists'));
      await settle(tester);
      expect(find.byType(WorkspacePanel), findsOneWidget);
      expect(find.text('Trailhead rules'), findsOneWidget);
      // The chat is still there beside it.
      expect(
        find.textContaining('Also this', findRichText: true),
        findsWidgets,
      );
      expect(tester.getSize(find.byType(WorkspacePanel)).width, 440);
      expect(workspace.world.panelLayoutStore.layout?.docsCollapsed, isFalse);

      await tester.tap(find.byTooltip('Close'));
      await settle(tester);
      expect(find.byType(WorkspacePanel), findsNothing);
    });

    desktopTest('the panel can be resized and remembers its width', (
      tester,
      workspace,
    ) async {
      await openDirect(tester, workspace.world);
      await tester.tap(find.byTooltip('Notes and lists'));
      await settle(tester);
      await tester.drag(
        find.byKey(const ValueKey('resize-docs')),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(WorkspacePanel)).width, 520);
      expect(workspace.world.panelLayoutStore.layout?.docsWidth, 520);
    });

    desktopTest('both tabs are in the panel and a note opens in place', (
      tester,
      workspace,
    ) async {
      await openDirect(tester, workspace.world);
      await tester.tap(find.byTooltip('Notes and lists'));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-lists')));
      await settle(tester);
      expect(find.text('Launch checklist'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-tab-notes')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('note-row-note-plan')));
      await settle(tester);
      expect(find.byKey(const ValueKey('note-title')), findsOneWidget);
      // Back to the index.
      await tester.tap(find.byTooltip('Back to notes'));
      await settle(tester);
      expect(find.byKey(const ValueKey('note-row-note-plan')), findsOneWidget);
    });

    desktopTest('the pinned note banner opens the note in the panel', (
      tester,
      workspace,
    ) async {
      await openDirect(tester, workspace.world);
      await tester.tap(find.byKey(const ValueKey('pinned-note-banner')));
      await settle(tester);
      expect(find.byType(WorkspacePanel), findsOneWidget);
      expect(find.byKey(const ValueKey('note-title')), findsOneWidget);
    });
  });
}

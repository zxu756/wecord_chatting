// Renders Notes and Lists on a phone (390x844) and a desktop (1440x900) with
// real fonts and writes PNGs for eyeballing. Not part of `flutter test`; run
// it with:
//
//   flutter test tool/screenshots/notes_lists_screenshots_test.dart \
//     --dart-define=PHONE_SCREENS_DIR=build/notes-lists/light
//
// Add --dart-define=PHONE_SCREENS_DARK=true for the dark theme and
// --dart-define=PHONE_SCREENS_ZH=true for the Chinese interface.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/inbox/inbox_screen.dart';
import 'package:wecord/features/lists/list_models.dart';
import 'package:wecord/features/notes/note_models.dart';
import 'package:wecord/features/notes/notes_repository.dart';
import 'package:wecord/shared/models/conversation.dart';

import '../../test/features/workspace/workspace_world.dart';
import '../../test/mobile/phone_test_support.dart';
import 'screenshot_fonts.dart';

const _outputDir = String.fromEnvironment(
  'PHONE_SCREENS_DIR',
  defaultValue: 'build/notes-lists/light',
);

const _phone = PhoneViewport(
  name: 'phone',
  size: Size(390, 844),
  devicePixelRatio: 2,
  topInset: 47,
  bottomInset: 34,
);

const _desktop = PhoneViewport(
  name: 'desktop',
  size: Size(1440, 900),
  devicePixelRatio: 1,
);

void main() {
  setUpAll(loadScreenshotFonts);

  Future<void> shoot(WidgetTester tester, String name) async {
    await settle(tester);
    final renderView = tester.binding.renderViews.first;
    final layer = renderView.debugLayer! as OffsetLayer;
    await tester.runAsync(() async {
      final image = await layer.toImage(renderView.paintBounds);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File('$_outputDir/$name.png');
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

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

  for (final viewport in [_phone, _desktop]) {
    final prefix = viewport.name;
    final desktop = viewport == _desktop;

    void screen(
      String name,
      Future<void> Function(WidgetTester tester, WorkspaceWorld workspace) body,
    ) {
      testWidgets('$prefix $name', (tester) async {
        if (desktop) {
          debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        }
        try {
          usePhoneViewport(tester, viewport);
          final workspace = WorkspaceWorld();
          // Chat messages with the cards.
          workspace.world.chats.messages = [
            ...richMessages().take(4),
            phoneMessage(
              'note-card',
              grace,
              '\u{1F5FA} Trip plan',
              minutesAgo: 14,
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
              minutesAgo: 9,
              attachment: const {
                'kind': 'task',
                'item_id': 'item-design',
                'list_id': 'list-launch',
                'title': 'Design the banner',
              },
            ),
            phoneMessage(
              'm7',
              me,
              'Can someone write the launch copy before Friday?',
              minutesAgo: 3,
            ),
          ];
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
          await body(tester, workspace);
          await shoot(tester, '$prefix-$name');
          await workspace.world.close(tester);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }

    screen('chat', (tester, workspace) async {
      await openDirect(tester, workspace.world);
    });

    screen('message-menu', (tester, workspace) async {
      await openDirect(tester, workspace.world);
      if (desktop) {
        await tester.tap(
          find.textContaining('Can someone write', findRichText: true).first,
          buttons: kSecondaryButton,
        );
      } else {
        await tester.longPress(
          find.textContaining('Can someone write', findRichText: true).first,
        );
      }
      await settle(tester);
    });

    screen('notes', (tester, workspace) async {
      if (desktop) {
        await openDirect(tester, workspace.world);
        await tester.tap(find.byTooltip('Notes and lists'));
      } else {
        await workspace.world.open(
          tester,
          '/chats/dm-1/workspace?tab=notes',
          extra: 'Bart',
        );
      }
      await settle(tester);
    });

    screen('note', (tester, workspace) async {
      if (desktop) {
        await openDirect(tester, workspace.world);
        await tester.tap(find.byTooltip('Notes and lists'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('note-row-note-plan')));
      } else {
        await workspace.world.open(
          tester,
          '/chats/dm-1/workspace?tab=notes&note=note-plan',
          extra: 'Bart',
        );
      }
      await settle(tester);
      workspace.notes.presence.controller.add(const [
        NotePeer(userId: 'user-3', name: 'Grace', blockId: 'blk-2', offset: 22),
        NotePeer(userId: 'user-2', name: 'Bart', blockId: 'blk-4', offset: 6),
      ]);
      await tester.pump();
      await tester.tap(find.textContaining('Rent a bear').first);
      await tester.pump();
    });

    screen('note-history', (tester, workspace) async {
      workspace.notes.versions = [
        NoteVersionSummary(
          id: 'v-1',
          createdAt: DateTime.now().subtract(const Duration(minutes: 40)),
          kind: 'manual',
          title: 'Trip plan',
          blockCount: 6,
          label: 'Before the rewrite',
          createdByName: 'Ada Lovelace',
        ),
        NoteVersionSummary(
          id: 'v-2',
          createdAt: DateTime.now().subtract(const Duration(hours: 5)),
          kind: 'auto',
          title: 'Trip plan',
          blockCount: 4,
          createdByName: 'Grace',
        ),
      ];
      await workspace.world.open(
        tester,
        '/chats/dm-1/workspace?tab=notes&note=note-plan',
        extra: 'Bart',
      );
      await settle(tester);
      await tester.tap(find.byTooltip('Version history'));
    });

    screen('lists', (tester, workspace) async {
      if (desktop) {
        await openDirect(tester, workspace.world);
        await tester.tap(find.byTooltip('Notes and lists'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('workspace-tab-lists')));
      } else {
        await workspace.world.open(
          tester,
          '/chats/dm-1/workspace?tab=lists',
          extra: 'Bart',
        );
      }
      await settle(tester);
    });

    screen('list', (tester, workspace) async {
      if (desktop) {
        await openDirect(tester, workspace.world);
        await tester.tap(find.byTooltip('Notes and lists'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('workspace-tab-lists')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('list-row-list-launch')));
      } else {
        await workspace.world.open(
          tester,
          '/chats/dm-1/workspace?tab=lists&list=list-launch',
          extra: 'Bart',
        );
      }
    });

    screen('board', (tester, workspace) async {
      workspace.lists.lists['list-launch'] = workspace
          .lists
          .lists['list-launch']!
          .copyWith(defaultView: TaskListView.board);
      if (desktop) {
        await openDirect(tester, workspace.world);
        await tester.tap(find.byTooltip('Notes and lists'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('workspace-tab-lists')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('list-row-list-launch')));
        await settle(tester);
        await tester.drag(
          find.byKey(const ValueKey('resize-docs')),
          const Offset(-300, 0),
        );
      } else {
        await workspace.world.open(
          tester,
          '/chats/dm-1/workspace?tab=lists&list=list-launch',
          extra: 'Bart',
        );
      }
    });

    screen('task', (tester, workspace) async {
      if (desktop) {
        await openDirect(tester, workspace.world);
        await tester.tap(find.byTooltip('Notes and lists'));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('workspace-tab-lists')));
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('list-row-list-launch')));
      } else {
        await workspace.world.open(
          tester,
          '/chats/dm-1/workspace?tab=lists&list=list-launch',
          extra: 'Bart',
        );
      }
      await settle(tester);
      await tester.tap(find.text('Design the banner').first);
    });

    screen('inbox', (tester, workspace) async {
      workspace.lists.notificationList = [
        TaskNotification(
          id: 'tn-1',
          kind: TaskNotificationKind.assigned,
          itemId: 'item-design',
          listId: 'list-launch',
          conversationId: 'conv-general',
          title: 'Design the banner',
          createdAt: minutesAgo(4),
          isUnread: true,
          isDone: false,
          actorName: 'Bart the Bold',
          dueAt: DateTime.now().add(const Duration(days: 3)),
        ),
        TaskNotification(
          id: 'tn-2',
          kind: TaskNotificationKind.dueSoon,
          itemId: 'item-copy',
          listId: 'list-launch',
          conversationId: 'conv-general',
          title: 'Write the launch copy',
          createdAt: minutesAgo(35),
          isUnread: false,
          isDone: false,
          dueAt: DateTime.now().add(const Duration(minutes: 25)),
        ),
      ];
      await workspace.world.open(tester, InboxScreen.path);
    });
  }
}

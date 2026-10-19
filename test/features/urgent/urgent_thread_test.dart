import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/urgent/urgent_models.dart';
import 'package:wecord/features/workspace/workspace_providers.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

import '../chats/chat_thread_screen_test.dart' as thread_test;
import '../file_preview/file_preview_fakes.dart';
import 'urgent_fakes.dart';

final _stamp = DateTime.utc(2026, 10, 24, 9);

Profile _profile(String id, String name) => Profile(
  id: id,
  username: id,
  displayName: name,
  bio: '',
  createdAt: _stamp,
  updatedAt: _stamp,
);

Widget _app(
  thread_test.FakeChatsRepository chats,
  FakeUrgentRepository urgent, {
  ConversationType type = ConversationType.group,
}) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(chats),
      urgentOverride(urgent),
      conversationMembersProvider.overrideWith(
        (ref, id) async => [
          GroupMember(profile: _profile('user-1', 'Me'), role: 'owner'),
          GroupMember(profile: _profile('user-2', 'Bo'), role: 'member'),
        ],
      ),
      onlineUserIdsProvider.overrideWith(
        (ref) => const Stream<Set<String>>.empty(),
      ),
      settingsRepositoryProvider.overrideWithValue(
        thread_test.FakeSettingsRepository(),
      ),
      ...filePreviewOverrides(),
      authRepositoryProvider.overrideWithValue(
        thread_test.FakeAuthRepository()
          ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
      ),
    ],
    child: MaterialApp(
      home: ChatThreadScreen(
        conversationId: 'conversation-1',
        title: 'Launch Crew',
        conversationType: type,
      ),
    ),
  );
}

thread_test.FakeChatsRepository _group({String announcement = ''}) =>
    thread_test.FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.group,
          title: 'Launch Crew',
          unreadCount: 0,
          announcement: announcement,
        ),
      ];

void main() {
  testWidgets('the red banner sits at the top of the chat', (tester) async {
    final urgent = FakeUrgentRepository(
      waiting: [pendingUrgent('m1', conversationId: 'conversation-1')],
    );
    await tester.pumpWidget(_app(_group(), urgent));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('urgent-banner')), findsOneWidget);
    expect(find.text('Ada marked a message urgent'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('urgent-got-it')));
    await tester.pumpAndSettle();
    expect(urgent.acknowledged, ['m1']);
    expect(find.byKey(const ValueKey('urgent-banner')), findsNothing);
  });

  testWidgets('another conversation\'s urgent message does not show', (
    tester,
  ) async {
    final urgent = FakeUrgentRepository(
      waiting: [pendingUrgent('m1', conversationId: 'elsewhere')],
    );
    await tester.pumpWidget(_app(_group(), urgent));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('urgent-banner')), findsNothing);
  });

  testWidgets('the announcement shows the count and a Confirm button', (
    tester,
  ) async {
    final urgent = FakeUrgentRepository(
      announcement: const AnnouncementAckState(
        requiresAck: true,
        total: 30,
        acked: 12,
        iAcked: false,
        canManage: false,
      ),
    );
    await tester.pumpWidget(
      _app(_group(announcement: 'Deploy at noon'), urgent),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Deploy at noon'), findsOneWidget);
    expect(find.text('Confirmed 12/30'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('announcement-ack-confirm')));
    await tester.pumpAndSettle();
    expect(urgent.announcementAcks, ['conversation-1']);
    expect(find.text('Confirmed 13/30'), findsOneWidget);
  });

  testWidgets('an announcement that asks for nothing looks as before', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(_group(announcement: 'Deploy at noon'), FakeUrgentRepository()),
    );
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(find.text('Deploy at noon'), findsOneWidget);
    expect(find.byKey(const ValueKey('announcement-ack-bar')), findsNothing);
  });

  testWidgets('Urgent is in the menu of your own message', (tester) async {
    final chats = _group()
      ..messages = [
        ChatMessage(
          id: 'message-1',
          conversationId: 'conversation-1',
          type: MessageType.text,
          senderId: 'user-1',
          body: 'Hand in the forms',
          createdAt: _stamp,
        ),
      ];
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(chats, FakeUrgentRepository()));
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('Hand in the forms'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-action-urgent')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('message-action-urgent')));
    await tester.pumpAndSettle();
    expect(find.text('Choose who must see this'), findsOneWidget);
    expect(find.byKey(const ValueKey('urgent-person-user-2')), findsOneWidget);
    // Not yourself.
    expect(find.byKey(const ValueKey('urgent-person-user-1')), findsNothing);
  });

  testWidgets('and not in the menu of somebody else\'s', (tester) async {
    final chats = _group()
      ..messages = [
        ChatMessage(
          id: 'message-1',
          conversationId: 'conversation-1',
          type: MessageType.text,
          senderId: 'user-2',
          body: 'Hand in the forms',
          createdAt: _stamp,
        ),
      ];
    await tester.pumpWidget(_app(chats, FakeUrgentRepository()));
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('Hand in the forms'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('message-action-urgent')), findsNothing);
  });
}

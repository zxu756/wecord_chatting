import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/ai/ai_repository.dart';
import 'package:wecord/features/ai/assistant/assistant_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/profile.dart';

import 'ai_fakes.dart';

class _Chats implements ChatsRepository {
  _Chats(this.role);

  final String role;

  @override
  Future<GroupDetail> getGroupDetail(String conversationId) async =>
      GroupDetail(
        conversationId: conversationId,
        title: 'Launch Crew',
        announcement: '',
        currentUserRole: role,
        members: [
          GroupMember(
            profile: Profile(
              id: 'owner-1',
              username: 'grace',
              displayName: 'Grace',
              bio: '',
              createdAt: DateTime.utc(2026),
              updatedAt: DateTime.utc(2026),
            ),
            role: 'owner',
          ),
        ],
      );

  @override
  Stream<void> conversationChanges() => const Stream.empty();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Contacts implements ContactsRepository {
  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Assistant implements AssistantRepository {
  var enabled = true;
  final sets = <bool>[];

  @override
  Future<AssistantJobStatus?> jobStatus(String messageId) async => null;

  @override
  Future<bool> groupAssistantEnabled(String conversationId) async => enabled;

  @override
  Future<void> setGroupAssistantEnabled(
    String conversationId, {
    required bool enabled,
  }) async {
    sets.add(enabled);
    this.enabled = enabled;
  }
}

void main() {
  Future<_Assistant> open(WidgetTester tester, {required String role}) async {
    final assistant = _Assistant();
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(_Chats(role)),
          contactsRepositoryProvider.overrideWithValue(_Contacts()),
          aiRepositoryProvider.overrideWithValue(FakeAiRepository()),
          assistantRepositoryProvider.overrideWithValue(assistant),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: GroupDetailSheet(
              conversationId: 'group-1',
              title: 'Launch Crew',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return assistant;
  }

  testWidgets('the owner sees the switch and can turn WeCord AI off', (
    tester,
  ) async {
    final assistant = await open(tester, role: 'owner');
    expect(find.text('WeCord AI in this group'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-detail-ai')));
    await tester.pumpAndSettle();
    expect(assistant.sets, [false]);
  });

  testWidgets('admins and members do not see it', (tester) async {
    await open(tester, role: 'admin');
    expect(find.byKey(const ValueKey('group-detail-ai')), findsNothing);
    await open(tester, role: 'member');
    expect(find.byKey(const ValueKey('group-detail-ai')), findsNothing);
  });
}

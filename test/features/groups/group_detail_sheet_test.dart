import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/groups/group_detail_sheet.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  testWidgets('invite friends picker renders contact aliases', (tester) async {
    final contactsRepository = _FakeContactsRepository()
      ..friends = [
        _profile(
          id: 'friend-1',
          username: 'ada',
          displayName: 'Ada Lovelace',
          alias: 'Ada L.',
        ),
      ];
    final chatsRepository = _FakeChatsRepository(
      detail: GroupDetail(
        conversationId: 'group-1',
        title: 'Launch Crew',
        announcement: 'Deploy at noon',
        announcementUpdatedAt: DateTime.utc(2026, 5, 19, 9, 30),
        announcementUpdatedBy: 'owner-1',
        currentUserRole: 'owner',
        members: [
          GroupMember(
            profile: _profile(id: 'owner-1', username: 'grace'),
            role: 'owner',
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          contactsRepositoryProvider.overrideWithValue(contactsRepository),
          chatsRepositoryProvider.overrideWithValue(chatsRepository),
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

    expect(find.text('Updated by Grace Lovelace'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Invite friends'));
    await tester.pumpAndSettle();

    expect(find.text('Ada L.'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsNothing);
  });
}

class _FakeContactsRepository implements ContactsRepository {
  var friends = <Profile>[];

  @override
  Future<List<Profile>> listFriends() async => friends;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeChatsRepository implements ChatsRepository {
  _FakeChatsRepository({required this.detail});

  final GroupDetail detail;

  @override
  Future<GroupDetail> getGroupDetail(String conversationId) async => detail;

  @override
  Stream<void> conversationChanges() => const Stream.empty();

  @override
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> memberIds,
  }) async {}

  @override
  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) async {}

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Profile _profile({
  required String id,
  required String username,
  String? displayName,
  String? alias,
}) {
  return Profile(
    id: id,
    username: username,
    displayName:
        displayName ??
        '${username[0].toUpperCase()}${username.substring(1)} Lovelace',
    alias: alias,
    avatarUrl: null,
    bio: '',
    createdAt: DateTime.utc(2026, 5, 18),
    updatedAt: DateTime.utc(2026, 5, 18),
  );
}

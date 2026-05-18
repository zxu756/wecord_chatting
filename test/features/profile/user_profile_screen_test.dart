import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/profile/profile_repository.dart';
import 'package:wecord/features/profile/user_profile_screen.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/profile_relationship.dart';

void main() {
  testWidgets('profile page shows friend actions', (tester) async {
    await tester.pumpWidget(
      buildProfileHarness(
        summary: friendSummary(displayName: 'Ada', username: 'ada'),
      ),
    );
    await tester.pump();

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
  });

  testWidgets('profile page shows add friend action for non-friends', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildProfileHarness(
        summary: noneSummary(displayName: 'Grace', username: 'grace'),
      ),
    );
    await tester.pump();

    expect(find.text('Add Friend'), findsOneWidget);
    expect(find.text('Message'), findsNothing);
  });
}

Widget buildProfileHarness({required ProfileSummary summary}) {
  final profileDataSource = FakeProfileDataSource()
    ..rpcResult = [summaryJson(summary)];

  return ProviderScope(
    overrides: [
      profileRepositoryProvider.overrideWithValue(
        ProfileRepository.withDataSource(profileDataSource),
      ),
      contactsRepositoryProvider.overrideWithValue(FakeContactsRepository()),
    ],
    child: const MaterialApp(home: UserProfileScreen(userId: 'user-2')),
  );
}

ProfileSummary friendSummary({
  required String displayName,
  required String username,
}) {
  return _summary(
    displayName: displayName,
    username: username,
    relationshipStatus: ProfileRelationshipStatus.friend,
  );
}

ProfileSummary noneSummary({
  required String displayName,
  required String username,
}) {
  return _summary(
    displayName: displayName,
    username: username,
    relationshipStatus: ProfileRelationshipStatus.none,
  );
}

ProfileSummary _summary({
  required String displayName,
  required String username,
  required ProfileRelationshipStatus relationshipStatus,
}) {
  return ProfileSummary(
    profile: Profile(
      id: 'user-2',
      username: username,
      displayName: displayName,
      bio: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    ),
    relationshipStatus: relationshipStatus,
    incomingRequestId: null,
    outgoingRequestId: null,
    isBlockedByMe: relationshipStatus == ProfileRelationshipStatus.blocked,
    hasBlockedMe: relationshipStatus == ProfileRelationshipStatus.blockedByThem,
  );
}

Map<String, dynamic> summaryJson(ProfileSummary summary) {
  return {
    'id': summary.profile.id,
    'username': summary.profile.username,
    'display_name': summary.profile.displayName,
    'alias': summary.profile.alias,
    'avatar_url': summary.profile.avatarUrl,
    'bio': summary.profile.bio,
    'relationship_status': switch (summary.relationshipStatus) {
      ProfileRelationshipStatus.self => 'self',
      ProfileRelationshipStatus.none => 'none',
      ProfileRelationshipStatus.friend => 'friend',
      ProfileRelationshipStatus.incomingRequest => 'incoming_request',
      ProfileRelationshipStatus.outgoingRequest => 'outgoing_request',
      ProfileRelationshipStatus.blocked => 'blocked',
      ProfileRelationshipStatus.blockedByThem => 'blocked_by_them',
    },
    'incoming_request_id': summary.incomingRequestId,
    'outgoing_request_id': summary.outgoingRequestId,
    'is_blocked_by_me': summary.isBlockedByMe,
    'has_blocked_me': summary.hasBlockedMe,
  };
}

class FakeProfileDataSource implements ProfileDataSource {
  Object? rpcResult;

  @override
  Future<Object?> rpc(String functionName, Map<String, dynamic> params) async {
    return rpcResult;
  }
}

class FakeContactsRepository implements ContactsRepository {
  @override
  Future<void> acceptFriendRequest(String requestId) async {}

  @override
  Future<List<IncomingFriendRequest>> listIncomingRequests() async {
    return const [];
  }

  @override
  Future<List<Profile>> listFriends() async {
    return const [];
  }

  @override
  Future<void> rejectFriendRequest(String requestId) async {}

  @override
  Future<List<Profile>> searchProfiles(String query) async {
    return const [];
  }

  @override
  Future<void> sendFriendRequest(String receiverId) async {}

  @override
  Future<void> setContactAlias({
    required String friendId,
    required String? alias,
  }) async {}
}

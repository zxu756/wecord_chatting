import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/shared/models/friend_request.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  testWidgets('shows search results and sends friend requests', (tester) async {
    final repository = FakeContactsRepository()
      ..searchResults = [_profile(id: 'user-2', username: 'ada')];

    await tester.pumpWidget(_app(repository));

    await tester.enterText(find.byType(TextField), 'Ada');
    await tester.pump();
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pump();

    expect(repository.searchQueries, ['Ada']);
    expect(repository.sentRequests, ['user-2']);
  });

  testWidgets('renders incoming requests and accepts or rejects them', (
    tester,
  ) async {
    final repository = FakeContactsRepository()
      ..incomingRequests = [
        _request(
          id: 'request-1',
          requesterId: 'user-2',
          receiverId: 'current-user',
        ),
        _request(
          id: 'request-2',
          requesterId: 'user-3',
          receiverId: 'current-user',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Incoming requests'), findsOneWidget);
    expect(find.text('user-2'), findsOneWidget);
    expect(find.text('user-3'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept').first);
    await tester.pump();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').at(1));
    await tester.pump();

    expect(repository.acceptedRequests, ['request-1']);
    expect(repository.rejectedRequests, ['request-2']);
  });

  testWidgets('renders friends list', (tester) async {
    final repository = FakeContactsRepository()
      ..friends = [
        _profile(
          id: 'friend-1',
          username: 'grace',
          displayName: 'Grace Hopper',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('@grace'), findsOneWidget);
  });

  testWidgets('shows async loading and error states', (tester) async {
    final repository = FakeContactsRepository()
      ..friendsFuture = Future<List<Profile>>.delayed(
        const Duration(milliseconds: 20),
        () => throw Exception('friends failed'),
      );

    await tester.pumpWidget(_app(repository));

    expect(find.byType(CircularProgressIndicator), findsWidgets);

    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump();

    expect(find.textContaining('friends failed'), findsOneWidget);
  });
}

Widget _app(FakeContactsRepository repository) {
  return ProviderScope(
    overrides: [contactsRepositoryProvider.overrideWithValue(repository)],
    child: const MaterialApp(home: ContactsScreen()),
  );
}

class FakeContactsRepository implements ContactsRepository {
  var searchResults = <Profile>[];
  var incomingRequests = <FriendRequest>[];
  var friends = <Profile>[];
  Future<List<Profile>>? friendsFuture;
  final searchQueries = <String>[];
  final sentRequests = <String>[];
  final acceptedRequests = <String>[];
  final rejectedRequests = <String>[];

  @override
  Future<List<Profile>> searchProfiles(String query) async {
    searchQueries.add(query);
    return searchResults;
  }

  @override
  Future<List<Profile>> listFriends() async {
    final future = friendsFuture;
    if (future != null) {
      return future;
    }
    return friends;
  }

  @override
  Future<List<FriendRequest>> listIncomingRequests() async {
    return incomingRequests;
  }

  @override
  Future<void> sendFriendRequest(String receiverId) async {
    sentRequests.add(receiverId);
  }

  @override
  Future<void> acceptFriendRequest(String requestId) async {
    acceptedRequests.add(requestId);
  }

  @override
  Future<void> rejectFriendRequest(String requestId) async {
    rejectedRequests.add(requestId);
  }
}

Profile _profile({
  required String id,
  required String username,
  String? displayName,
}) {
  return Profile(
    id: id,
    username: username,
    displayName:
        displayName ??
        '${username[0].toUpperCase()}${username.substring(1)} Lovelace',
    avatarUrl: null,
    bio: '',
    createdAt: DateTime.utc(2026, 5, 18),
    updatedAt: DateTime.utc(2026, 5, 18),
  );
}

FriendRequest _request({
  required String id,
  required String requesterId,
  required String receiverId,
}) {
  return FriendRequest(
    id: id,
    requesterId: requesterId,
    receiverId: receiverId,
    status: FriendRequestStatus.pending,
    createdAt: DateTime.utc(2026, 5, 18),
    updatedAt: DateTime.utc(2026, 5, 18),
  );
}

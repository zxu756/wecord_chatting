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

    expect(repository.searchQueries, ['Ada', 'Ada']);
    expect(repository.sentRequests, ['user-2']);
    expect(find.widgetWithText(FilledButton, 'Requested'), findsOneWidget);
    final requestedButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Requested'),
    );
    expect(requestedButton.onPressed, isNull);
  });

  testWidgets('renders incoming requester profiles and refreshes actions', (
    tester,
  ) async {
    final repository = FakeContactsRepository()
      ..incomingRequests = [
        _incomingRequest(
          requestId: 'request-1',
          requester: _profile(
            id: 'user-2',
            username: 'ada',
            displayName: 'Ada Lovelace',
          ),
        ),
        _incomingRequest(
          requestId: 'request-2',
          requester: _profile(
            id: 'user-3',
            username: 'grace',
            displayName: 'Grace Hopper',
          ),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Incoming requests'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('@grace'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Accept').first);
    await tester.pumpAndSettle();

    expect(find.text('Ada Lovelace'), findsNothing);
    expect(find.text('Grace Hopper'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Reject').first);
    await tester.pumpAndSettle();

    expect(repository.acceptedRequests, ['request-1']);
    expect(repository.rejectedRequests, ['request-2']);
    expect(find.text('Grace Hopper'), findsNothing);
    expect(find.text('No incoming requests.'), findsOneWidget);
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
  var incomingRequests = <IncomingFriendRequest>[];
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
  Future<List<IncomingFriendRequest>> listIncomingRequests() async {
    return incomingRequests;
  }

  @override
  Future<void> sendFriendRequest(String receiverId) async {
    sentRequests.add(receiverId);
  }

  @override
  Future<void> acceptFriendRequest(String requestId) async {
    acceptedRequests.add(requestId);
    incomingRequests = incomingRequests
        .where((request) => request.request.id != requestId)
        .toList();
  }

  @override
  Future<void> rejectFriendRequest(String requestId) async {
    rejectedRequests.add(requestId);
    incomingRequests = incomingRequests
        .where((request) => request.request.id != requestId)
        .toList();
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

IncomingFriendRequest _incomingRequest({
  required String requestId,
  required Profile requester,
}) {
  return IncomingFriendRequest(
    request: FriendRequest(
      id: requestId,
      requesterId: requester.id,
      receiverId: 'current-user',
      status: FriendRequestStatus.pending,
      createdAt: DateTime.utc(2026, 5, 18),
      updatedAt: DateTime.utc(2026, 5, 18),
    ),
    requester: requester,
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/shared/models/friend_request.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
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
            avatarUrl: 'profile-avatars/user-2/ada.png',
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
    expect(find.text('AL'), findsOneWidget);
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
          avatarUrl: 'profile-avatars/friend-1/grace.png',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('@grace'), findsOneWidget);
    expect(find.text('GH'), findsOneWidget);
  });

  testWidgets('starts a direct conversation from a friend row', (tester) async {
    final contactsRepository = FakeContactsRepository()
      ..friends = [
        _profile(
          id: 'friend-1',
          username: 'grace',
          displayName: 'Grace Hopper',
        ),
      ];
    final chatsRepository = FakeChatsRepository();
    final router = GoRouter(
      initialLocation: ContactsScreen.path,
      routes: [
        GoRoute(
          path: ContactsScreen.path,
          builder: (context, state) => const ContactsScreen(),
        ),
        GoRoute(
          path: '/chats/:conversationId',
          builder: (context, state) {
            final title = switch (state.extra) {
              ChatThreadRouteExtra(:final title) => title,
              final extra => extra,
            };
            return Text(
              'Thread ${state.pathParameters['conversationId']} $title',
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        contactsRepository,
        chatsRepository: chatsRepository,
        router: router,
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Message'));
    await tester.pumpAndSettle();

    expect(chatsRepository.directConversationUserIds, ['friend-1']);
    expect(
      find.text('Thread conversation-for-friend-1 Grace Hopper'),
      findsOneWidget,
    );
  });

  testWidgets('creates a group conversation from selected friends', (
    tester,
  ) async {
    final contactsRepository = FakeContactsRepository()
      ..friends = [
        _profile(
          id: 'friend-1',
          username: 'grace',
          displayName: 'Grace Hopper',
        ),
        _profile(id: 'friend-2', username: 'ada', displayName: 'Ada Lovelace'),
        _profile(
          id: 'friend-3',
          username: 'katherine',
          displayName: 'Katherine Johnson',
        ),
      ];
    final chatsRepository = FakeChatsRepository();
    final router = GoRouter(
      initialLocation: ContactsScreen.path,
      routes: [
        GoRoute(
          path: ContactsScreen.path,
          builder: (context, state) => const ContactsScreen(),
        ),
        GoRoute(
          path: '/chats/:conversationId',
          builder: (context, state) {
            final title = switch (state.extra) {
              ChatThreadRouteExtra(:final title) => title,
              final extra => extra,
            };
            return Text(
              'Thread ${state.pathParameters['conversationId']} $title',
            );
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        contactsRepository,
        chatsRepository: chatsRepository,
        router: router,
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'New Group'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Group name'), 'Launch Crew');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Grace Hopper'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Ada Lovelace'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(chatsRepository.createdGroupTitle, 'Launch Crew');
    expect(chatsRepository.createdGroupMemberIds, ['friend-1', 'friend-2']);
    expect(find.text('Thread group-conversation Launch Crew'), findsOneWidget);
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

Widget _app(
  FakeContactsRepository repository, {
  FakeChatsRepository? chatsRepository,
  GoRouter? router,
}) {
  final child = router == null
      ? const MaterialApp(home: ContactsScreen())
      : MaterialApp.router(routerConfig: router);

  return ProviderScope(
    overrides: [
      contactsRepositoryProvider.overrideWithValue(repository),
      if (chatsRepository != null)
        chatsRepositoryProvider.overrideWithValue(chatsRepository),
    ],
    child: child,
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

class FakeChatsRepository implements ChatsRepository {
  final directConversationUserIds = <String>[];
  String? createdGroupTitle;
  List<String>? createdGroupMemberIds;

  @override
  Future<List<ConversationSummary>> listConversations() async {
    return const [];
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    return const [];
  }

  @override
  Future<List<ConversationReadMarker>> listReadMarkers(
    String conversationId,
  ) async {
    return const [];
  }

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) async {
    directConversationUserIds.add(otherUserId);
    return 'conversation-for-$otherUserId';
  }

  @override
  Future<GroupDetail> getGroupDetail(String conversationId) async {
    return GroupDetail(
      conversationId: conversationId,
      title: conversationId,
      members: const [],
    );
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
  }) async {}

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  }) async {}

  @override
  Future<String> createImageUrl(ImageAttachment attachment) async {
    return 'https://example.com/${attachment.path}';
  }

  @override
  Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
  }) async {
    createdGroupTitle = title;
    createdGroupMemberIds = memberIds;
    return 'group-conversation';
  }

  @override
  Future<void> renameGroupConversation({
    required String conversationId,
    required String title,
  }) async {}

  @override
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> memberIds,
  }) async {}

  @override
  Future<void> recallMessage({required String messageId}) async {}

  @override
  Future<void> editMessage({
    required String messageId,
    required String body,
  }) async {}

  @override
  Future<void> markConversationRead(String conversationId) async {}

  @override
  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  ) {
    return _searchConversations(conversations, query);
  }

  @override
  List<ChatMessage> searchMessages(List<ChatMessage> messages, String query) {
    return _searchMessages(messages, query);
  }

  @override
  Stream<void> conversationChanges() => const Stream.empty();

  @override
  Stream<void> messageChanges(String conversationId) => const Stream.empty();

  @override
  Stream<void> threadChanges(String conversationId) => const Stream.empty();

  @override
  Stream<ConversationActivity> conversationActivity(String conversationId) {
    return const Stream.empty();
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}

List<ConversationSummary> _searchConversations(
  List<ConversationSummary> conversations,
  String query,
) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return conversations;
  }
  return conversations
      .where(
        (conversation) =>
            _containsQuery(conversation.title, normalizedQuery) ||
            _containsQuery(conversation.lastMessageBody, normalizedQuery),
      )
      .toList(growable: false);
}

List<ChatMessage> _searchMessages(List<ChatMessage> messages, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return messages;
  }
  return messages
      .where((message) {
        if (message.recalledAt != null) {
          return false;
        }
        final preview = message.replyPreview;
        return _containsQuery(message.body, normalizedQuery) ||
            _containsQuery(preview?.body, normalizedQuery) ||
            _containsQuery(preview?.senderName, normalizedQuery);
      })
      .toList(growable: false);
}

bool _containsQuery(String? value, String query) {
  return value?.toLowerCase().contains(query) ?? false;
}

Profile _profile({
  required String id,
  required String username,
  String? displayName,
  String? avatarUrl,
}) {
  return Profile(
    id: id,
    username: username,
    displayName:
        displayName ??
        '${username[0].toUpperCase()}${username.substring(1)} Lovelace',
    avatarUrl: avatarUrl,
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

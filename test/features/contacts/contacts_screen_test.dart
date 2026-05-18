import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/contacts/contacts_repository.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/settings/settings_repository.dart';
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
    await tester.pump();

    expect(find.text('Incoming requests'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('@ada'), findsOneWidget);
    final incomingAvatar = tester.widget<CircleAvatar>(
      find.byType(CircleAvatar).first,
    );
    final incomingImage = incomingAvatar.backgroundImage;
    expect(incomingImage, isA<NetworkImage>());
    expect(
      (incomingImage! as NetworkImage).url,
      'https://signed.example.com/profile-avatars/user-2/ada.png',
    );
    expect(find.text('AL'), findsNothing);
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
    await tester.pump();

    expect(find.text('Friends'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('@grace'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    final image = avatar.backgroundImage;
    expect(image, isA<NetworkImage>());
    expect(
      (image! as NetworkImage).url,
      'https://signed.example.com/profile-avatars/friend-1/grace.png',
    );
    expect(find.text('GH'), findsNothing);
  });

  testWidgets('friend tile shows alias and opens alias editor', (tester) async {
    final repository = FakeContactsRepository()
      ..friends = [
        _profile(
          id: 'friend-1',
          username: 'ada',
          displayName: 'Ada Lovelace',
          alias: 'Ada L.',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Ada L.'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit alias'));
    await tester.pumpAndSettle();

    expect(find.text('Edit alias'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).last).controller!.text,
      'Ada L.',
    );
  });

  testWidgets('alias editor trims saves and removes aliases', (tester) async {
    final repository = FakeContactsRepository()
      ..friends = [
        _profile(
          id: 'friend-1',
          username: 'ada',
          displayName: 'Ada Lovelace',
          alias: 'Ada L.',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Edit alias'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Alias'), '  Countess  ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.aliasUpdates, [
      const AliasUpdate(friendId: 'friend-1', alias: 'Countess'),
    ]);
    expect(find.text('Countess'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit alias'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Alias'), '   ');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repository.aliasUpdates, [
      const AliasUpdate(friendId: 'friend-1', alias: 'Countess'),
      const AliasUpdate(friendId: 'friend-1', alias: null),
    ]);
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('alias editor keeps errors visible after failed saves', (
    tester,
  ) async {
    final repository = FakeContactsRepository()
      ..friends = [
        _profile(id: 'friend-1', username: 'ada', displayName: 'Ada Lovelace'),
      ]
      ..aliasError = Exception('alias failed');

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Edit alias'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Alias'), 'Ada L.');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(find.text('Edit alias'), findsOneWidget);
    expect(find.textContaining('alias failed'), findsOneWidget);
  });

  testWidgets('alias editor validates the 48 character alias limit locally', (
    tester,
  ) async {
    final repository = FakeContactsRepository()
      ..friends = [
        _profile(id: 'friend-1', username: 'ada', displayName: 'Ada Lovelace'),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Edit alias'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Alias'), 'A' * 49);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();

    expect(repository.aliasUpdates, isEmpty);
    expect(find.textContaining('48 characters'), findsOneWidget);
    expect(find.text('Edit alias'), findsOneWidget);
  });

  testWidgets('filters friends by display name or username', (tester) async {
    final repository = FakeContactsRepository()
      ..friends = [
        _profile(
          id: 'friend-1',
          username: 'grace',
          displayName: 'Grace Hopper',
        ),
        _profile(id: 'friend-2', username: 'ada', displayName: 'Ada Lovelace'),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.pump();

    await tester.enterText(find.bySemanticsLabel('Search friends'), 'ADA');
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsNothing);
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
          alias: 'Amazing Grace',
        ),
        _profile(
          id: 'friend-2',
          username: 'ada',
          displayName: 'Ada Lovelace',
          alias: 'Ada L.',
        ),
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
    expect(
      find.widgetWithText(CheckboxListTile, 'Amazing Grace'),
      findsOneWidget,
    );
    expect(find.widgetWithText(CheckboxListTile, 'Ada L.'), findsOneWidget);
    await tester.enterText(find.bySemanticsLabel('Group name'), 'Launch Crew');
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Amazing Grace'));
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Ada L.'));
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
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      if (chatsRepository != null)
        chatsRepositoryProvider.overrideWithValue(chatsRepository),
    ],
    child: child,
  );
}

class FakeSettingsRepository implements SettingsRepository {
  @override
  Future<Profile> currentProfile() {
    throw UnimplementedError();
  }

  @override
  Future<void> updateProfile({
    required String displayName,
    required String bio,
    required String? avatarUrl,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> uploadAvatar({
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> createAvatarUrl(String avatarPath) async {
    return 'https://signed.example.com/$avatarPath';
  }
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
  final aliasUpdates = <AliasUpdate>[];
  Object? aliasError;

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

  @override
  Future<void> setContactAlias({
    required String friendId,
    required String? alias,
  }) async {
    final error = aliasError;
    if (error != null) {
      throw error;
    }
    aliasUpdates.add(AliasUpdate(friendId: friendId, alias: alias));
    friends = [
      for (final friend in friends)
        friend.id == friendId ? friend.copyWith(alias: alias) : friend,
    ];
  }
}

class AliasUpdate {
  const AliasUpdate({required this.friendId, required this.alias});

  final String friendId;
  final String? alias;

  @override
  bool operator ==(Object other) {
    return other is AliasUpdate &&
        other.friendId == friendId &&
        other.alias == alias;
  }

  @override
  int get hashCode => Object.hash(friendId, alias);
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
  Future<ConversationSummary?> getConversationSummary(
    String conversationId,
  ) async {
    return null;
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
    List<MessageMention> mentions = const <MessageMention>[],
  }) async {}

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  }) async {}

  @override
  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) async {}

  @override
  Future<void> forwardMessage({
    required String sourceMessageId,
    required String targetConversationId,
  }) async {}

  @override
  Future<String> createImageUrl(ImageAttachment attachment) async {
    return 'https://example.com/${attachment.path}';
  }

  @override
  Future<String> createVoiceUrl(VoiceAttachment attachment) async {
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
  Future<void> markConversationUnread(String conversationId) async {}

  @override
  Future<void> setConversationPinned({
    required String conversationId,
    required bool pinned,
  }) async {}

  @override
  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) async {}

  @override
  Future<void> hideConversation(String conversationId) async {}

  @override
  Future<String> uploadGroupAvatar({
    required String conversationId,
    required ChatImageUpload image,
  }) async {
    return 'group-avatars/$conversationId/avatar.png';
  }

  @override
  Future<void> updateGroupProfile({
    required String conversationId,
    required String title,
    required String? avatarUrl,
    required String announcement,
  }) async {}

  @override
  Future<void> leaveGroupConversation(String conversationId) async {}

  @override
  Future<void> removeGroupMember({
    required String conversationId,
    required String memberId,
  }) async {}

  @override
  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  ) {
    return _searchConversations(conversations, query);
  }

  @override
  Future<List<MessageSearchResult>> searchMessages(String query) async {
    return const [];
  }

  @override
  List<ChatMessage> searchThreadMessages(
    List<ChatMessage> messages,
    String query,
  ) {
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
  String? alias,
  String? avatarUrl,
}) {
  return Profile(
    id: id,
    username: username,
    displayName:
        displayName ??
        '${username[0].toUpperCase()}${username.substring(1)} Lovelace',
    alias: alias,
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

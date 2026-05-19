import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  testWidgets('shows loading and empty states', (tester) async {
    final completer = Completer<List<ConversationSummary>>();
    final repository = FakeChatsRepository()
      ..conversationsFuture = completer.future;

    await tester.pumpWidget(_app(repository));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pump();

    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('renders conversation rows with unread badges', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          avatarUrl: 'profile-avatars/user-2/ada.png',
          lastMessageBody: 'See you soon',
          lastMessageAt: DateTime.utc(2026, 5, 18, 4, 30),
          unreadCount: 2,
        ),
        const ConversationSummary(
          id: 'conversation-2',
          type: ConversationType.direct,
          title: 'Grace Hopper',
          lastMessageBody: null,
          unreadCount: 0,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('See you soon'), findsOneWidget);
    expect(find.text('04:30'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar).first);
    final image = avatar.backgroundImage;
    expect(image, isA<NetworkImage>());
    expect(
      (image! as NetworkImage).url,
      'https://signed.example.com/profile-avatars/user-2/ada.png',
    );
    expect(find.text('AL'), findsNothing);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('No messages yet'), findsOneWidget);
  });

  testWidgets('previews latest voice messages as voice', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: '',
          lastMessageType: MessageType.voice,
          lastMessageAt: DateTime.utc(2026, 5, 18, 4, 30),
          unreadCount: 0,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('[Voice]'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
  });

  testWidgets('renders conversation management indicators', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.group,
          title: 'Launch Crew',
          lastMessageBody: '[Image]',
          unreadCount: 0,
          pinnedAt: DateTime.utc(2026, 5, 18),
          isMuted: true,
          isMarkedUnread: true,
          memberCount: 3,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Launch Crew'), findsOneWidget);
    expect(find.text('[Image]'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    expect(find.text('3 members'), findsOneWidget);
    expect(find.byType(Badge), findsOneWidget);
  });

  testWidgets('conversation menu calls management actions', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: 'See you soon',
          unreadCount: 0,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Conversation actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin chat'));
    await tester.pump();

    await tester.tap(find.byTooltip('Conversation actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mute'));
    await tester.pump();

    await tester.tap(find.byTooltip('Conversation actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark unread'));
    await tester.pump();

    await tester.tap(find.byTooltip('Conversation actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete conversation'));
    await tester.pump();

    expect(repository.pinnedCalls, [
      const ConversationToggleCall(
        conversationId: 'conversation-1',
        value: true,
      ),
    ]);
    expect(repository.mutedCalls, [
      const ConversationToggleCall(
        conversationId: 'conversation-1',
        value: true,
      ),
    ]);
    expect(repository.markUnreadCalls, ['conversation-1']);
    expect(repository.hideCalls, ['conversation-1']);
  });

  testWidgets('shows safe deleted text for recalled latest messages', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: 'Message deleted',
          unreadCount: 0,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Message deleted'), findsOneWidget);
    expect(find.text('private secret'), findsNothing);
  });

  testWidgets('filters visible conversations by search query', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: 'Math notes',
          unreadCount: 0,
        ),
        const ConversationSummary(
          id: 'conversation-2',
          type: ConversationType.direct,
          title: 'Grace Hopper',
          lastMessageBody: 'Compiler update',
          unreadCount: 0,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.enterText(find.bySemanticsLabel('Search chats'), 'math');
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsNothing);
  });

  testWidgets('tapping a conversation passes the title to the thread route', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: 'See you soon',
          unreadCount: 0,
        ),
      ];
    final router = GoRouter(
      initialLocation: ChatsScreen.path,
      routes: [
        GoRoute(
          path: ChatsScreen.path,
          builder: (context, state) => const ChatsScreen(),
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

    await tester.pumpWidget(_app(repository, router: router));
    await tester.pump();

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();

    expect(find.text('Thread conversation-1 Ada Lovelace'), findsOneWidget);
  });
}

Widget _app(FakeChatsRepository repository, {GoRouter? router}) {
  final child = router == null
      ? const MaterialApp(home: ChatsScreen())
      : MaterialApp.router(routerConfig: router);

  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(repository),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
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

  @override
  Future<List<Profile>> listBlockedUsers() async {
    return const [];
  }

  @override
  Future<void> unblockUser(String userId) async {}
}

class FakeChatsRepository implements ChatsRepository {
  var conversations = <ConversationSummary>[];
  Future<List<ConversationSummary>>? conversationsFuture;
  final pinnedCalls = <ConversationToggleCall>[];
  final mutedCalls = <ConversationToggleCall>[];
  final markUnreadCalls = <String>[];
  final markReadCalls = <String>[];
  final hideCalls = <String>[];
  final _changes = StreamController<void>.broadcast();

  @override
  Future<List<ConversationSummary>> listConversations() {
    final future = conversationsFuture;
    if (future != null) {
      return future;
    }
    return Future.value(conversations);
  }

  @override
  Future<ConversationSummary?> getConversationSummary(
    String conversationId,
  ) async {
    for (final conversation in conversations) {
      if (conversation.id == conversationId) {
        return conversation;
      }
    }
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
  Future<void> markConversationRead(String conversationId) async {
    markReadCalls.add(conversationId);
  }

  @override
  Future<void> markConversationUnread(String conversationId) async {
    markUnreadCalls.add(conversationId);
  }

  @override
  Future<void> setConversationPinned({
    required String conversationId,
    required bool pinned,
  }) async {
    pinnedCalls.add(
      ConversationToggleCall(conversationId: conversationId, value: pinned),
    );
  }

  @override
  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) async {
    mutedCalls.add(
      ConversationToggleCall(conversationId: conversationId, value: muted),
    );
  }

  @override
  Future<void> hideConversation(String conversationId) async {
    hideCalls.add(conversationId);
  }

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
  Future<List<DiscoveryResult>> searchDiscovery(String query) async {
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
  Stream<void> conversationChanges() => _changes.stream;

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

class ConversationToggleCall {
  const ConversationToggleCall({
    required this.conversationId,
    required this.value,
  });

  final String conversationId;
  final bool value;

  @override
  bool operator ==(Object other) {
    return other is ConversationToggleCall &&
        other.conversationId == conversationId &&
        other.value == value;
  }

  @override
  int get hashCode => Object.hash(conversationId, value);
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

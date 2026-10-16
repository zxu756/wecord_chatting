import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/composer_drafts.dart';
import 'package:wecord/features/contacts/contacts_screen.dart';
import 'package:wecord/features/home/conversation_preview.dart';
import 'package:wecord/features/home/phone_messages_panel.dart';
import 'package:wecord/features/presence/presence_indicator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/link_preview.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/pinned_message.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/ui/ui.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  testWidgets('shows loading and empty states', (tester) async {
    final completer = Completer<List<ConversationSummary>>();
    final repository = FakeChatsRepository()
      ..conversationsFuture = completer.future;

    await tester.pumpWidget(_app(repository));

    expect(find.text('Messages'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const []);
    await tester.pump();

    expect(find.text('No conversations yet'), findsOneWidget);
  });

  testWidgets('renders conversation rows with previews, ages and badges', (
    tester,
  ) async {
    final sentAt = DateTime.now().subtract(const Duration(days: 9));
    final repository = FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          avatarUrl: 'profile-avatars/user-2/ada.png',
          lastMessageBody: 'See you soon',
          lastMessageSenderId: 'user-2',
          lastMessageAt: sentAt,
          unreadCount: 2,
          directUserId: 'user-2',
        ),
        const ConversationSummary(
          id: 'conversation-2',
          type: ConversationType.direct,
          title: 'Grace Hopper',
          lastMessageBody: 'On my way',
          lastMessageSenderId: 'me',
          unreadCount: 0,
          directUserId: 'user-3',
        ),
      ];

    await tester.pumpWidget(_app(repository, onlineUserIds: {'user-2'}));
    await tester.pump();
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('See you soon'), findsOneWidget);
    expect(find.text('9d'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    final avatar = tester.widget<PersonAvatar>(
      find.descendant(
        of: find.byKey(const ValueKey('home-dm-conversation-1')),
        matching: find.byType(PersonAvatar),
      ),
    );
    final image = avatar.image;
    expect(image, isA<NetworkImage>());
    expect(
      (image! as NetworkImage).url,
      'https://signed.example.com/profile-avatars/user-2/ada.png',
    );
    expect(find.text('AL'), findsNothing);
    // The user's own latest message.
    expect(find.text('You: On my way'), findsOneWidget);
  });

  test('ages are compact', () {
    final now = DateTime(2026, 10, 16, 12);
    String age(Duration ago) => compactAge(now.subtract(ago), now: now);
    expect(age(const Duration(seconds: 20)), 'now');
    expect(age(const Duration(minutes: 5)), '5m');
    expect(age(const Duration(hours: 3)), '3h');
    expect(age(const Duration(days: 9)), '9d');
    expect(age(const Duration(days: 40)), '1mo');
    expect(age(const Duration(days: 800)), '2y');
  });

  testWidgets('shows drafts, GIFs and presence statuses', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: 'See you soon',
          unreadCount: 0,
          directUserId: 'user-2',
        ),
        const ConversationSummary(
          id: 'conversation-2',
          type: ConversationType.direct,
          title: 'Grace Hopper',
          lastMessageBody: 'https://media.giphy.com/media/abc/giphy.gif',
          unreadCount: 0,
          directUserId: 'user-3',
        ),
        const ConversationSummary(
          id: 'conversation-3',
          type: ConversationType.direct,
          title: 'Linus',
          lastMessageBody: 'Later',
          unreadCount: 0,
          directUserId: 'user-4',
        ),
      ];

    await tester.pumpWidget(
      _app(
        repository,
        onlineUserIds: {'user-2', 'user-3'},
        statuses: {
          'user-2': PresenceStatus.doNotDisturb,
          'user-3': PresenceStatus.idle,
        },
        drafts: {'conversation-1': const ComposerDraft(text: 'half   written')},
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('conversation-draft')), findsOneWidget);
    expect(
      find.textContaining('Draft half written', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('See you soon'), findsNothing);
    expect(find.text('GIF'), findsOneWidget);

    PresenceStatus? statusIn(String conversationId) {
      return tester
          .widget<PresenceIndicator>(
            find.descendant(
              of: find.byKey(ValueKey('home-dm-$conversationId')),
              matching: find.byType(PresenceIndicator),
            ),
          )
          .status;
    }

    expect(statusIn('conversation-1'), PresenceStatus.doNotDisturb);
    expect(statusIn('conversation-2'), PresenceStatus.idle);
    // Offline (or invisible) people show no status.
    expect(statusIn('conversation-3'), isNull);
  });

  testWidgets('lists only direct and group chats', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'group-conversation',
          type: ConversationType.group,
          title: 'Hiking crew',
          unreadCount: 0,
          memberCount: 4,
        ),
        const ConversationSummary(
          id: 'channel-conversation',
          type: ConversationType.channel,
          title: 'general',
          unreadCount: 0,
        ),
        const ConversationSummary(
          id: 'thread-conversation',
          type: ConversationType.thread,
          title: 'Weekend plans',
          unreadCount: 3,
          parentConversationId: 'channel-conversation',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.pump();

    // Channels and their threads live in their circle.
    expect(find.text('Hiking crew'), findsOneWidget);
    // Groups without messages show their size instead.
    expect(find.text('4 members'), findsOneWidget);
    expect(find.text('general'), findsNothing);
    expect(find.text('Weekend plans'), findsNothing);
    expect(find.text('3'), findsNothing);
  });

  testWidgets('previews text messages without markdown markers', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          lastMessageBody: '**Ship** it ~~today~~ ||now||',
          lastMessageType: MessageType.text,
          lastMessageAt: DateTime.utc(2026, 5, 18, 4, 30),
          unreadCount: 0,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Ship it today [spoiler]'), findsOneWidget);
  });

  testWidgets('labels voice messages, images, videos, files and calls', (
    tester,
  ) async {
    ConversationSummary chat(String id, MessageType type, String body) {
      return ConversationSummary(
        id: id,
        type: ConversationType.direct,
        title: 'Chat $id',
        lastMessageBody: body,
        lastMessageType: type,
        lastMessageAt: DateTime.utc(2026, 5, 18, 4, 30),
        unreadCount: 0,
      );
    }

    final repository = FakeChatsRepository()
      ..conversations = [
        chat('voice', MessageType.voice, ''),
        chat('image', MessageType.image, '[Image]'),
        chat('file', MessageType.file, ''),
        ConversationSummary.fromJson({
          'id': 'video',
          'type': 'direct',
          'title': 'Chat video',
          'last_message_body': '',
          'last_message_type': 'file',
          'last_message_attachment_kind': 'video',
          'last_message_at': '2026-05-18T04:30:00Z',
          'unread_count': 0,
        }),
        chat(
          'call',
          MessageType.system,
          'Ada started a call that lasted 5 minutes.',
        ),
        chat('ringing', MessageType.system, 'Ada started a call.'),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Voice message'), findsOneWidget);
    expect(find.text('Image'), findsOneWidget);
    expect(find.text('File'), findsOneWidget);
    // Videos say so, with a video icon.
    expect(find.text('Video'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('home-dm-video')),
        matching: find.byIcon(Icons.videocam_outlined),
      ),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.call_outlined), findsNWidgets(2));
    expect(find.text('Call ended'), findsOneWidget);
    expect(find.text('Ada started a call'), findsOneWidget);
  });

  testWidgets('renders conversation management indicators', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.group,
          title: 'Launch Crew',
          lastMessageBody: '[Image]',
          lastMessageType: MessageType.image,
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
    expect(find.text('Image'), findsOneWidget);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.byIcon(Icons.push_pin), findsOneWidget);
    expect(find.byIcon(Icons.notifications_off_outlined), findsOneWidget);
    // The latest message replaces the member count.
    expect(find.text('3 members'), findsNothing);
    expect(find.byType(CountBadge), findsOneWidget);
  });

  testWidgets('long press opens the conversation actions', (tester) async {
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

    Future<void> pick(String action) async {
      await tester.longPress(find.text('Ada Lovelace'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action));
      await tester.pumpAndSettle();
    }

    await pick('Pin chat');
    await pick('Mute');
    await pick('Mark unread');
    await pick('Delete conversation');

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

  testWidgets('friends show online first and open their direct message', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-ada',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          unreadCount: 0,
          directUserId: 'user-2',
        ),
      ];
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      _app(
        repository,
        router: router,
        friends: [
          _friend('user-2', 'Ada Lovelace'),
          _friend('user-3', 'Grace'),
        ],
        onlineUserIds: {'user-3'},
      ),
    );
    await tester.pump();
    await tester.pump();

    final ada = find.byKey(const ValueKey('phone-friend-user-2'));
    final grace = find.byKey(const ValueKey('phone-friend-user-3'));
    expect(tester.getTopLeft(grace).dx, lessThan(tester.getTopLeft(ada).dx));

    // The existing conversation opens.
    await tester.tap(ada);
    await tester.pumpAndSettle();
    expect(find.text('Thread conversation-ada Ada Lovelace'), findsOneWidget);
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
    final router = _router();
    addTearDown(router.dispose);

    await tester.pumpWidget(_app(repository, router: router));
    await tester.pump();

    await tester.tap(find.text('Ada Lovelace'));
    await tester.pumpAndSettle();

    expect(find.text('Thread conversation-1 Ada Lovelace'), findsOneWidget);
  });
}

Profile _friend(String id, String name) {
  final now = DateTime.utc(2026, 5, 18);
  return Profile(
    id: id,
    username: name.toLowerCase().replaceAll(' ', ''),
    displayName: name,
    bio: '',
    createdAt: now,
    updatedAt: now,
  );
}

GoRouter _router() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      GoRoute(
        path: '/home',
        builder: (context, state) => const Scaffold(body: PhoneMessagesPanel()),
      ),
      GoRoute(
        path: '${ChatsScreen.path}/:conversationId',
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
}

Widget _app(
  FakeChatsRepository repository, {
  GoRouter? router,
  List<Profile> friends = const [],
  Set<String> onlineUserIds = const {},
  Map<String, PresenceStatus> statuses = const {},
  Map<String, ComposerDraft> drafts = const {},
}) {
  final child = router == null
      ? const MaterialApp(home: Scaffold(body: PhoneMessagesPanel()))
      : MaterialApp.router(routerConfig: router);

  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(repository),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      authStateProvider.overrideWith(
        (ref) => Stream.value(const AuthUser(id: 'me')),
      ),
      friendsProvider.overrideWith((ref) async => friends),
      incomingFriendRequestsProvider.overrideWith((ref) async => const []),
      onlineUserIdsProvider.overrideWith((ref) => Stream.value(onlineUserIds)),
      presenceStatusesProvider.overrideWith((ref) => Stream.value(statuses)),
      composerDraftStoreProvider.overrideWithValue(
        InMemoryComposerDraftStore({'me': drafts}),
      ),
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

  @override
  Future<void> setCustomStatus({
    String? emoji,
    String? text,
    DateTime? expiresAt,
  }) async {}
}

class FakeChatsRepository implements ChatsRepository {
  @override
  Future<void> createPoll({
    required String conversationId,
    required String question,
    required List<String> options,
    required bool multi,
    int? durationHours,
  }) async {}

  @override
  Future<void> votePoll({
    required String messageId,
    required List<String> optionIds,
  }) async {}

  @override
  Future<void> endPoll({required String messageId}) async {}

  @override
  Future<bool> canModeratePolls(String conversationId) async => false;

  @override
  Future<List<Profile>> listPollVoters({
    required String messageId,
    required String optionId,
  }) async => const [];

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

  final sentFiles =
      <({String conversationId, String fileName, String mimeType, int size})>[];

  @override
  Future<void> sendFileMessage({
    required String conversationId,
    required String fileName,
    required String mimeType,
    required Uint8List bytes,
  }) async {
    sentFiles.add((
      conversationId: conversationId,
      fileName: fileName,
      mimeType: mimeType,
      size: bytes.length,
    ));
  }

  @override
  Future<String> createFileUrl(FileAttachment attachment) async {
    return 'https://files.test/${attachment.path}';
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
  Future<void> sendSticker({
    required String conversationId,
    required String stickerId,
  }) async {}

  @override
  Future<bool> canModerateMessages(String conversationId) async => false;

  @override
  Future<void> recallMessage({required String messageId}) async {}

  @override
  Future<void> editMessage({
    required String messageId,
    required String body,
  }) async {}

  @override
  Future<void> toggleMessageReaction({
    required String messageId,
    required String emoji,
  }) async {}

  @override
  Future<List<Profile>> listMessageReactors({
    required String messageId,
    required String emoji,
  }) async {
    return const [];
  }

  @override
  Future<bool> canPinMessages(String conversationId) async => false;

  @override
  Future<void> pinMessage({required String messageId}) async {}

  @override
  Future<void> unpinMessage({required String messageId}) async {}

  @override
  Future<List<PinnedMessage>> listPinnedMessages(String conversationId) async {
    return const [];
  }

  @override
  Future<LinkPreview?> getLinkPreview(String url) async => null;

  @override
  Future<void> setMessageSuppressEmbeds({
    required String messageId,
    required bool suppress,
  }) async {}

  @override
  Future<ConversationThread> createThread({
    required String parentConversationId,
    String? rootMessageId,
    String? title,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ConversationThread>> listThreads(
    String parentConversationId,
  ) async => const [];

  @override
  Future<ConversationThread> setThreadArchived({
    required String threadId,
    required bool archived,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canManageThread(String threadId) async => false;

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
  Future<List<ConversationMediaItem>> listConversationMedia(
    String conversationId,
  ) async {
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

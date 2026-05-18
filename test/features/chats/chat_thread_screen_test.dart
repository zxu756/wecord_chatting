import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/navigation/app_router.dart';

void main() {
  testWidgets('renders existing messages in chronological bubbles', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Older message',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'Newer message',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('AL'), findsOneWidget);
    expect(find.text('Older message'), findsOneWidget);
    expect(find.text('Newer message'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Older message')).dy,
      lessThan(tester.getTopLeft(find.text('Newer message')).dy),
    );
    expect(
      tester.getCenter(find.text('Newer message')).dx,
      greaterThan(tester.getCenter(find.text('Older message')).dx),
    );
    expect(repository.markReadCalls, ['conversation-1']);
  });

  testWidgets('keeps the newest message closest to the composer', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Older message',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'Newer message',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    final composerTop = tester.getTopLeft(find.byType(TextField)).dy;
    final olderDistance =
        composerTop - tester.getBottomLeft(find.text('Older message')).dy;
    final newerDistance =
        composerTop - tester.getBottomLeft(find.text('Newer message')).dy;

    expect(newerDistance, lessThan(olderDistance));
    expect(newerDistance, lessThan(96));
  });

  testWidgets(
    'keeps the newest message closest when repository returns latest first',
    (tester) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-2',
            senderId: 'user-1',
            body: 'Newer message',
            createdAt: DateTime.utc(2026, 5, 18, 4, 31),
          ),
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body: 'Older message',
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          ),
        ];

      await tester.pumpWidget(_app(repository));
      await tester.pump();

      final composerTop = tester.getTopLeft(find.byType(TextField)).dy;
      final olderDistance =
          composerTop - tester.getBottomLeft(find.text('Older message')).dy;
      final newerDistance =
          composerTop - tester.getBottomLeft(find.text('Newer message')).dy;

      expect(
        tester.getTopLeft(find.text('Older message')).dy,
        lessThan(tester.getTopLeft(find.text('Newer message')).dy),
      );
      expect(newerDistance, lessThan(olderDistance));
      expect(newerDistance, lessThan(96));
    },
  );

  testWidgets('refreshes the visible thread when realtime emits a message', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Initial message',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Initial message'), findsOneWidget);

    repository.messages = [
      ...repository.messages,
      _message(
        id: 'message-2',
        senderId: 'user-2',
        body: 'Incoming message',
        createdAt: DateTime.utc(2026, 5, 18, 4, 31),
      ),
    ];
    repository.emitMessageChange();
    await tester.pump();
    await tester.pump();

    expect(find.text('Incoming message'), findsOneWidget);
  });

  testWidgets('shows online and typing activity from the peer', (tester) async {
    final repository = FakeChatsRepository()
      ..activity = const ConversationActivity(
        onlineUserIds: {'user-2'},
        typingUserIds: {'user-2'},
      );

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Online'), findsOneWidget);
    expect(find.text('typing...'), findsOneWidget);
  });

  testWidgets('sends typing activity while composing and clears it on send', (
    tester,
  ) async {
    final repository = FakeChatsRepository();

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(repository.typingUpdates, [
      const TypingUpdate(conversationId: 'conversation-1', isTyping: true),
      const TypingUpdate(conversationId: 'conversation-1', isTyping: false),
    ]);
  });

  testWidgets('shows read receipt for the latest outgoing message', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Incoming',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'Outgoing',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ]
      ..readMarkers = const [
        ConversationReadMarker(
          userId: 'user-2',
          lastReadMessageId: 'message-2',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Read'), findsOneWidget);
  });

  testWidgets('renders image messages and opens a preview', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: '',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          type: MessageType.image,
          attachment: const ImageAttachment(
            bucket: 'chat-images',
            path: 'conversation-1/photo.png',
            mimeType: 'image/png',
            size: 3,
          ).toJson(),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);

    await tester.tap(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.text('Image preview'), findsOneWidget);
    expect(repository.createdImageUrls, hasLength(1));
    expect(repository.createdImageUrls.single.bucket, 'chat-images');
    expect(repository.createdImageUrls.single.path, 'conversation-1/photo.png');
    expect(repository.createdImageUrls.single.mimeType, 'image/png');
  });

  testWidgets('picks and sends an image from the composer', (tester) async {
    final repository = FakeChatsRepository();
    final picker = FakeImagePickerService()
      ..nextImage = ChatImageUpload(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'Photo.PNG',
        mimeType: 'image/png',
      );

    await tester.pumpWidget(_app(repository, imagePickerService: picker));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pump();

    expect(picker.pickCalls, 1);
    expect(repository.sentImages, [
      SentImage(conversationId: 'conversation-1', image: picker.nextImage!),
    ]);
  });

  testWidgets('does not show upload progress while the image picker is open', (
    tester,
  ) async {
    final repository = FakeChatsRepository();
    final picker = FakeImagePickerService()
      ..pickCompleter = Completer<ChatImageUpload?>();

    await tester.pumpWidget(_app(repository, imagePickerService: picker));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, Icons.image_outlined),
          )
          .onPressed,
      isNotNull,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);

    picker.pickCompleter!.complete(null);
    await tester.pump();
  });

  testWidgets('failed local image read shows a local file error', (
    tester,
  ) async {
    final repository = FakeChatsRepository();
    final picker = FakeImagePickerService()
      ..pickError = const ImagePickerException(
        'Could not read the selected image from this Mac. Try moving it to a local folder and choosing it again.',
      );

    await tester.pumpWidget(_app(repository, imagePickerService: picker));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pump();

    expect(repository.sentImages, isEmpty);
    expect(
      find.textContaining('Could not read the selected image'),
      findsOneWidget,
    );
  });

  testWidgets('failed image send clears progress and shows the root error', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..sendError = Exception('storage denied');
    final picker = FakeImagePickerService()
      ..nextImage = ChatImageUpload(
        bytes: Uint8List.fromList([1, 2, 3]),
        fileName: 'Photo.PNG',
        mimeType: 'image/png',
      );

    await tester.pumpWidget(_app(repository, imagePickerService: picker));
    await tester.pump();

    await tester.tap(find.byIcon(Icons.image_outlined));
    await tester.pump();

    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    expect(find.textContaining('storage denied'), findsOneWidget);
  });

  testWidgets('long pressing a text message can copy it', (tester) async {
    String? copiedText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
            return null;
          }
          if (call.method == 'Clipboard.getData') {
            return {'text': copiedText};
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Copy this',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('Copy this'));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Delete'), findsNothing);

    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();

    expect(copiedText, 'Copy this');
  });

  testWidgets('long pressing an outgoing text message can delete it', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Remove this',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('Remove this'));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(repository.recalledMessageIds, ['message-1']);
  });

  testWidgets('recalled messages render deleted text and have no actions', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Already gone',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          recalledAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Message deleted'), findsOneWidget);
    expect(find.text('Already gone'), findsNothing);

    await tester.longPress(find.text('Message deleted'));
    await tester.pumpAndSettle();

    expect(find.text('Copy'), findsNothing);
    expect(find.text('Delete'), findsNothing);
  });

  testWidgets('image action menu can open preview', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: '',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          type: MessageType.image,
          attachment: const ImageAttachment(
            bucket: 'chat-images',
            path: 'conversation-1/photo.png',
            mimeType: 'image/png',
            size: 3,
          ).toJson(),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.byType(Image));
    await tester.pumpAndSettle();

    expect(find.text('Preview'), findsOneWidget);

    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(find.text('Image preview'), findsOneWidget);
  });

  testWidgets('empty composer does not send', (tester) async {
    final repository = FakeChatsRepository();

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(repository.sentMessages, isEmpty);
  });

  testWidgets('non-empty composer sends trimmed text and clears input', (
    tester,
  ) async {
    final repository = FakeChatsRepository();

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '  Hello Ada  ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(repository.sentMessages, [
      const SentMessage(conversationId: 'conversation-1', body: 'Hello Ada'),
    ]);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('failed send shows retryable error text', (tester) async {
    final repository = FakeChatsRepository()..sendError = Exception('offline');

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Hello Ada');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(find.text('Could not send message. Try again.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Hello Ada',
    );
  });

  testWidgets('app router builds a chat thread for chat routes', (
    tester,
  ) async {
    final repository = FakeChatsRepository();
    final authRepository = FakeAuthRepository()
      ..user = const AuthUser(id: 'user-1', email: 'me@example.com');
    final authState = StreamController<AuthUser?>();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(authRepository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    router.go('/chats/conversation-1');
    await tester.pumpAndSettle();

    expect(find.byType(ChatThreadScreen), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
  });

  testWidgets('app router passes route extra as the thread title', (
    tester,
  ) async {
    final repository = FakeChatsRepository();
    final authRepository = FakeAuthRepository()
      ..user = const AuthUser(id: 'user-1', email: 'me@example.com');
    final authState = StreamController<AuthUser?>();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(authRepository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    router.go('/chats/conversation-1', extra: 'Ada Lovelace');
    await tester.pumpAndSettle();

    expect(find.byType(ChatThreadScreen), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsOneWidget);
  });

  testWidgets('app router passes route extra avatarUrl to the thread', (
    tester,
  ) async {
    final repository = FakeChatsRepository();
    final authRepository = FakeAuthRepository()
      ..user = const AuthUser(id: 'user-1', email: 'me@example.com');
    final authState = StreamController<AuthUser?>();
    late GoRouter router;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          authRepositoryProvider.overrideWithValue(authRepository),
          authStateProvider.overrideWith((ref) => authState.stream),
        ],
        child: Consumer(
          builder: (context, ref, child) {
            router = ref.watch(appRouterProvider);
            return MaterialApp.router(routerConfig: router);
          },
        ),
      ),
    );

    authState.add(const AuthUser(id: 'user-1', email: 'me@example.com'));
    await tester.pumpAndSettle();

    router.go(
      '/chats/conversation-1',
      extra: const ChatThreadRouteExtra(
        title: 'Ada Lovelace',
        type: ConversationType.direct,
        avatarUrl: 'https://example.com/ada.png',
      ),
    );
    await tester.pumpAndSettle();

    final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
    final image = avatar.backgroundImage;
    expect(image, isA<NetworkImage>());
    expect((image! as NetworkImage).url, 'https://example.com/ada.png');
  });

  testWidgets('does not show group details for direct conversations', (
    tester,
  ) async {
    final repository = FakeChatsRepository();

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.byTooltip('Group details'), findsNothing);
  });

  testWidgets('opens group details from the chat app bar', (tester) async {
    final repository = FakeChatsRepository()
      ..groupDetail = GroupDetail(
        conversationId: 'conversation-1',
        title: 'Launch Crew',
        members: [
          GroupMember(
            profile: _profile(
              id: 'friend-1',
              username: 'grace',
              displayName: 'Grace Hopper',
            ),
            role: 'owner',
          ),
          GroupMember(
            profile: _profile(
              id: 'friend-2',
              username: 'ada',
              displayName: 'Ada Lovelace',
            ),
            role: 'member',
          ),
        ],
      );

    await tester.pumpWidget(
      _app(repository, conversationType: ConversationType.group),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Group details'));
    await tester.pumpAndSettle();

    expect(find.text('Group members'), findsOneWidget);
    expect(find.text('Launch Crew'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('Ada Lovelace'), findsWidgets);
  });
}

Widget _app(
  FakeChatsRepository repository, {
  ImagePickerService? imagePickerService,
  ConversationType? conversationType,
}) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(repository),
      if (imagePickerService != null)
        imagePickerServiceProvider.overrideWithValue(imagePickerService),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository()
          ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
      ),
    ],
    child: MaterialApp(
      home: ChatThreadScreen(
        conversationId: 'conversation-1',
        title: 'Ada Lovelace',
        conversationType: conversationType,
      ),
    ),
  );
}

ChatMessage _message({
  required String id,
  required String senderId,
  required String body,
  required DateTime createdAt,
  MessageType type = MessageType.text,
  Map<String, dynamic>? attachment,
  DateTime? recalledAt,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: type,
    body: body,
    attachment: attachment,
    createdAt: createdAt,
    recalledAt: recalledAt,
  );
}

class FakeChatsRepository implements ChatsRepository {
  var conversations = <ConversationSummary>[];
  var messages = <ChatMessage>[];
  var readMarkers = <ConversationReadMarker>[];
  var activity = const ConversationActivity();
  GroupDetail? groupDetail;
  Object? sendError;
  final sentMessages = <SentMessage>[];
  final sentImages = <SentImage>[];
  final createdImageUrls = <ImageAttachment>[];
  final recalledMessageIds = <String>[];
  final typingUpdates = <TypingUpdate>[];
  final markReadCalls = <String>[];
  final _conversationChanges = StreamController<void>.broadcast();
  final _messageChanges = StreamController<void>.broadcast();
  final _activityChanges = StreamController<ConversationActivity>.broadcast();

  @override
  Future<List<ConversationSummary>> listConversations() async => conversations;

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async {
    return messages;
  }

  @override
  Future<List<ConversationReadMarker>> listReadMarkers(
    String conversationId,
  ) async {
    return readMarkers;
  }

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) async {
    return 'conversation-for-$otherUserId';
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
  }) async {
    if (sendError case final error?) {
      throw error;
    }
    sentMessages.add(SentMessage(conversationId: conversationId, body: body));
  }

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  }) async {
    if (sendError case final error?) {
      throw error;
    }
    sentImages.add(SentImage(conversationId: conversationId, image: image));
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) async {
    createdImageUrls.add(attachment);
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
  Future<GroupDetail> getGroupDetail(String conversationId) async {
    return groupDetail ??
        GroupDetail(
          conversationId: conversationId,
          title: conversationId,
          members: const [],
        );
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
  Future<void> recallMessage({required String messageId}) async {
    recalledMessageIds.add(messageId);
  }

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
  Stream<void> conversationChanges() => _conversationChanges.stream;

  @override
  Stream<void> messageChanges(String conversationId) => _messageChanges.stream;

  @override
  Stream<void> threadChanges(String conversationId) => _messageChanges.stream;

  @override
  Stream<ConversationActivity> conversationActivity(String conversationId) {
    Future<void>.microtask(() {
      _activityChanges.add(activity);
    });
    return _activityChanges.stream;
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {
    typingUpdates.add(
      TypingUpdate(conversationId: conversationId, isTyping: isTyping),
    );
  }

  void emitMessageChange() {
    _messageChanges.add(null);
  }
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

class SentMessage {
  const SentMessage({required this.conversationId, required this.body});

  final String conversationId;
  final String body;

  @override
  bool operator ==(Object other) {
    return other is SentMessage &&
        other.conversationId == conversationId &&
        other.body == body;
  }

  @override
  int get hashCode => Object.hash(conversationId, body);
}

class SentImage {
  const SentImage({required this.conversationId, required this.image});

  final String conversationId;
  final ChatImageUpload image;

  @override
  bool operator ==(Object other) {
    return other is SentImage &&
        other.conversationId == conversationId &&
        identical(other.image, image);
  }

  @override
  int get hashCode => Object.hash(conversationId, identityHashCode(image));
}

class TypingUpdate {
  const TypingUpdate({required this.conversationId, required this.isTyping});

  final String conversationId;
  final bool isTyping;

  @override
  bool operator ==(Object other) {
    return other is TypingUpdate &&
        other.conversationId == conversationId &&
        other.isTyping == isTyping;
  }

  @override
  int get hashCode => Object.hash(conversationId, isTyping);
}

class FakeImagePickerService implements ImagePickerService {
  ChatImageUpload? nextImage;
  Completer<ChatImageUpload?>? pickCompleter;
  Object? pickError;
  var pickCalls = 0;

  @override
  Future<ChatImageUpload?> pickImage() async {
    pickCalls += 1;
    final error = pickError;
    if (error != null) {
      throw error;
    }
    final completer = pickCompleter;
    if (completer != null) {
      return completer.future;
    }
    return nextImage;
  }
}

class FakeAuthRepository implements AuthRepository {
  final _controller = StreamController<AuthUser?>.broadcast();
  AuthUser? user;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => _controller.stream;

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> ensureCurrentUserProfile() async {}

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {}
}

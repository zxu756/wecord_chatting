import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/pinned_message.dart';
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

  testWidgets('searches the current thread and filters visible messages', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Project kickoff',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'Lunch later',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ];

    await tester.pumpWidget(_app(repository, title: null));
    await tester.pump();

    await tester.tap(find.byTooltip('Search messages'));
    await tester.pump();
    await tester.enterText(find.bySemanticsLabel('Search messages'), 'project');
    await tester.pump();

    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Project kickoff'), findsOneWidget);
    expect(find.text('Lunch later'), findsNothing);
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

  testWidgets('draws a NEW divider before the first unread incoming message', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Already read',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'My reply',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
        _message(
          id: 'message-3',
          senderId: 'user-2',
          body: 'First unread',
          createdAt: DateTime.utc(2026, 5, 18, 4, 32),
        ),
        _message(
          id: 'message-4',
          senderId: 'user-2',
          body: 'Second unread',
          createdAt: DateTime.utc(2026, 5, 18, 4, 33),
        ),
      ]
      ..readMarkers = const [
        ConversationReadMarker(
          userId: 'user-1',
          lastReadMessageId: 'message-1',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('NEW'), findsOneWidget);
    final dividerY = tester.getCenter(find.text('NEW')).dy;
    expect(dividerY, greaterThan(tester.getCenter(find.text('My reply')).dy));
    expect(dividerY, lessThan(tester.getCenter(find.text('First unread')).dy));

    // Opening the thread marks it read; the divider must survive the refresh.
    repository.readMarkers = const [
      ConversationReadMarker(userId: 'user-1', lastReadMessageId: 'message-4'),
    ];
    repository.emitMessageChange();
    await tester.pump();
    await tester.pump();

    expect(find.text('NEW'), findsOneWidget);
    expect(
      tester.getCenter(find.text('NEW')).dy,
      lessThan(tester.getCenter(find.text('First unread')).dy),
    );
  });

  group('consecutive message grouping', () {
    final grace = _profile(
      id: 'user-2',
      username: 'grace',
      displayName: 'Grace Hopper',
    );
    final alan = _profile(
      id: 'user-3',
      username: 'alan',
      displayName: 'Alan Turing',
    );

    testWidgets('shows the sender once per group in group chats', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            sender: grace,
            body: 'First',
            createdAt: DateTime.utc(2026, 5, 18, 10, 0),
          ),
          _message(
            id: 'message-2',
            senderId: 'user-2',
            sender: grace,
            body: 'Second',
            createdAt: DateTime.utc(2026, 5, 18, 10, 4),
          ),
          _message(
            id: 'message-3',
            senderId: 'user-2',
            sender: grace,
            body: 'Third',
            createdAt: DateTime.utc(2026, 5, 18, 10, 11),
          ),
          _message(
            id: 'message-4',
            senderId: 'user-3',
            sender: alan,
            body: 'Interjection',
            createdAt: DateTime.utc(2026, 5, 18, 10, 12),
          ),
          _message(
            id: 'message-5',
            senderId: 'user-2',
            sender: grace,
            body: 'Back again',
            createdAt: DateTime.utc(2026, 5, 18, 10, 13),
          ),
        ];

      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.group),
      );
      await tester.pump();
      await tester.pump();

      // Grace starts two groups, Alan one; follow-ups carry no name.
      expect(find.text('Grace Hopper'), findsNWidgets(2));
      expect(find.text('Alan Turing'), findsOneWidget);
      expect(find.text('GH'), findsNWidgets(2));
      expect(find.text('AT'), findsOneWidget);

      // Grouped messages sit closer together than separate groups.
      double gapBetween(String upper, String lower) {
        return tester.getTopLeft(find.text(lower)).dy -
            tester.getBottomLeft(find.text(upper)).dy;
      }

      expect(
        gapBetween('First', 'Second'),
        lessThan(gapBetween('Third', 'Interjection')),
      );

      // Follow-up bubbles line up with the first one in the group.
      expect(
        tester.getTopLeft(find.text('Second')).dx,
        tester.getTopLeft(find.text('First')).dx,
      );
    });

    testWidgets('starts a new group after seven minutes', (tester) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            sender: grace,
            body: 'Before the break',
            createdAt: DateTime.utc(2026, 5, 18, 10, 0),
          ),
          _message(
            id: 'message-2',
            senderId: 'user-2',
            sender: grace,
            body: 'Exactly seven later',
            createdAt: DateTime.utc(2026, 5, 18, 10, 7),
          ),
          _message(
            id: 'message-3',
            senderId: 'user-2',
            sender: grace,
            body: 'Eight minutes later',
            createdAt: DateTime.utc(2026, 5, 18, 10, 15),
          ),
        ];

      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.channel),
      );
      await tester.pump();

      expect(find.text('Grace Hopper'), findsNWidgets(2));
    });

    testWidgets('NEW divider, system notices and day changes break groups', (
      tester,
    ) async {
      final lateEvening = DateTime(2026, 5, 18, 23, 57).toUtc();
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            sender: grace,
            body: 'Read already',
            createdAt: DateTime.utc(2026, 5, 18, 10, 0),
          ),
          _message(
            id: 'message-2',
            senderId: 'user-2',
            sender: grace,
            body: 'Unread one',
            createdAt: DateTime.utc(2026, 5, 18, 10, 1),
          ),
          _message(
            id: 'message-3',
            senderId: 'user-1',
            type: MessageType.system,
            body: 'Ada pinned a message.',
            createdAt: DateTime.utc(2026, 5, 18, 10, 2),
          ),
          _message(
            id: 'message-4',
            senderId: 'user-2',
            sender: grace,
            body: 'After the notice',
            createdAt: DateTime.utc(2026, 5, 18, 10, 3),
          ),
          _message(
            id: 'message-5',
            senderId: 'user-2',
            sender: grace,
            body: 'Before midnight',
            createdAt: lateEvening,
          ),
          _message(
            id: 'message-6',
            senderId: 'user-2',
            sender: grace,
            body: 'After midnight',
            createdAt: lateEvening.add(const Duration(minutes: 5)),
          ),
        ]
        ..readMarkers = const [
          ConversationReadMarker(
            userId: 'user-1',
            lastReadMessageId: 'message-1',
          ),
        ];

      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.group),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('NEW'), findsOneWidget);
      // One header for each of the five groups the breaks create.
      expect(find.text('Grace Hopper'), findsNWidgets(5));
    });

    testWidgets('direct chats never show sender headers', (tester) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            sender: grace,
            body: 'Hello',
            createdAt: DateTime.utc(2026, 5, 18, 10, 0),
          ),
          _message(
            id: 'message-2',
            senderId: 'user-2',
            sender: grace,
            body: 'Again',
            createdAt: DateTime.utc(2026, 5, 18, 10, 1),
          ),
        ];

      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.direct),
      );
      await tester.pump();

      expect(find.text('Grace Hopper'), findsNothing);
      expect(find.text('GH'), findsNothing);
    });

    testWidgets('follow-up messages keep reactions, receipts and actions', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..canPin = true
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            sender: grace,
            body: 'Lead',
            createdAt: DateTime.utc(2026, 5, 18, 10, 0),
          ),
          _message(
            id: 'message-2',
            senderId: 'user-2',
            sender: grace,
            body: 'Follow-up',
            createdAt: DateTime.utc(2026, 5, 18, 10, 1),
            reactions: const [
              MessageReaction(emoji: '👍', count: 2, reactedByMe: true),
            ],
            replyPreview: const ReplyPreview(
              messageId: 'message-1',
              senderName: 'Grace Hopper',
              body: 'Lead',
              type: MessageType.text,
            ),
          ),
          _message(
            id: 'message-3',
            senderId: 'user-1',
            body: 'Mine',
            createdAt: DateTime.utc(2026, 5, 18, 10, 2),
          ),
          _message(
            id: 'message-4',
            senderId: 'user-1',
            body: 'Mine too',
            createdAt: DateTime.utc(2026, 5, 18, 10, 3),
          ),
        ]
        ..readMarkers = const [
          ConversationReadMarker(
            userId: 'user-2',
            lastReadMessageId: 'message-4',
          ),
        ];

      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.group),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Grace Hopper'), findsNWidgets(2)); // header + quote
      expect(find.text('2'), findsOneWidget);
      expect(find.text('Read'), findsOneWidget);

      await tester.longPress(find.text('Follow-up'));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      expect(repository.pinnedMessageIds, ['message-2']);
    });
  });

  testWidgets('omits the NEW divider when everything was already read', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Read message',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'My own newer message',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ]
      ..readMarkers = const [
        ConversationReadMarker(
          userId: 'user-1',
          lastReadMessageId: 'message-1',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('NEW'), findsNothing);

    repository.messages = [
      ...repository.messages,
      _message(
        id: 'message-3',
        senderId: 'user-2',
        body: 'Arrived while open',
        createdAt: DateTime.utc(2026, 5, 18, 4, 32),
      ),
    ];
    repository.emitMessageChange();
    await tester.pump();
    await tester.pump();

    expect(find.text('Arrived while open'), findsOneWidget);
    expect(find.text('NEW'), findsNothing);
  });

  testWidgets('jump to latest appears with a count when scrolled up', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        for (var index = 0; index < 30; index++)
          _message(
            id: 'message-$index',
            senderId: index.isEven ? 'user-2' : 'user-1',
            body: 'History $index',
            createdAt: DateTime.utc(
              2026,
              5,
              18,
              4,
            ).add(Duration(minutes: index)),
          ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.byTooltip('Jump to latest'), findsNothing);

    await tester.drag(
      find.byKey(const ValueKey('chat-message-list')),
      const Offset(0, 400),
    );
    await tester.pump();

    // Scrolled up but nothing new yet.
    expect(find.byTooltip('Jump to latest'), findsNothing);

    repository.messages = [
      ...repository.messages,
      _message(
        id: 'message-30',
        senderId: 'user-2',
        body: 'Fresh one',
        createdAt: DateTime.utc(2026, 5, 18, 5),
      ),
      _message(
        id: 'message-31',
        senderId: 'user-2',
        body: 'Fresh two',
        createdAt: DateTime.utc(2026, 5, 18, 5, 1),
      ),
    ];
    repository.emitMessageChange();
    await tester.pump();
    await tester.pump();

    expect(find.byTooltip('Jump to latest'), findsOneWidget);
    expect(find.text('2 new messages'), findsOneWidget);

    await tester.tap(find.byTooltip('Jump to latest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byTooltip('Jump to latest'), findsNothing);
    expect(find.text('Fresh two'), findsOneWidget);
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

  testWidgets('search does not move the read receipt to an older result', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Project kickoff',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'Latest outgoing',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ]
      ..readMarkers = const [
        ConversationReadMarker(
          userId: 'user-2',
          lastReadMessageId: 'message-1',
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Search messages'));
    await tester.pump();
    await tester.enterText(find.bySemanticsLabel('Search messages'), 'project');
    await tester.pump();

    expect(find.text('Project kickoff'), findsOneWidget);
    expect(find.text('Latest outgoing'), findsNothing);
    expect(find.text('Read'), findsNothing);
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

  testWidgets('composer can record and send a voice message', (tester) async {
    final repository = FakeChatsRepository();
    final recorder = FakeVoiceMessageRecorder()
      ..nextRecording = RecordedVoiceMessage(
        bytes: Uint8List.fromList([4, 5, 6]),
        mimeType: 'audio/mp4',
        durationMs: 4200,
      );

    await tester.pumpWidget(_app(repository, voiceMessageRecorder: recorder));
    await tester.pump();

    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pump();
    expect(find.text('Recording...'), findsOneWidget);

    await tester.tap(find.byTooltip('Send voice message'));
    await tester.pumpAndSettle();

    expect(recorder.startCalls, 1);
    expect(recorder.stopCalls, 1);
    expect(repository.sentVoiceMessages, [
      SentVoiceMessage(
        conversationId: 'conversation-1',
        bytes: Uint8List.fromList([4, 5, 6]),
        mimeType: 'audio/mp4',
        durationMs: 4200,
      ),
    ]);
  });

  testWidgets('keeps the active voice recorder alive while mounted', (
    tester,
  ) async {
    final repository = FakeChatsRepository();
    final createdRecorders = <FakeVoiceMessageRecorder>[];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          chatsRepositoryProvider.overrideWithValue(repository),
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
          voiceMessageRecorderProvider.overrideWith((ref) {
            final recorder = FakeVoiceMessageRecorder()
              ..nextRecording = RecordedVoiceMessage(
                bytes: Uint8List.fromList([9, 8, 7]),
                mimeType: 'audio/wav',
                durationMs: 1200,
              );
            createdRecorders.add(recorder);
            return recorder;
          }),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository()
              ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
          ),
        ],
        child: const MaterialApp(
          home: ChatThreadScreen(
            conversationId: 'conversation-1',
            title: 'Ada Lovelace',
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pump();
    await tester.tap(find.byTooltip('Send voice message'));
    await tester.pumpAndSettle();

    expect(createdRecorders, hasLength(1));
    expect(createdRecorders.single.startCalls, 1);
    expect(createdRecorders.single.stopCalls, 1);
    expect(repository.sentVoiceMessages.single.mimeType, 'audio/wav');
  });

  testWidgets('cancels an active voice recording when disposed', (
    tester,
  ) async {
    final repository = FakeChatsRepository();
    final recorder = FakeVoiceMessageRecorder();

    await tester.pumpWidget(_app(repository, voiceMessageRecorder: recorder));
    await tester.pump();

    await tester.tap(find.byTooltip('Record voice message'));
    await tester.pump();
    expect(find.text('Recording...'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(recorder.cancelCalls, 1);
  });

  testWidgets('voice messages render a playback control', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: '',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          type: MessageType.voice,
          attachment: const VoiceAttachment(
            bucket: 'voice-messages',
            path: 'conversation-1/message-1.m4a',
            mimeType: 'audio/mp4',
            size: 3,
            durationMs: 4200,
          ).toJson(),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.byTooltip('Play voice message'), findsOneWidget);
    expect(find.text('0:04'), findsOneWidget);
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

  testWidgets('renders system notices as a centered line without actions', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..canPin = true
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'The plan',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          type: MessageType.system,
          body: 'Grace pinned a message.',
          attachment: const {'kind': 'pin', 'message_id': 'message-1'},
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    final noticeCenter = tester.getCenter(find.text('Grace pinned a message.'));
    final screenWidth = tester.getSize(find.byType(Scaffold)).width;
    expect(noticeCenter.dx, closeTo(screenWidth / 2, 24));
    // A system notice is never the latest outgoing message.
    expect(find.text('Read'), findsNothing);

    await tester.longPress(find.text('Grace pinned a message.'));
    await tester.pumpAndSettle();

    expect(find.text('Reply'), findsNothing);
    expect(find.text('Pin'), findsNothing);
  });

  testWidgets('pins a message from the action menu when permitted', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..canPin = true
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Pin me',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('Pin me'));
    await tester.pumpAndSettle();
    expect(find.text('Unpin'), findsNothing);
    await tester.tap(find.text('Pin'));
    await tester.pumpAndSettle();

    expect(repository.pinnedMessageIds, ['message-1']);
  });

  testWidgets('unpins an already pinned message from the action menu', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..canPin = true
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Pinned already',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          isPinned: true,
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('Pinned already'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Unpin'));
    await tester.pumpAndSettle();

    expect(repository.unpinnedMessageIds, ['message-1']);
    expect(repository.pinnedMessageIds, isEmpty);
  });

  testWidgets('hides pin actions when the user cannot pin', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Not mine to pin',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('Not mine to pin'));
    await tester.pumpAndSettle();

    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Pin'), findsNothing);
    expect(find.text('Unpin'), findsNothing);
  });

  testWidgets('pin limit shows a snackbar', (tester) async {
    final repository = FakeChatsRepository()
      ..canPin = true
      ..pinError = const PinnedMessageLimitException()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'One too many',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('One too many'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pin'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('This conversation already has 50 pinned messages.'),
      findsOneWidget,
    );
  });

  testWidgets('pinned list scrolls to and highlights the original message', (
    tester,
  ) async {
    final messages = [
      for (var index = 0; index < 40; index++)
        _message(
          id: 'message-$index',
          senderId: index.isEven ? 'user-2' : 'user-1',
          body: 'History $index',
          createdAt: DateTime.utc(2026, 5, 18, 4).add(Duration(minutes: index)),
        ),
    ];
    final repository = FakeChatsRepository()
      ..messages = messages
      ..pinnedMessages = [
        PinnedMessage(
          message: messages.first.copyWith(isPinned: true),
          sender: _profile(id: 'user-2', username: 'ada'),
          pinnedBy: 'user-1',
          pinnedByName: 'Grace',
          pinnedAt: DateTime.utc(2026, 5, 18, 6),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    // The oldest message is far above the viewport and not built yet.
    expect(find.text('History 0'), findsNothing);

    await tester.tap(find.byTooltip('Pinned messages'));
    await tester.pumpAndSettle();

    expect(find.text('Pinned messages'), findsOneWidget);
    expect(find.text('Pinned by Grace'), findsOneWidget);
    expect(find.byTooltip('Unpin'), findsNothing);

    await tester.tap(find.text('History 0'));
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('Pinned messages'), findsNothing);
    final target = find.text('History 0');
    expect(target, findsOneWidget);
    final targetY = tester.getCenter(target).dy;
    expect(targetY, greaterThan(0));
    expect(targetY, lessThan(tester.getSize(find.byType(Scaffold)).height));

    Color? highlightColor() {
      final container = tester.widget<AnimatedContainer>(
        find
            .ancestor(of: target, matching: find.byType(AnimatedContainer))
            .first,
      );
      return (container.decoration as BoxDecoration?)?.color;
    }

    expect(highlightColor(), isNot(Colors.transparent));

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));

    expect(highlightColor(), Colors.transparent);
  });

  testWidgets('tapping a pin notice scrolls to the pinned message', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        for (var index = 0; index < 40; index++)
          _message(
            id: 'message-$index',
            senderId: index.isEven ? 'user-2' : 'user-1',
            body: 'History $index',
            createdAt: DateTime.utc(
              2026,
              5,
              18,
              4,
            ).add(Duration(minutes: index)),
          ),
        _message(
          id: 'notice',
          senderId: 'user-2',
          type: MessageType.system,
          body: 'Ada pinned a message.',
          attachment: const {'kind': 'pin', 'message_id': 'message-0'},
          createdAt: DateTime.utc(2026, 5, 18, 6),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('History 0'), findsNothing);

    await tester.tap(find.text('Ada pinned a message.'));
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.text('History 0'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('opening a pinned message that is not loaded shows a snackbar', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Loaded message',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ]
      ..pinnedMessages = [
        PinnedMessage(
          message: _message(
            id: 'message-old',
            senderId: 'user-2',
            body: 'Ancient history',
            createdAt: DateTime.utc(2026, 1, 1),
            isPinned: true,
          ),
          sender: _profile(id: 'user-2', username: 'ada'),
          pinnedAt: DateTime.utc(2026, 5, 18, 6),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Pinned messages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ancient history'));
    await tester.pumpAndSettle();

    expect(find.text('That message is not loaded.'), findsOneWidget);
  });

  testWidgets('pinned list can unpin when permitted', (tester) async {
    final pinned = _message(
      id: 'message-1',
      senderId: 'user-2',
      body: 'Pinned body',
      createdAt: DateTime.utc(2026, 5, 18, 4, 30),
      isPinned: true,
    );
    final repository = FakeChatsRepository()
      ..canPin = true
      ..messages = [pinned]
      ..pinnedMessages = [
        PinnedMessage(
          message: pinned,
          sender: _profile(id: 'user-2', username: 'ada'),
          pinnedAt: DateTime.utc(2026, 5, 18, 6),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.tap(find.byTooltip('Pinned messages'));
    await tester.pumpAndSettle();

    repository.pinnedMessages = [];
    await tester.tap(find.byTooltip('Unpin'));
    await tester.pumpAndSettle();

    expect(repository.unpinnedMessageIds, ['message-1']);
    expect(find.text('No pinned messages yet'), findsOneWidget);
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

  testWidgets('renders reaction chips and highlights my reactions', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'React to me',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          reactions: const [
            MessageReaction(emoji: '👍', count: 2, reactedByMe: true),
            MessageReaction(emoji: '🎉', count: 1),
          ],
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.byKey(const ValueKey('reaction-chip-👍')), findsOneWidget);
    expect(find.byKey(const ValueKey('reaction-chip-🎉')), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);

    final colorScheme = Theme.of(
      tester.element(find.text('React to me')),
    ).colorScheme;
    Material chipMaterial(String emoji) {
      return tester.widget<Material>(
        find.descendant(
          of: find.byKey(ValueKey('reaction-chip-$emoji')),
          matching: find.byType(Material),
        ),
      );
    }

    expect(chipMaterial('👍').color, colorScheme.primaryContainer);
    expect(chipMaterial('🎉').color, colorScheme.surfaceContainerHighest);
  });

  testWidgets('tapping a reaction chip toggles it and refreshes the thread', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'React to me',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          reactions: const [MessageReaction(emoji: '🎉', count: 1)],
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    repository.messages = [
      _message(
        id: 'message-1',
        senderId: 'user-2',
        body: 'React to me',
        createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        reactions: const [
          MessageReaction(emoji: '🎉', count: 2, reactedByMe: true),
        ],
      ),
    ];
    await tester.tap(find.byKey(const ValueKey('reaction-chip-🎉')));
    await tester.pumpAndSettle();

    expect(repository.toggledReactions, [('message-1', '🎉')]);
    expect(find.text('2'), findsOneWidget);
  });

  testWidgets('long pressing a reaction chip lists who reacted', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..reactors = [
        _profile(id: 'user-2', username: 'grace', displayName: 'Grace Hopper'),
      ]
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'React to me',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          reactions: const [MessageReaction(emoji: '😂', count: 1)],
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.byKey(const ValueKey('reaction-chip-😂')));
    await tester.pumpAndSettle();

    expect(repository.reactorRequests, [('message-1', '😂')]);
    expect(find.text('Reacted with 😂'), findsOneWidget);
    expect(find.text('Grace Hopper'), findsOneWidget);
    expect(find.text('@grace'), findsOneWidget);
    expect(repository.toggledReactions, isEmpty);
  });

  testWidgets('action menu quick reactions toggle the chosen emoji', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'React to me',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('React to me'));
    await tester.pumpAndSettle();

    for (final emoji in ['👍', '❤️', '😂', '😮', '😢', '🎉']) {
      expect(find.text(emoji), findsOneWidget);
    }
    expect(find.byTooltip('More reactions'), findsOneWidget);

    await tester.tap(find.text('❤️'));
    await tester.pumpAndSettle();

    expect(repository.toggledReactions, [('message-1', '❤️')]);
    expect(find.text('Reply'), findsNothing);
  });

  testWidgets('more reactions opens the picker and toggles the pick', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'React to me',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('React to me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More reactions'));
    await tester.pumpAndSettle();

    expect(find.text('Add reaction'), findsOneWidget);

    await tester.tap(find.text('🤔'));
    await tester.pumpAndSettle();

    expect(repository.toggledReactions, [('message-1', '🤔')]);
    expect(find.text('Add reaction'), findsNothing);
  });

  testWidgets('recalled messages hide their reaction chips', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Gone',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          recalledAt: DateTime.utc(2026, 5, 18, 4, 31),
          reactions: const [MessageReaction(emoji: '👍', count: 1)],
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Message deleted'), findsOneWidget);
    expect(find.byKey(const ValueKey('reaction-chip-👍')), findsNothing);
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

  testWidgets('replies to a message from the action menu', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Original',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();

    expect(find.text('Replying to Original'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'A reply');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(repository.sentReplyToMessageId, 'message-1');
    expect(repository.sentReplyPreview?.messageId, 'message-1');
    expect(repository.sentReplyPreview?.body, 'Original');
    expect(repository.sentReplyPreview?.type, MessageType.text);
    expect(find.text('Replying to Original'), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('message action menu can open the forward sheet', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'hello',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();

    expect(find.text('Forward to'), findsOneWidget);
  });

  testWidgets('forward sheet filters target conversations by title only', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          title: 'Ada Lovelace',
          unreadCount: 0,
        ),
        const ConversationSummary(
          id: 'conversation-2',
          type: ConversationType.group,
          title: 'Project Room',
          lastMessageBody: 'needle in the last message',
          unreadCount: 0,
        ),
        const ConversationSummary(
          id: 'conversation-3',
          type: ConversationType.direct,
          title: 'Needlepoint Club',
          lastMessageBody: 'craft plans',
          unreadCount: 0,
        ),
      ]
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'hello',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository, title: 'Current Chat'));
    await tester.pump();

    await tester.longPress(find.text('hello'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Forward'));
    await tester.pumpAndSettle();
    await tester.enterText(find.bySemanticsLabel('Search chats'), 'needle');
    await tester.pump();

    expect(find.text('Needlepoint Club'), findsOneWidget);
    expect(find.text('Project Room'), findsNothing);
    expect(find.text('Ada Lovelace'), findsNothing);
  });

  testWidgets('reply state clears when replied-to message becomes recalled', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Original',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.longPress(find.text('Original'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reply'));
    await tester.pumpAndSettle();

    expect(find.text('Replying to Original'), findsOneWidget);

    repository.messages = [
      _message(
        id: 'message-1',
        senderId: 'user-2',
        body: 'Original',
        createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        recalledAt: DateTime.utc(2026, 5, 18, 4, 31),
      ),
    ];
    repository.emitMessageChange();
    await tester.pumpAndSettle();

    expect(find.text('Replying to Original'), findsNothing);
    expect(find.text('Original'), findsNothing);
    expect(find.text('Message deleted'), findsOneWidget);
  });

  testWidgets('edits an outgoing text message from the action menu', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Before',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('Before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Before',
    );

    await tester.enterText(find.byType(TextField), 'After');
    await tester.tap(find.byTooltip('Save edit'));
    await tester.pump();

    expect(repository.editedMessageId, 'message-1');
    expect(repository.editedBody, 'After');
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
  });

  testWidgets('keeps an in-progress edit draft across equivalent refreshes', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Before',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.longPress(find.text('Before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Draft in progress');

    repository.messages = [
      _message(
        id: 'message-1',
        senderId: 'user-1',
        body: 'Before',
        createdAt: DateTime.utc(2026, 5, 18, 4, 30),
      ),
    ];
    repository.emitMessageChange();
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Draft in progress',
    );
  });

  testWidgets('edit state clears when edited message becomes recalled', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Before',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.longPress(find.text('Before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Save edit'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Before',
    );

    repository.messages = [
      _message(
        id: 'message-1',
        senderId: 'user-1',
        body: 'Before',
        createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        recalledAt: DateTime.utc(2026, 5, 18, 4, 31),
      ),
    ];
    repository.emitMessageChange();
    await tester.pumpAndSettle();

    expect(find.byTooltip('Save edit'), findsNothing);
    expect(find.text('Before'), findsNothing);
    expect(find.text('Message deleted'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '',
    );
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
    expect(find.text('Reply'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('renders reply previews above message content', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Reply body',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
          replyPreview: const ReplyPreview(
            messageId: 'message-0',
            senderName: 'Ada',
            body: 'Original preview',
            type: MessageType.text,
          ),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Original preview'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Original preview')).dy,
      lessThan(tester.getTopLeft(find.text('Reply body')).dy),
    );
  });

  testWidgets('renders forwarded previews above message content', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Forwarded body',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
          forwardPreview: const ForwardPreview(
            messageId: 'message-0',
            senderName: 'Grace Hopper',
            type: MessageType.text,
            body: 'Original body',
          ),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Forwarded from Grace Hopper'), findsOneWidget);
    expect(find.text('Original body'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Original body')).dy,
      lessThan(tester.getTopLeft(find.text('Forwarded body')).dy),
    );
  });

  testWidgets('reply preview redacts recalled message bodies in thread', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Original secret',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          recalledAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'Reply body',
          createdAt: DateTime.utc(2026, 5, 18, 4, 32),
          replyPreview: const ReplyPreview(
            messageId: 'message-1',
            senderName: 'Ada',
            body: 'Original secret',
            type: MessageType.text,
          ),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Reply body'), findsOneWidget);
    expect(find.text('Original secret'), findsNothing);
    expect(find.text('Message deleted'), findsWidgets);
  });

  testWidgets('reply preview preserves stored body after parent edits', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Edited body',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          editedAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'Reply body',
          createdAt: DateTime.utc(2026, 5, 18, 4, 32),
          replyPreview: const ReplyPreview(
            messageId: 'message-1',
            senderName: 'Ada',
            body: 'Original body',
            type: MessageType.text,
          ),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Original body'), findsOneWidget);
    expect(find.text('Edited body'), findsOneWidget);
  });

  testWidgets('edited messages render an edited marker', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Updated',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          editedAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Updated'), findsOneWidget);
    expect(find.text('edited'), findsOneWidget);
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

  testWidgets('failed edit keeps the composer text', (tester) async {
    final repository = FakeChatsRepository()
      ..editError = Exception('offline')
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-1',
          body: 'Before',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.longPress(find.text('Before'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'After');
    await tester.tap(find.byTooltip('Save edit'));
    await tester.pump();

    expect(find.text('Could not save edit. Try again.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'After',
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
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
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

  testWidgets('media opens above the thread and pops back to it', (
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
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
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

    await tester.tap(find.byTooltip('Media'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatMediaScreen), findsOneWidget);

    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ChatMediaScreen), findsNothing);
    expect(find.byType(ChatThreadScreen), findsOneWidget);
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
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
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
          settingsRepositoryProvider.overrideWithValue(
            FakeSettingsRepository(),
          ),
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
        avatarUrl: 'profile-avatars/user-2/ada.png',
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));

    final screen = tester.widget<ChatThreadScreen>(
      find.byType(ChatThreadScreen),
    );
    expect(screen.avatarUrl, 'profile-avatars/user-2/ada.png');
    final avatar = tester.widget<CircleAvatar>(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(CircleAvatar),
      ),
    );
    final image = avatar.backgroundImage;
    expect(image, isA<NetworkImage>());
    expect(
      (image! as NetworkImage).url,
      'https://signed.example.com/profile-avatars/user-2/ada.png',
    );
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

  testWidgets('loads group metadata when route extras are absent', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.group,
          title: 'Launch Crew',
          unreadCount: 0,
        ),
      ];

    await tester.pumpWidget(_app(repository, title: null));
    await tester.pump();
    await tester.pump();

    expect(find.text('Launch Crew'), findsOneWidget);
    expect(find.byTooltip('Group details'), findsOneWidget);
  });

  testWidgets('shows group announcement above messages', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.group,
          title: 'Launch Crew',
          unreadCount: 0,
          announcement: 'Deploy at noon',
        ),
      ]
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Ready',
          createdAt: DateTime.utc(2026, 5, 19, 9, 45),
        ),
      ];

    await tester.pumpWidget(
      _app(repository, conversationType: ConversationType.group),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Deploy at noon'), findsOneWidget);
  });

  testWidgets('marks the active conversation while mounted', (tester) async {
    final repository = FakeChatsRepository();
    final container = ProviderContainer(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(repository),
        settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: ChatThreadScreen(
            conversationId: 'conversation-1',
            title: 'Ada Lovelace',
          ),
        ),
      ),
    );
    await tester.pump();

    expect(container.read(activeConversationIdProvider), 'conversation-1');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(container.read(activeConversationIdProvider), isNull);
  });
}

Widget _app(
  FakeChatsRepository repository, {
  ImagePickerService? imagePickerService,
  VoiceMessageRecorder? voiceMessageRecorder,
  String? title = 'Ada Lovelace',
  ConversationType? conversationType,
}) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(repository),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      if (imagePickerService != null)
        imagePickerServiceProvider.overrideWithValue(imagePickerService),
      if (voiceMessageRecorder != null)
        voiceMessageRecorderProvider.overrideWithValue(voiceMessageRecorder),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository()
          ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
      ),
    ],
    child: MaterialApp(
      home: ChatThreadScreen(
        conversationId: 'conversation-1',
        title: title,
        conversationType: conversationType,
      ),
    ),
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

ChatMessage _message({
  required String id,
  required String senderId,
  required String body,
  required DateTime createdAt,
  MessageType type = MessageType.text,
  Map<String, dynamic>? attachment,
  ReplyPreview? replyPreview,
  ForwardPreview? forwardPreview,
  DateTime? editedAt,
  DateTime? recalledAt,
  List<MessageReaction> reactions = const [],
  bool isPinned = false,
  Profile? sender,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: type,
    body: body,
    attachment: attachment,
    replyPreview: replyPreview,
    forwardPreview: forwardPreview,
    createdAt: createdAt,
    editedAt: editedAt,
    recalledAt: recalledAt,
    reactions: reactions,
    isPinned: isPinned,
    sender: sender,
  );
}

class FakeChatsRepository implements ChatsRepository {
  var conversations = <ConversationSummary>[];
  var messages = <ChatMessage>[];
  var readMarkers = <ConversationReadMarker>[];
  var activity = const ConversationActivity();
  GroupDetail? groupDetail;
  Object? sendError;
  Object? editError;
  final sentMessages = <SentMessage>[];
  final sentImages = <SentImage>[];
  final sentVoiceMessages = <SentVoiceMessage>[];
  final forwardedMessages = <ForwardedMessage>[];
  final createdImageUrls = <ImageAttachment>[];
  final recalledMessageIds = <String>[];
  final toggledReactions = <(String, String)>[];
  final reactorRequests = <(String, String)>[];
  var reactors = <Profile>[];
  var canPin = false;
  var pinnedMessages = <PinnedMessage>[];
  Object? pinError;
  final pinnedMessageIds = <String>[];
  final unpinnedMessageIds = <String>[];
  final typingUpdates = <TypingUpdate>[];
  final markReadCalls = <String>[];
  String? sentReplyToMessageId;
  ReplyPreview? sentReplyPreview;
  String? editedMessageId;
  String? editedBody;
  final _conversationChanges = StreamController<void>.broadcast();
  final _messageChanges = StreamController<void>.broadcast();
  final _activityChanges = StreamController<ConversationActivity>.broadcast();

  @override
  Future<List<ConversationSummary>> listConversations() async => conversations;

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
    List<MessageMention> mentions = const <MessageMention>[],
  }) async {
    if (sendError case final error?) {
      throw error;
    }
    sentReplyToMessageId = replyToMessageId;
    sentReplyPreview = replyPreview;
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
  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) async {
    if (sendError case final error?) {
      throw error;
    }
    sentVoiceMessages.add(
      SentVoiceMessage(
        conversationId: conversationId,
        bytes: bytes,
        mimeType: mimeType,
        durationMs: durationMs,
      ),
    );
  }

  @override
  Future<void> forwardMessage({
    required String sourceMessageId,
    required String targetConversationId,
  }) async {
    forwardedMessages.add(
      ForwardedMessage(
        sourceMessageId: sourceMessageId,
        targetConversationId: targetConversationId,
      ),
    );
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) async {
    createdImageUrls.add(attachment);
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
  }) async {
    if (editError case final error?) {
      throw error;
    }
    editedMessageId = messageId;
    editedBody = body;
  }

  @override
  Future<void> toggleMessageReaction({
    required String messageId,
    required String emoji,
  }) async {
    toggledReactions.add((messageId, emoji));
  }

  @override
  Future<List<Profile>> listMessageReactors({
    required String messageId,
    required String emoji,
  }) async {
    reactorRequests.add((messageId, emoji));
    return reactors;
  }

  @override
  Future<bool> canPinMessages(String conversationId) async => canPin;

  @override
  Future<void> pinMessage({required String messageId}) async {
    if (pinError case final error?) {
      throw error;
    }
    pinnedMessageIds.add(messageId);
  }

  @override
  Future<void> unpinMessage({required String messageId}) async {
    unpinnedMessageIds.add(messageId);
  }

  @override
  Future<List<PinnedMessage>> listPinnedMessages(String conversationId) async {
    return pinnedMessages;
  }

  @override
  Future<void> markConversationRead(String conversationId) async {
    markReadCalls.add(conversationId);
  }

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

class SentVoiceMessage {
  const SentVoiceMessage({
    required this.conversationId,
    required this.bytes,
    required this.mimeType,
    required this.durationMs,
  });

  final String conversationId;
  final Uint8List bytes;
  final String mimeType;
  final int durationMs;

  @override
  bool operator ==(Object other) {
    return other is SentVoiceMessage &&
        other.conversationId == conversationId &&
        _listEquals(other.bytes, bytes) &&
        other.mimeType == mimeType &&
        other.durationMs == durationMs;
  }

  @override
  int get hashCode =>
      Object.hash(conversationId, Object.hashAll(bytes), mimeType, durationMs);
}

class ForwardedMessage {
  const ForwardedMessage({
    required this.sourceMessageId,
    required this.targetConversationId,
  });

  final String sourceMessageId;
  final String targetConversationId;

  @override
  bool operator ==(Object other) {
    return other is ForwardedMessage &&
        other.sourceMessageId == sourceMessageId &&
        other.targetConversationId == targetConversationId;
  }

  @override
  int get hashCode => Object.hash(sourceMessageId, targetConversationId);
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

class FakeVoiceMessageRecorder implements VoiceMessageRecorder {
  RecordedVoiceMessage? nextRecording;
  var startCalls = 0;
  var stopCalls = 0;
  var cancelCalls = 0;

  @override
  Future<void> start() async {
    startCalls += 1;
  }

  @override
  Future<RecordedVoiceMessage?> stop() async {
    stopCalls += 1;
    return nextRecording;
  }

  @override
  Future<void> cancel() async {
    cancelCalls += 1;
  }
}

bool _listEquals(Uint8List left, Uint8List right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
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

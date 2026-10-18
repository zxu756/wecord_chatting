import 'dart:async';
import 'package:wecord/features/file_preview/file_preview_screen.dart';
import '../file_preview/file_preview_fakes.dart';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chat_thread_parts.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/circles/circle_moderation.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/chats_screen.dart';
import 'package:wecord/features/chats/image_picker_service.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/chats/media_send/blurhash.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';
import 'package:wecord/features/chats/message_history.dart';
import 'package:wecord/features/chats/message_markdown_text.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/search/message_jump.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/custom_status.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/link_preview.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/pinned_message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/navigation/app_router.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'emoji_fixtures.dart';
import 'media_send/media_fakes.dart';

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
    expect(_avatarsOf('Ada Lovelace'), findsOneWidget);
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

  testWidgets('renders markdown bodies while search matches raw text', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: '**Big** news, see `code`',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'plain reply',
          createdAt: DateTime.utc(2026, 5, 18, 4, 31),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Big news, see code'), findsOneWidget);
    expect(find.textContaining('**'), findsNothing);

    await tester.tap(find.byTooltip('Search messages'));
    await tester.pump();
    await tester.enterText(find.bySemanticsLabel('Search messages'), '**big');
    await tester.pump();

    expect(find.text('1 result'), findsOneWidget);
    expect(find.text('Big news, see code'), findsOneWidget);
    expect(find.text('plain reply'), findsNothing);
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
      expect(_avatarsOf('Grace Hopper'), findsNWidgets(2));
      expect(_avatarsOf('Alan Turing'), findsOneWidget);

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

    testWidgets('channel threads prefer circle nicknames and role colors', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..groupDetail = GroupDetail(
          conversationId: 'conversation-1',
          title: 'general',
          members: [
            GroupMember(profile: alan, role: 'member', nickname: 'Prof'),
          ],
        )
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            sender: grace,
            body: 'From the message nickname',
            createdAt: DateTime.utc(2026, 5, 18, 10, 0),
          ).copyWith(senderNickname: 'Admiral', senderRoleColor: 0xE91E63),
          _message(
            id: 'message-2',
            senderId: 'user-3',
            body: 'From the member list',
            createdAt: DateTime.utc(2026, 5, 18, 10, 1),
          ),
        ];

      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.channel),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Admiral'), findsOneWidget);
      expect(find.text('Grace Hopper'), findsNothing);
      expect(find.text('Prof'), findsOneWidget);
      expect(find.text('Alan Turing'), findsNothing);
      // Names take the sender's highest coloured circle role.
      expect(
        tester.widget<Text>(find.text('Admiral')).style?.color,
        const Color(0xFFE91E63),
      );
      expect(
        tester.widget<Text>(find.text('Prof')).style?.color,
        isNot(const Color(0xFFE91E63)),
      );
    });

    testWidgets('channel mention candidates show and match nicknames', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..groupDetail = GroupDetail(
          conversationId: 'conversation-1',
          title: 'general',
          members: [
            GroupMember(profile: grace, role: 'member', nickname: 'Admiral'),
            GroupMember(profile: alan, role: 'member'),
          ],
        );

      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.channel),
      );
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'hi @admi');
      await tester.pump();

      expect(find.text('Admiral'), findsOneWidget);
      expect(find.text('@grace'), findsOneWidget);
      expect(find.text('Alan Turing'), findsNothing);

      await tester.tap(find.text('Admiral'));
      await tester.pump();

      final composer = tester.widget<TextField>(find.byType(TextField));
      expect(composer.controller!.text, 'hi @grace ');
    });

    testWidgets('direct chats show avatars but no sender names', (
      tester,
    ) async {
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
      // One avatar per run of bubbles, beside its last message.
      expect(_avatarsOf('Grace Hopper'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('message-avatar-message-1')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('message-avatar-message-2')),
        findsOneWidget,
      );
    });

    testWidgets('own messages sit on the right without an avatar', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-1',
            sender: _profile(id: 'user-1', username: 'ada'),
            body: 'Mine',
            createdAt: DateTime.utc(2026, 5, 18, 10, 0),
          ),
        ];

      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.direct),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('message-avatar-message-1')),
        findsNothing,
      );
      expect(
        tester.getTopRight(find.text('Mine')).dx,
        greaterThan(tester.getSize(find.byType(Scaffold)).width - 60),
      );
    });

    testWidgets('follow-up messages keep reactions, receipts and actions', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..canPin = true
        ..conversations = [
          const ConversationSummary(
            id: 'conversation-1',
            type: ConversationType.group,
            unreadCount: 0,
            title: 'Pair',
          ),
        ]
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
      // A group counts readers instead of saying "Read".
      expect(find.text('1 read'), findsOneWidget);
      expect(find.text('Read'), findsNothing);

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

  testWidgets('direct chats show the peer online anywhere in the app', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..readMarkers = const [
        ConversationReadMarker(userId: 'user-1', lastReadMessageId: null),
        ConversationReadMarker(userId: 'user-2', lastReadMessageId: null),
      ];
    final online = StreamController<Set<String>>.broadcast();
    addTearDown(online.close);

    await tester.pumpWidget(
      _app(
        repository,
        conversationType: ConversationType.direct,
        onlineUserIds: online.stream,
      ),
    );
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);

    online.add({'user-1', 'user-2'});
    await tester.pump();
    expect(find.text('Online'), findsOneWidget);

    // Viewing this conversation is not what makes a direct peer online.
    repository.emitActivity(
      const ConversationActivity(onlineUserIds: {'user-2'}),
    );
    online.add({'user-1'});
    await tester.pump();
    await tester.pump();
    expect(find.text('Offline'), findsOneWidget);
  });

  testWidgets('direct chat headers show the peer custom status', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.direct,
          unreadCount: 0,
          title: 'Ada Lovelace',
          directUserId: 'user-2',
          directCustomStatus: const CustomStatus(
            emoji: '🎧',
            text: 'Listening',
          ),
        ),
      ];

    await tester.pumpWidget(
      _app(
        repository,
        conversationType: ConversationType.direct,
        onlineUserIds: Stream.value({'user-1', 'user-2'}),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Online · 🎧 Listening'), findsOneWidget);
  });

  group('threads', () {
    testWidgets('long-pressing a channel message creates a thread', (
      tester,
    ) async {
      const body =
          'Who is up for a long walk on Saturday morning around the lake?';
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body: body,
            createdAt: DateTime.utc(2026, 10, 13, 8),
          ),
        ];
      final opened = <ThreadTarget>[];

      await tester.pumpWidget(
        _app(
          repository,
          title: '# general',
          conversationType: ConversationType.channel,
          onOpenThread: opened.add,
        ),
      );
      await tester.pump();

      await tester.longPress(find.text(body));
      await tester.pumpAndSettle();
      expect(find.text('Open thread'), findsNothing);
      await tester.tap(find.text('Create thread'));
      await tester.pumpAndSettle();

      final titleField = find.widgetWithText(TextField, 'Thread title');
      expect(
        tester.widget<TextField>(titleField).controller!.text,
        suggestedThreadTitle(body),
      );
      expect(suggestedThreadTitle(body), endsWith('…'));
      await tester.enterText(titleField, 'Saturday walk');
      await tester.tap(find.widgetWithText(FilledButton, 'Create'));
      await tester.pumpAndSettle();

      expect(repository.createdThreads, [
        (
          parentConversationId: 'conversation-1',
          rootMessageId: 'message-1',
          title: 'Saturday walk',
        ),
      ]);
      expect(opened.single.conversationId, 'thread-conversation-1');
      expect(opened.single.title, 'Saturday walk');
    });

    testWidgets('root messages show a reply chip that opens the thread', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body: 'Root message',
            createdAt: DateTime.utc(2026, 10, 13, 8),
          ).copyWith(
            threadSummary: MessageThreadSummary(
              threadId: 'thread-1',
              conversationId: 'thread-conversation-1',
              title: 'Plans',
              replyCount: 2,
              lastReplyAt: DateTime.now().toUtc().subtract(
                const Duration(minutes: 5),
              ),
              unreadCount: 1,
            ),
          ),
        ];
      final opened = <ThreadTarget>[];

      await tester.pumpWidget(
        _app(
          repository,
          conversationType: ConversationType.group,
          onOpenThread: opened.add,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('thread-chip-message-1')),
        findsOneWidget,
      );
      expect(find.text('Plans'), findsOneWidget);
      expect(find.text('2 replies · 5m ago'), findsOneWidget);
      expect(find.byKey(const ValueKey('thread-chip-unread')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('thread-chip-message-1')));
      await tester.pump();
      expect(opened.single.conversationId, 'thread-conversation-1');
      expect(opened.single.threadId, 'thread-1');

      await tester.longPress(find.text('Root message'));
      await tester.pumpAndSettle();
      expect(find.text('Create thread'), findsNothing);
      await tester.tap(find.text('Open thread'));
      await tester.pumpAndSettle();
      expect(opened, hasLength(2));
      expect(repository.createdThreads, isEmpty);
    });

    testWidgets('direct chats and threads cannot start threads', (
      tester,
    ) async {
      for (final type in [ConversationType.direct, ConversationType.thread]) {
        final repository = FakeChatsRepository()
          ..messages = [
            _message(
              id: 'message-1',
              senderId: 'user-2',
              body: 'Hello there',
              createdAt: DateTime.utc(2026, 10, 13, 8),
            ),
          ];
        await tester.pumpWidget(
          _app(repository, conversationType: type, onOpenThread: (_) {}),
        );
        await tester.pump();

        await tester.longPress(find.text('Hello there'));
        await tester.pumpAndSettle();
        expect(find.text('Create thread'), findsNothing, reason: '$type');
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }
    });

    testWidgets('thread headers name the channel and archive the thread', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..canManageThreads = true
        ..conversations = [
          const ConversationSummary(
            id: 'conversation-1',
            type: ConversationType.thread,
            unreadCount: 0,
            title: 'Plans',
            parentConversationId: 'channel-conversation-1',
            parentTitle: 'general',
            circleId: 'circle-1',
            threadId: 'thread-1',
          ),
        ];

      await tester.pumpWidget(
        _app(
          repository,
          title: null,
          conversationType: ConversationType.thread,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Plans'), findsOneWidget);
      expect(find.text('in #general'), findsOneWidget);
      expect(find.text('Online'), findsNothing);

      await tester.tap(find.byTooltip('Archive thread'));
      await tester.pump();
      await tester.pump();

      expect(repository.archiveCalls, [('thread-1', true)]);
      expect(find.text('in #general · Archived'), findsOneWidget);
      expect(find.byTooltip('Unarchive thread'), findsOneWidget);
    });
  });

  testWidgets('sends typing activity while composing and clears it on send', (
    tester,
  ) async {
    final repository = FakeChatsRepository();

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'Hello');
    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
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

    await tester.pumpWidget(
      _app(repository, conversationType: ConversationType.direct),
    );
    await tester.pump();

    expect(find.text('Read'), findsOneWidget);
  });

  group('who has read the newest message', () {
    List<ChatMessage> sample() => [
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
    ];

    FakeChatsRepository repositoryOf(
      ConversationType type,
      List<ConversationReadMarker> markers,
    ) => FakeChatsRepository()
      ..conversations = [
        ConversationSummary(
          id: 'conversation-1',
          type: type,
          unreadCount: 0,
          title: 'Chat',
        ),
      ]
      ..messages = sample()
      ..readMarkers = markers;

    testWidgets('a group counts the readers and never says "Read"', (
      tester,
    ) async {
      final repository = repositoryOf(ConversationType.group, const [
        ConversationReadMarker(
          userId: 'user-2',
          lastReadMessageId: 'message-2',
        ),
        ConversationReadMarker(
          userId: 'user-3',
          lastReadMessageId: 'message-2',
        ),
        ConversationReadMarker(userId: 'user-4', lastReadMessageId: null),
      ]);
      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.group),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('2 read'), findsOneWidget);
      expect(find.text('Read'), findsNothing);
    });

    testWidgets('a group where nobody read it shows nothing', (tester) async {
      final repository = repositoryOf(ConversationType.group, const [
        ConversationReadMarker(userId: 'user-2', lastReadMessageId: null),
      ]);
      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.group),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('read'), findsNothing);
      expect(find.text('Read'), findsNothing);
    });

    testWidgets('a channel shows neither "Read" nor a count', (tester) async {
      final repository = repositoryOf(ConversationType.channel, const [
        ConversationReadMarker(
          userId: 'user-2',
          lastReadMessageId: 'message-2',
        ),
      ]);
      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.channel),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Read'), findsNothing);
      expect(find.textContaining(' read'), findsNothing);
    });

    testWidgets('"Message info" is in the menu of my message in a group', (
      tester,
    ) async {
      final repository = repositoryOf(ConversationType.group, const [
        ConversationReadMarker(
          userId: 'user-2',
          lastReadMessageId: 'message-2',
        ),
      ]);
      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.group),
      );
      await tester.pump();
      await tester.pump();

      await tester.longPress(find.text('Outgoing'));
      await tester.pumpAndSettle();
      expect(find.text('Message info'), findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Incoming'));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Message info'), findsNothing);
    });

    testWidgets('a direct chat has no "Message info"', (tester) async {
      final repository = repositoryOf(ConversationType.direct, const [
        ConversationReadMarker(
          userId: 'user-2',
          lastReadMessageId: 'message-2',
        ),
      ]);
      await tester.pumpWidget(
        _app(repository, conversationType: ConversationType.direct),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Read'), findsOneWidget);
      await tester.longPress(find.text('Outgoing'));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Message info'), findsNothing);
    });
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

    expect(find.byType(FilePreviewScreen), findsOneWidget);
    // Test images never load, so the URL is signed once more (as when a
    // signed URL has expired) and then left alone.
    expect(repository.createdImageUrls, hasLength(2));
    for (final attachment in repository.createdImageUrls) {
      expect(attachment.bucket, 'chat-images');
      expect(attachment.path, 'conversation-1/photo.png');
      expect(attachment.mimeType, 'image/png');
    }
  });

  group('attachments', () {
    testWidgets('the attach menu offers photos and videos, and files', (
      tester,
    ) async {
      final picker = FakeChatMediaPicker();
      await tester.pumpWidget(_app(FakeChatsRepository(), mediaPicker: picker));
      await tester.pump();

      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();

      expect(find.text('Photos and videos'), findsOneWidget);
      expect(find.text('Files'), findsOneWidget);
      await tester.tap(find.text('Photos and videos'));
      await tester.pump();
      expect(picker.photoCalls, 1);
      expect(picker.lastLimit, 10);
      // Nothing was chosen: no tray.
      expect(find.byKey(const ValueKey('media-tray')), findsNothing);
    });

    testWidgets('picked photos wait in a tray, then go out as one album', (
      tester,
    ) async {
      final repository = OutboxChatsRepository();
      final uploader = FakeChatMediaUploader();
      final picker = FakeChatMediaPicker()
        ..photos = [testPhoto('a.jpg'), testPhoto('b.jpg'), testPhoto('c.jpg')];
      await tester.pumpWidget(
        _app(repository, mediaPicker: picker, uploader: uploader),
      );
      await tester.pump();

      await _openAttach(tester, 'Photos and videos');
      await _settleMedia(tester);

      expect(find.byKey(const ValueKey('media-tray')), findsOneWidget);
      expect(find.text('3 photos'), findsOneWidget);
      expect(find.text('Original quality'), findsOneWidget);
      expect(find.textContaining('Resized to 2560 px'), findsOneWidget);

      // Take one out again.
      final remove = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'media-tray-remove-',
            ),
      );
      expect(remove, findsNWidgets(3));
      await tester.tap(remove.first);
      await tester.pump();
      expect(find.text('2 photos'), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('media-tray-caption')),
        'Trip',
      );
      await tester.pump();
      expect(find.text('Send 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media-tray-send')));
      await _settleMedia(tester);

      expect(find.byKey(const ValueKey('media-tray')), findsNothing);
      expect(uploader.uploads, hasLength(2));
      expect(uploader.uploads.every((u) => u.bucket == 'chat-images'), isTrue);
      final calls = repository.mediaSender.calls;
      expect(calls, hasLength(2));
      expect(calls.map((call) => call['body']), ['Trip', '']);
      expect(calls.map((call) => call['group']).toSet(), hasLength(1));
      expect(calls.first['group'], isNotNull);
      expect(calls.map((call) => call['notify']), [false, true]);
      final attachment = calls.first['attachment']! as Map<String, dynamic>;
      expect(attachment['width'], 40);
      expect(attachment['height'], 30);
      expect(BlurHash.isValid(attachment['blurhash'] as String?), isTrue);
    });

    testWidgets('files that are too big are marked and block sending', (
      tester,
    ) async {
      final picker = FakeChatMediaPicker()
        ..files = [
          XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: 'Movie.mov',
            path: 'Movie.mov',
            mimeType: 'video/quicktime',
            length: 60 * 1024 * 1024,
          ),
          XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: 'notes.txt',
            path: 'notes.txt',
            mimeType: 'text/plain',
            length: 3,
          ),
        ];
      await tester.pumpWidget(
        _app(
          OutboxChatsRepository(),
          mediaPicker: picker,
          uploader: FakeChatMediaUploader(),
        ),
      );
      await tester.pump();

      await _openAttach(tester, 'Files');
      await _settleMedia(tester);

      expect(find.text('2 items'), findsOneWidget);
      expect(find.text('Too big'), findsOneWidget);
      expect(find.byKey(const ValueKey('media-tray-too-big')), findsOneWidget);
      // Files only: nothing to scale.
      expect(find.text('Original quality'), findsNothing);
      expect(
        tester
            .widget<WeCordButton>(find.byKey(const ValueKey('media-tray-send')))
            .onPressed,
        isNull,
      );

      // Without the big one it can go.
      final big = find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith(
              'media-tray-remove-',
            ),
      );
      await tester.tap(big.first);
      await tester.pump();
      expect(find.byKey(const ValueKey('media-tray-too-big')), findsNothing);
      expect(
        tester
            .widget<WeCordButton>(find.byKey(const ValueKey('media-tray-send')))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('the Original quality switch says what will be sent', (
      tester,
    ) async {
      final picker = FakeChatMediaPicker()..photos = [testPhoto('a.jpg')];
      await tester.pumpWidget(
        _app(
          OutboxChatsRepository(),
          mediaPicker: picker,
          uploader: FakeChatMediaUploader(),
        ),
      );
      await tester.pump();
      await _openAttach(tester, 'Photos and videos');
      await _settleMedia(tester);

      expect(find.text('1 photo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media-tray-original')));
      await tester.pump();
      expect(find.text('Full size · location removed'), findsOneWidget);
    });

    testWidgets('closing the tray drops everything in it', (tester) async {
      final picker = FakeChatMediaPicker()..photos = [testPhoto('a.jpg')];
      final uploader = FakeChatMediaUploader();
      await tester.pumpWidget(
        _app(OutboxChatsRepository(), mediaPicker: picker, uploader: uploader),
      );
      await tester.pump();
      await _openAttach(tester, 'Photos and videos');
      await _settleMedia(tester);

      await tester.tap(find.byKey(const ValueKey('media-tray-close')));
      await tester.pump();

      expect(find.byKey(const ValueKey('media-tray')), findsNothing);
      expect(uploader.uploads, isEmpty);
    });

    testWidgets('a failed picker shows why', (tester) async {
      final picker = FakeChatMediaPicker()..error = Exception('no access');
      await tester.pumpWidget(_app(FakeChatsRepository(), mediaPicker: picker));
      await tester.pump();

      await _openAttach(tester, 'Photos and videos');
      await tester.pump();

      expect(find.textContaining('no access'), findsOneWidget);
    });

    testWidgets('an album being sent shows rings and can be cancelled', (
      tester,
    ) async {
      final repository = OutboxChatsRepository();
      final uploader = FakeChatMediaUploader()..hold = Completer<void>();
      final picker = FakeChatMediaPicker()
        ..photos = [testPhoto('a.jpg'), testPhoto('b.jpg')];
      await tester.pumpWidget(
        _app(repository, mediaPicker: picker, uploader: uploader),
      );
      await tester.pump();
      await _openAttach(tester, 'Photos and videos');
      await _settleMedia(tester);
      await tester.tap(find.byKey(const ValueKey('media-tray-send')));
      await _settleMedia(tester);

      // Two tiles in one bubble, both still going up.
      expect(find.byType(MediaTile), findsNWidgets(2));
      expect(find.byTooltip('Cancel upload'), findsNWidgets(2));
      expect(find.text('Sending…'), findsOneWidget);
      expect(uploader.uploads, hasLength(1), reason: 'one file at a time');

      await tester.tap(find.byTooltip('Cancel upload').first);
      await _settleMedia(tester);

      // The cancelled one left; the other went on and is still uploading.
      expect(find.byType(MediaTile), findsOneWidget);
      expect(uploader.uploads, hasLength(2));
      uploader.hold!.complete();
      await _settleMedia(tester);
      expect(repository.mediaSender.calls, hasLength(1));
      expect(find.byType(MediaTile), findsNothing);
    });

    testWidgets('slowmode on an album says how long and sends again on Retry', (
      tester,
    ) async {
      final repository = OutboxChatsRepository();
      repository.mediaSender.failures.add(const SlowmodeException(8));
      final uploader = FakeChatMediaUploader();
      final picker = FakeChatMediaPicker()..photos = [testPhoto('a.jpg')];
      await tester.pumpWidget(
        _app(repository, mediaPicker: picker, uploader: uploader),
      );
      await tester.pump();
      await _openAttach(tester, 'Photos and videos');
      await _settleMedia(tester);
      await tester.tap(find.byKey(const ValueKey('media-tray-send')));
      await _settleMedia(tester);

      // The reason, in the words text sends use, not a bare "failed".
      expect(
        find.text('Slowmode is enabled. Try again in 8 seconds.'),
        findsOneWidget,
      );
      expect(find.text('Failed — tap to retry'), findsNothing);
      expect(find.text('Edit and resend'), findsNothing);
      expect(find.text('Discard'), findsOneWidget);
      expect(find.byTooltip('Retry upload'), findsOneWidget);
      expect(repository.mediaSender.calls, isEmpty);

      // The wait counts down, and Retry shows when it is over.
      expect(find.text('Retry'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      expect(
        find.text('Slowmode is enabled. Try again in 5 seconds.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 6));
      expect(
        find.text('Slowmode is over. You can send it now.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);

      await tester.tap(find.text('Retry'));
      await _settleMedia(tester);

      // The file was already up; only the message is sent again.
      expect(uploader.uploads, hasLength(1));
      expect(repository.mediaSender.calls, hasLength(1));
      expect(find.text('Retry'), findsNothing);
    });

    testWidgets('a file over the limit says so and offers to edit it', (
      tester,
    ) async {
      final repository = OutboxChatsRepository();
      final uploader = FakeChatMediaUploader()
        ..failures.add(const UploadException(413, 'Payload too large'));
      final picker = FakeChatMediaPicker()..photos = [testPhoto('a.jpg')];
      await tester.pumpWidget(
        _app(repository, mediaPicker: picker, uploader: uploader),
      );
      await tester.pump();
      await _openAttach(tester, 'Photos and videos');
      await _settleMedia(tester);
      await tester.tap(find.byKey(const ValueKey('media-tray-send')));
      await _settleMedia(tester);

      expect(find.text('Files can be up to 50 MB.'), findsOneWidget);
      expect(find.text('Edit and resend'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.byTooltip('Retry upload'), findsNothing);
      expect(find.byTooltip('Edit and resend'), findsOneWidget);
    });

    testWidgets(
      'an album refused by AutoMod says why; Edit and resend puts it back in the tray',
      (tester) async {
        final repository = OutboxChatsRepository();
        repository.mediaSender.failures.add(
          const AutoModBlockedException('No links here'),
        );
        final uploader = FakeChatMediaUploader();
        final picker = FakeChatMediaPicker()
          ..photos = [testPhoto('a.jpg'), testPhoto('b.jpg')];
        await tester.pumpWidget(
          _app(repository, mediaPicker: picker, uploader: uploader),
        );
        await tester.pump();
        await _openAttach(tester, 'Photos and videos');
        await _settleMedia(tester);
        await tester.enterText(
          find.byKey(const ValueKey('media-tray-caption')),
          'Trip',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('media-tray-send')));
        await _settleMedia(tester);

        // The first item was refused, the second went through.
        expect(
          find.text('AutoMod blocked your message: No links here'),
          findsOneWidget,
        );
        expect(repository.mediaSender.calls, hasLength(1));
        expect(find.text('Edit and resend'), findsOneWidget);
        expect(find.text('Discard'), findsOneWidget);
        expect(find.text('Retry'), findsNothing);
        expect(find.byKey(const ValueKey('media-tray')), findsNothing);

        await tester.tap(find.text('Edit and resend'));
        await _settleMedia(tester);

        // The refused photo is back in the tray with its caption, and is
        // gone from the chat.
        expect(find.byKey(const ValueKey('media-tray')), findsOneWidget);
        expect(find.text('1 photo'), findsOneWidget);
        final caption = tester.widget<TextField>(
          find.byKey(const ValueKey('media-tray-caption')),
        );
        expect(caption.controller!.text, 'Trip');
        expect(find.text('Edit and resend'), findsNothing);
        expect(
          find.text('AutoMod blocked your message: No links here'),
          findsNothing,
        );
      },
    );

    testWidgets('Discard drops a refused album after asking', (tester) async {
      final repository = OutboxChatsRepository();
      repository.mediaSender.failures.add(
        const CircleRulesNotAcceptedException(),
      );
      final picker = FakeChatMediaPicker()..photos = [testPhoto('a.jpg')];
      await tester.pumpWidget(
        _app(
          repository,
          mediaPicker: picker,
          uploader: FakeChatMediaUploader(),
        ),
      );
      await tester.pump();
      await _openAttach(tester, 'Photos and videos');
      await _settleMedia(tester);
      await tester.tap(find.byKey(const ValueKey('media-tray-send')));
      await _settleMedia(tester);

      expect(
        find.text('Accept the circle rules to start chatting.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Discard'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pending-discard-confirm')));
      await _settleMedia(tester);

      expect(find.byType(MediaTile), findsNothing);
      expect(find.text('Discard'), findsNothing);
    });

    for (final reduced in [true, false]) {
      testWidgets(
        'a GIF in an album ${reduced ? 'holds still behind a play button under reduced motion' : 'just plays without it'}',
        (tester) async {
          if (reduced) {
            tester.platformDispatcher.accessibilityFeaturesTestValue =
                const FakeAccessibilityFeatures(disableAnimations: true);
            addTearDown(
              tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
            );
          }
          Map<String, dynamic> gif(String name) => ImageAttachment(
            bucket: 'chat-images',
            path: 'conversation-1/$name.gif',
            mimeType: 'image/gif',
            size: 1000,
            width: 400,
            height: 400,
          ).toJson();
          final repository = FakeChatsRepository()
            ..messages = [
              for (var i = 1; i <= 2; i++)
                _message(
                  id: 'message-$i',
                  senderId: 'user-2',
                  body: '',
                  createdAt: DateTime.utc(2026, 10, 17, 9, 0, i),
                  type: MessageType.image,
                  attachment: gif('g$i'),
                  attachmentGroupId: 'album-1',
                ),
            ];
          await tester.pumpWidget(
            _app(
              repository,
              voiceMessageRecorder: FakeVoiceMessageRecorder(),
              overrides: [
                chatImageProviderFactoryProvider.overrideWithValue(
                  (url) => MemoryImage(partyParrotPng),
                ),
              ],
            ),
          );
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await tester.pump();
          await tester.pump();

          expect(find.byType(MediaTile), findsNWidgets(2));
          expect(
            find.byTooltip('Play animation'),
            reduced ? findsNWidgets(2) : findsNothing,
          );
          if (reduced) {
            // Playing one does not open the viewer.
            await tester.tap(find.byTooltip('Play animation').first);
            await tester.pump();
            expect(find.byTooltip('Play animation'), findsOneWidget);
            expect(find.byType(FilePreviewScreen), findsNothing);
          }
        },
      );
    }

    testWidgets('pictures sent together show as one grid and open the viewer', (
      tester,
    ) async {
      const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
      Map<String, dynamic> photo(String name) => ImageAttachment(
        bucket: 'chat-images',
        path: 'conversation-1/$name.jpg',
        mimeType: 'image/jpeg',
        size: 1000,
        width: 800,
        height: 600,
        blurhash: hash,
      ).toJson();
      final repository = FakeChatsRepository()
        ..messages = [
          for (var i = 1; i <= 4; i++)
            _message(
              id: 'message-$i',
              senderId: 'user-2',
              body: i == 1 ? 'Trip to the lake' : '',
              createdAt: DateTime.utc(2026, 10, 17, 9, 0, i),
              type: MessageType.image,
              attachment: photo('p$i'),
              attachmentGroupId: 'album-1',
            ),
        ];

      await tester.pumpWidget(_app(repository));
      await tester.pump();
      await tester.pump();

      // One bubble, one grid of four, one caption.
      expect(
        find.byKey(const ValueKey('album-grid-message-1')),
        findsOneWidget,
      );
      expect(find.byType(MediaTile), findsNWidgets(4));
      expect(find.text('Trip to the lake'), findsOneWidget);
      // The BlurHash is there from the first frame.
      expect(find.byType(BlurHashView), findsNWidgets(4));

      // Tiles sit side by side in rows of two.
      final first = tester.getRect(
        find.byKey(const ValueKey('album-tile-message-1')),
      );
      final second = tester.getRect(
        find.byKey(const ValueKey('album-tile-message-2')),
      );
      final third = tester.getRect(
        find.byKey(const ValueKey('album-tile-message-3')),
      );
      expect(second.left, greaterThan(first.right - 1));
      expect(second.top, first.top);
      expect(third.top, greaterThan(first.bottom - 1));

      await tester.tap(find.byKey(const ValueKey('album-tile-message-2')));
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewScreen), findsOneWidget);
    });

    testWidgets('a picture keeps its proportions before it has loaded', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body: '',
            createdAt: DateTime.utc(2026, 10, 17, 9),
            type: MessageType.image,
            attachment: const ImageAttachment(
              bucket: 'chat-images',
              path: 'conversation-1/wide.jpg',
              mimeType: 'image/jpeg',
              size: 1000,
              width: 1600,
              height: 800,
            ).toJson(),
          ),
        ];

      await tester.pumpWidget(_app(repository));
      await tester.pump();

      final size = tester.getSize(
        find.byKey(const ValueKey('album-tile-message-1')),
      );
      expect(size.width / size.height, closeTo(2, 0.01));
    });
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

  group('voice recording length', () {
    RecordedVoiceMessage recording() => RecordedVoiceMessage(
      bytes: Uint8List.fromList([4, 5, 6]),
      mimeType: 'audio/wav',
      durationMs: 540000,
    );

    Future<void> startRecording(
      WidgetTester tester,
      FakeChatsRepository repository,
      FakeVoiceMessageRecorder recorder,
    ) async {
      await tester.pumpWidget(_app(repository, voiceMessageRecorder: recorder));
      await tester.pump();
      await tester.tap(find.byTooltip('Record voice message'));
      await tester.pump();
      expect(find.text('Recording...'), findsOneWidget);
    }

    testWidgets('counts down the last 30 seconds, then stops and sends', (
      tester,
    ) async {
      final repository = FakeChatsRepository();
      final recorder = FakeVoiceMessageRecorder()..nextRecording = recording();
      await startRecording(tester, repository, recorder);

      // Nothing to see for most of the nine minutes.
      await tester.pump(const Duration(seconds: 509));
      expect(find.byKey(const ValueKey('voice-seconds-left')), findsNothing);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('30s left'), findsOneWidget);
      await tester.pump(const Duration(seconds: 20));
      expect(find.text('10s left'), findsOneWidget);
      await tester.pump(const Duration(seconds: 9));
      expect(find.text('1s left'), findsOneWidget);
      expect(recorder.stopCalls, 0);

      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(recorder.stopCalls, 1);
      expect(repository.sentVoiceMessages, hasLength(1));
      expect(find.text('Recording...'), findsNothing);
      expect(
        find.text('Reached the 9 minute limit. Your voice message was sent.'),
        findsOneWidget,
      );
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('sending before the limit ends the countdown', (tester) async {
      final repository = FakeChatsRepository();
      final recorder = FakeVoiceMessageRecorder()..nextRecording = recording();
      await startRecording(tester, repository, recorder);

      await tester.pump(const Duration(seconds: 520));
      expect(find.text('20s left'), findsOneWidget);
      await tester.tap(find.byTooltip('Send voice message'));
      await tester.pumpAndSettle();
      expect(recorder.stopCalls, 1);

      await tester.pump(const Duration(seconds: 100));
      expect(recorder.stopCalls, 1);
      expect(repository.sentVoiceMessages, hasLength(1));
      expect(find.textContaining('9 minute limit'), findsNothing);
    });

    testWidgets('cancelling ends the countdown too', (tester) async {
      final repository = FakeChatsRepository();
      final recorder = FakeVoiceMessageRecorder()..nextRecording = recording();
      await startRecording(tester, repository, recorder);

      await tester.pump(const Duration(seconds: 525));
      await tester.tap(find.byTooltip('Cancel voice message'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 100));

      expect(recorder.cancelCalls, 1);
      expect(recorder.stopCalls, 0);
      expect(repository.sentVoiceMessages, isEmpty);
    });

    testWidgets('a recording the server finds too big says so', (tester) async {
      final repository = FakeChatsRepository()
        ..sendError = const VoiceMessageTooLargeException();
      final recorder = FakeVoiceMessageRecorder()..nextRecording = recording();
      await startRecording(tester, repository, recorder);

      await tester.tap(find.byTooltip('Send voice message'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'This voice message is too long to send. '
          'Voice messages can be up to 9 minutes.',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Could not send voice message. Try again.'),
        findsNothing,
      );
    });

    test('nine minutes of WAV fit the 50 MB bucket', () {
      const bytesPerSecond = 44100 * 2;
      expect(
        maxVoiceRecordingSeconds * bytesPerSecond + 44,
        lessThan(maxChatFileBytes),
      );
      expect(voiceCountdownSeconds, lessThan(maxVoiceRecordingSeconds));
    });
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

  group('link previews', () {
    const examplePreview = LinkPreview(
      url: 'https://example.com/',
      title: 'Example Domain',
      description: 'For use in examples',
      siteName: 'Example',
    );

    testWidgets('shows a card for the first link and opens it on tap', (
      tester,
    ) async {
      final opened = <Uri>[];
      final repository = FakeChatsRepository()
        ..linkPreviews = {'https://example.com': examplePreview}
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body:
                'look `https://code.example` https://example.com '
                'and https://second.example',
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          ),
        ];

      await tester.pumpWidget(
        _app(repository, linkLauncher: (context, uri) async => opened.add(uri)),
      );
      await tester.pump();
      await tester.pump();

      expect(repository.linkPreviewRequests, ['https://example.com']);
      expect(find.byKey(const ValueKey('link-preview-card')), findsOneWidget);
      expect(find.text('Example'), findsOneWidget);
      expect(find.text('Example Domain'), findsOneWidget);
      expect(find.text('For use in examples'), findsOneWidget);

      await tester.tap(find.text('Example Domain'));
      await tester.pump();

      expect(opened, [Uri.parse('https://example.com')]);
    });

    testWidgets('suppressed, recalled and code-only links show no card', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..linkPreviews = {'https://example.com': examplePreview}
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body: 'https://example.com',
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
            suppressEmbeds: true,
          ),
          _message(
            id: 'message-2',
            senderId: 'user-2',
            body: 'https://example.com',
            createdAt: DateTime.utc(2026, 5, 18, 4, 31),
            recalledAt: DateTime.utc(2026, 5, 18, 4, 32),
          ),
          _message(
            id: 'message-3',
            senderId: 'user-2',
            body: '```\nhttps://example.com\n```',
            createdAt: DateTime.utc(2026, 5, 18, 4, 33),
          ),
        ];

      await tester.pumpWidget(_app(repository));
      await tester.pump();
      await tester.pump();

      expect(repository.linkPreviewRequests, isEmpty);
      expect(find.byKey(const ValueKey('link-preview-card')), findsNothing);
    });

    testWidgets('failed or empty previews render nothing', (tester) async {
      final repository = FakeChatsRepository()
        ..linkPreviewError = Exception('offline')
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body: 'see https://broken.example',
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          ),
          _message(
            id: 'message-2',
            senderId: 'user-2',
            body: 'see https://empty.example',
            createdAt: DateTime.utc(2026, 5, 18, 4, 31),
          ),
        ];

      await tester.pumpWidget(_app(repository));
      await tester.pump();
      await tester.pump();

      expect(
        repository.linkPreviewRequests,
        containsAll(['https://broken.example', 'https://empty.example']),
      );
      expect(find.byKey(const ValueKey('link-preview-card')), findsNothing);
      expect(find.text('see https://broken.example'), findsOneWidget);
    });

    testWidgets('the sender can remove the embed from the action menu', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..linkPreviews = {'https://example.com': examplePreview}
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-1',
            body: 'mine https://example.com',
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          ),
        ];

      await tester.pumpWidget(_app(repository));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('link-preview-card')), findsOneWidget);

      await tester.longPress(find.text('mine https://example.com'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove embed'));
      await tester.pumpAndSettle();

      expect(repository.suppressEmbedCalls, [('message-1', true)]);
      expect(find.byKey(const ValueKey('link-preview-card')), findsNothing);
    });

    testWidgets('remove embed is not offered without send permission', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..linkPreviews = {'https://example.com': examplePreview}
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-1',
            body: 'mine https://example.com',
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          ),
        ];

      await tester.pumpWidget(_app(repository, canSendMessages: false));
      await tester.pump();
      await tester.pump();

      await tester.longPress(find.text('mine https://example.com'));
      await tester.pumpAndSettle();
      expect(find.text('Remove embed'), findsNothing);
      expect(find.text('Edit'), findsNothing);
    });

    testWidgets('file messages show their name and size and open on tap', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            type: MessageType.file,
            body: '',
            attachment: const {
              'kind': 'file',
              'bucket': 'chat-files',
              'path': 'conversation-1/seed-notes.pdf',
              'name': 'notes.pdf',
              'mime_type': 'application/pdf',
              'size': 2048,
            },
            createdAt: DateTime.utc(2026, 10, 14, 9),
          ),
        ];
      await tester.pumpWidget(_app(repository));
      await tester.pump();

      expect(find.text('notes.pdf'), findsOneWidget);
      expect(find.text('2 KB · PDF'), findsOneWidget);
      await tester.tap(find.text('notes.pdf'));
      await tester.pumpAndSettle();
      expect(find.byType(FilePreviewScreen), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('file-preview-title')))
            .data,
        'notes.pdf',
      );
    });

    testWidgets('a timed-out member is told when they can talk again', (
      tester,
    ) async {
      final until = DateTime.now().add(const Duration(minutes: 10));
      await tester.pumpWidget(
        _app(
          FakeChatsRepository(),
          canSendMessages: false,
          timedOutUntil: until,
        ),
      );
      await tester.pump();

      expect(
        find.byKey(const ValueKey('chat-read-only-notice')),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          "You're timed out until ${formatTimeoutEnd(until)}",
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('remove embed is not offered on other people\'s messages', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..linkPreviews = {'https://example.com': examplePreview}
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body: 'theirs https://example.com',
            createdAt: DateTime.utc(2026, 5, 18, 4, 30),
          ),
          _message(
            id: 'message-2',
            senderId: 'user-1',
            body: 'mine without a link',
            createdAt: DateTime.utc(2026, 5, 18, 4, 31),
          ),
        ];

      await tester.pumpWidget(_app(repository));
      await tester.pump();
      await tester.pump();

      await tester.longPress(find.text('theirs https://example.com'));
      await tester.pumpAndSettle();
      expect(find.text('Remove embed'), findsNothing);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await tester.longPress(find.text('mine without a link'));
      await tester.pumpAndSettle();
      expect(find.text('Remove embed'), findsNothing);
    });
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

  testWidgets('channels without send permission show a read-only notice', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Announcement',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(
      _app(
        repository,
        conversationType: ConversationType.channel,
        canSendMessages: false,
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-read-only-notice')), findsOneWidget);
    expect(
      find.text("You don't have permission to send messages in this channel"),
      findsOneWidget,
    );
    expect(find.byTooltip('Attach'), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.longPress(find.text('Announcement'));
    await tester.pumpAndSettle();

    // Reactions still work; replying and threads need send permission.
    expect(find.text('Reply'), findsNothing);
    expect(find.text('Create thread'), findsNothing);
    expect(find.text('Forward'), findsOneWidget);
  });

  group('slowmode', () {
    // The composer's trailing button: Send, or the microphone while the
    // field is empty.
    WeCordIconButton sendButton(WidgetTester tester) {
      final send = find.byKey(const ValueKey('composer-send-button'));
      return tester.widget<WeCordIconButton>(
        send.evaluate().isNotEmpty
            ? send
            : find.byKey(const ValueKey('composer-mic-button')),
      );
    }

    testWidgets('shows the banner without a countdown before sending', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-2',
            body: 'Hello',
            createdAt: DateTime.now().toUtc(),
          ),
        ];

      await tester.pumpWidget(
        _app(
          repository,
          conversationType: ConversationType.channel,
          slowmodeSeconds: 30,
        ),
      );
      await tester.pump();

      expect(find.text('Slowmode is enabled'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('composer-slowmode-countdown')),
        findsNothing,
      );
      expect(sendButton(tester).onPressed, isNotNull);
    });

    testWidgets('counts down from the own latest message and blocks sends', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-1',
            body: 'Mine',
            createdAt: DateTime.now().toUtc().subtract(
              const Duration(seconds: 5),
            ),
          ),
        ];

      await tester.pumpWidget(
        _app(
          repository,
          conversationType: ConversationType.channel,
          slowmodeSeconds: 120,
        ),
      );
      await tester.pump();

      final countdown = tester.widget<Text>(
        find.byKey(const ValueKey('composer-slowmode-countdown')),
      );
      expect(countdown.data, matches(RegExp(r'^1:5\d$')));
      expect(sendButton(tester).onPressed, isNull);
      expect(
        tester
            .widget<WeCordIconButton>(
              find.byKey(const ValueKey('composer-attach-button')),
            )
            .onPressed,
        isNull,
      );

      await tester.enterText(find.byType(TextField), 'Too soon');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(repository.sentMessages, isEmpty);

      // The countdown keeps ticking while the thread is open.
      await tester.pump(const Duration(seconds: 1));
      expect(
        find.byKey(const ValueKey('composer-slowmode-countdown')),
        findsOneWidget,
      );
    });

    testWidgets('exempt members and old messages are not slowed', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..messages = [
          _message(
            id: 'message-1',
            senderId: 'user-1',
            body: 'Mine',
            createdAt: DateTime.now().toUtc().subtract(
              const Duration(minutes: 5),
            ),
          ),
        ];

      await tester.pumpWidget(
        _app(
          repository,
          conversationType: ConversationType.channel,
          slowmodeSeconds: 60,
        ),
      );
      await tester.pump();
      expect(sendButton(tester).onPressed, isNotNull);

      await tester.pumpWidget(
        _app(
          repository,
          conversationType: ConversationType.channel,
          slowmodeSeconds: 0,
        ),
      );
      await tester.pump();
      expect(find.text('Slowmode is enabled'), findsNothing);
    });

    testWidgets('a slowmode refusal starts the server countdown', (
      tester,
    ) async {
      final repository = FakeChatsRepository()
        ..sendError = const SlowmodeException(45);

      await tester.pumpWidget(
        _app(
          repository,
          conversationType: ConversationType.channel,
          slowmodeSeconds: 60,
        ),
      );
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Sent elsewhere');

      await tester.pump();
      await tester.tap(find.byTooltip('Send'));
      await tester.pump();

      final countdown = tester.widget<Text>(
        find.byKey(const ValueKey('composer-slowmode-countdown')),
      );
      expect(countdown.data, anyOf('45s', '44s'));
      expect(find.text('Could not send message. Try again.'), findsNothing);
      // The draft stays for later.
      expect(find.text('Sent elsewhere'), findsOneWidget);
      expect(sendButton(tester).onPressed, isNull);
    });

    test('countdowns read as seconds, minutes or hours', () {
      expect(formatSlowmodeCountdown(9), '9s');
      expect(formatSlowmodeCountdown(59), '59s');
      expect(formatSlowmodeCountdown(60), '1:00');
      expect(formatSlowmodeCountdown(125), '2:05');
      expect(formatSlowmodeCountdown(3600), '1:00:00');
      expect(formatSlowmodeCountdown(21599), '5:59:59');
    });
  });

  testWidgets('read-only falls back to the conversation list', (tester) async {
    final repository = FakeChatsRepository()
      ..conversations = [
        const ConversationSummary(
          id: 'conversation-1',
          type: ConversationType.channel,
          unreadCount: 0,
          canSendMessages: false,
        ),
      ];

    await tester.pumpWidget(
      _app(repository, conversationType: ConversationType.channel),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-read-only-notice')), findsOneWidget);
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

    expect(highlightColor()!.a, greaterThan(0));

    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));

    expect(highlightColor()!.a, 0);
  });

  testWidgets('a message search result opens scrolled to its message', (
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
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    expect(find.text('History 3'), findsNothing);

    final container = ProviderScope.containerOf(
      tester.element(find.byType(ChatThreadScreen)),
    );
    // A jump for another conversation is left alone.
    container.read(pendingMessageJumpProvider.notifier).state =
        const MessageJump(conversationId: 'other', messageId: 'message-3');
    await tester.pump();
    expect(container.read(pendingMessageJumpProvider), isNotNull);

    container
        .read(pendingMessageJumpProvider.notifier)
        .state = const MessageJump(
      conversationId: 'conversation-1',
      messageId: 'message-3',
    );
    for (var frame = 0; frame < 40; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(container.read(pendingMessageJumpProvider), isNull);
    final target = find.text('History 3');
    expect(target, findsOneWidget);
    final targetY = tester.getCenter(target).dy;
    expect(targetY, greaterThan(0));
    expect(targetY, lessThan(tester.getSize(find.byType(Scaffold)).height));
    final highlight = tester.widget<AnimatedContainer>(
      find.ancestor(of: target, matching: find.byType(AnimatedContainer)).first,
    );
    expect((highlight.decoration as BoxDecoration?)?.color?.a, greaterThan(0));
    await tester.pump(const Duration(seconds: 3));
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

    final colors = tester.element(find.text('React to me')).tokens.colors;
    BoxDecoration chip(String emoji) {
      return tester
              .widget<AnimatedContainer>(
                find.descendant(
                  of: find.byKey(ValueKey('reaction-chip-$emoji')),
                  matching: find.byKey(const ValueKey('reaction-body')),
                ),
              )
              .decoration!
          as BoxDecoration;
    }

    // Mine is outlined in the accent; the others sit on the raised fill.
    expect(chip('👍').border, isNotNull);
    expect((chip('👍').border! as Border).top.color, colors.accent);
    expect(chip('🎉').color, colors.raised);
    expect(chip('🎉').border, isNull);
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

    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
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

  testWidgets('reply preview of an unloaded deleted message reads deleted', (
    tester,
  ) async {
    // The server empties the quote once the original is deleted, even when
    // the original is not in the loaded page.
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-2',
          senderId: 'user-1',
          body: 'Reply body',
          createdAt: DateTime.utc(2026, 5, 18, 4, 32),
          replyPreview: const ReplyPreview(
            messageId: 'message-older',
            senderName: 'Ada',
            body: '',
            type: MessageType.text,
          ),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    expect(find.text('Reply body'), findsOneWidget);
    expect(find.text('Message deleted'), findsOneWidget);
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

    expect(find.byType(FilePreviewScreen), findsOneWidget);
  });

  testWidgets('image action menu offers Copy text from picture', (
    tester,
  ) async {
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
    expect(find.text('Copy text from picture'), findsOneWidget);

    await tester.tap(find.text('Copy text from picture'));
    await tester.pumpAndSettle();
    // Tests have no Apple Vision, like the web: the sheet says where it
    // works instead of reading or sending the picture anywhere.
    expect(find.text('Text from picture'), findsOneWidget);
    expect(find.text('Available in the iPhone and Mac apps'), findsOneWidget);
  });

  testWidgets('text messages have no Copy text from picture', (tester) async {
    final repository = FakeChatsRepository()
      ..messages = [
        _message(
          id: 'message-1',
          senderId: 'user-2',
          body: 'Just words',
          createdAt: DateTime.utc(2026, 5, 18, 4, 30),
        ),
      ];

    await tester.pumpWidget(_app(repository));
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('Just words'));
    await tester.pumpAndSettle();
    expect(find.text('Copy text from picture'), findsNothing);
  });

  testWidgets('empty composer does not send', (tester) async {
    final repository = FakeChatsRepository();

    await tester.pumpWidget(_app(repository));
    await tester.pump();

    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    // Phones keep the microphone until there is something to send.
    expect(find.byTooltip('Send'), findsNothing);
    await tester.testTextInput.receiveAction(TextInputAction.send);
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

    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
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

    await tester.pump();
    await tester.tap(find.byTooltip('Send'));
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

    await tester.tap(find.byKey(const ValueKey('paper-page-back')));
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
    final avatarFinder = find.descendant(
      of: find.byKey(const ValueKey('chat-thread-header')),
      matching: find.byType(ChatAvatar),
    );
    expect(
      tester.widget<ChatAvatar>(avatarFinder).avatarUrl,
      'profile-avatars/user-2/ada.png',
    );
    // The signed URL is what the avatar loads; images cannot load in tests,
    // so the initials show afterwards.
    final container = ProviderScope.containerOf(tester.element(avatarFinder));
    expect(
      container
          .read(avatarDisplayUrlProvider('profile-avatars/user-2/ada.png'))
          .value,
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

  testWidgets('group headers show members and who is online, not Offline', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..groupDetail = GroupDetail(
        conversationId: 'conversation-1',
        title: 'Launch Crew',
        members: [
          for (final (id, name) in [
            ('user-1', 'Me'),
            ('friend-1', 'Grace'),
            ('friend-2', 'Ada'),
          ])
            GroupMember(
              profile: _profile(id: id, username: id, displayName: name),
              role: 'member',
            ),
        ],
      );
    final online = StreamController<Set<String>>.broadcast();
    addTearDown(online.close);

    await tester.pumpWidget(
      _app(
        repository,
        conversationType: ConversationType.group,
        onlineUserIds: online.stream,
      ),
    );
    await tester.pump();
    expect(find.text('3 members'), findsOneWidget);
    expect(find.text('Offline'), findsNothing);

    online.add({'user-1', 'friend-2', 'stranger'});
    await tester.pump();
    await tester.pump();
    expect(find.text('3 members · 2 online'), findsOneWidget);
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

  testWidgets('channel topics show under the title and open in full', (
    tester,
  ) async {
    const topic =
        'Weekend plans, trip logistics and everything else that does not '
        'fit anywhere else. Be kind and keep it on topic.';
    await tester.pumpWidget(
      _app(
        FakeChatsRepository(),
        title: '# general',
        conversationType: ConversationType.channel,
        topic: topic,
      ),
    );
    await tester.pump();

    final subtitle = tester.widget<Text>(
      find.byKey(const ValueKey('chat-thread-subtitle')),
    );
    expect(subtitle.data, topic);
    expect(subtitle.maxLines, 1);
    expect(find.text('Offline'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('chat-thread-topic')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.widgetWithText(AlertDialog, '# general'), findsOneWidget);
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('channels without a topic keep the online state', (tester) async {
    await tester.pumpWidget(
      _app(
        FakeChatsRepository(),
        title: '# general',
        conversationType: ConversationType.channel,
        topic: '   ',
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('chat-thread-topic')), findsNothing);
    expect(find.text('Offline'), findsOneWidget);
  });
}

Widget _app(
  FakeChatsRepository repository, {
  ChatMediaPicker? mediaPicker,
  FakeChatMediaUploader? uploader,
  VoiceMessageRecorder? voiceMessageRecorder,
  String? title = 'Ada Lovelace',
  ConversationType? conversationType,
  LinkLauncher? linkLauncher,
  Stream<Set<String>>? onlineUserIds,
  ValueChanged<ThreadTarget>? onOpenThread,
  bool? canSendMessages,
  DateTime? timedOutUntil,
  int? slowmodeSeconds,
  String? topic,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      ...overrides,
      chatsRepositoryProvider.overrideWithValue(repository),
      onlineUserIdsProvider.overrideWith(
        (ref) => onlineUserIds ?? const Stream<Set<String>>.empty(),
      ),
      if (linkLauncher != null)
        linkLauncherProvider.overrideWithValue(linkLauncher),
      settingsRepositoryProvider.overrideWithValue(FakeSettingsRepository()),
      ...filePreviewOverrides(),
      if (mediaPicker != null)
        chatMediaPickerProvider.overrideWithValue(mediaPicker),
      if (uploader != null) ...[
        chatMediaUploaderProvider.overrideWithValue(uploader),
        pendingMediaStoreProvider.overrideWithValue(MemoryPendingMediaStore()),
      ],
      // Tests that let real time pass would otherwise reach for the
      // microphone plugin.
      if (voiceMessageRecorder != null || mediaPicker != null)
        voiceMessageRecorderProvider.overrideWithValue(
          voiceMessageRecorder ?? FakeVoiceMessageRecorder(),
        ),
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
        onOpenThread: onOpenThread,
        canSendMessages: canSendMessages,
        timedOutUntil: timedOutUntil,
        slowmodeSeconds: slowmodeSeconds,
        topic: topic,
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

  @override
  Future<void> setCustomStatus({
    String? emoji,
    String? text,
    DateTime? expiresAt,
  }) async {}
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
  bool suppressEmbeds = false,
  Profile? sender,
  String? attachmentGroupId,
}) {
  return ChatMessage(
    id: id,
    attachmentGroupId: attachmentGroupId,
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
    suppressEmbeds: suppressEmbeds,
    sender: sender,
  );
}

/// A repository that takes part in the outbox, so attachments are queued,
/// uploaded and stored through [mediaSender].
class OutboxChatsRepository extends FakeChatsRepository
    implements OutboxMessageSender, MediaMessageSender {
  final mediaSender = FakeMediaMessageSender();

  @override
  Future<void> notifyMessageSent(String messageId) =>
      mediaSender.notifyMessageSent(messageId);

  @override
  Future<String?> sendQueuedTextMessage({
    required String conversationId,
    required String clientId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const [],
  }) async {
    sentMessages.add(SentMessage(conversationId: conversationId, body: body));
    return 'text-${sentMessages.length}';
  }

  @override
  Future<String?> sendQueuedMediaMessage({
    required String conversationId,
    required String clientId,
    required MessageType type,
    required Map<String, dynamic> attachment,
    String body = '',
    String? attachmentGroupId,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    bool notify = true,
  }) {
    return mediaSender.sendQueuedMediaMessage(
      conversationId: conversationId,
      clientId: clientId,
      type: type,
      attachment: attachment,
      body: body,
      attachmentGroupId: attachmentGroupId,
      replyToMessageId: replyToMessageId,
      replyPreview: replyPreview,
      notify: notify,
    );
  }
}

/// Lets the engine's real work (decoding pictures, files) run between
/// frames.
Future<void> _settleMedia(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 40)),
    );
    await tester.pump();
  }
}

Future<void> _openAttach(WidgetTester tester, String entry) async {
  await tester.tap(find.byTooltip('Attach'));
  await tester.pumpAndSettle();
  await tester.tap(find.text(entry));
  await tester.pump();
}

class FakeChatsRepository implements ChatsRepository {
  final createdPolls =
      <
        ({
          String conversationId,
          String question,
          List<String> options,
          bool multi,
          int? durationHours,
        })
      >[];
  final pollVotes = <(String, List<String>)>[];
  final endedPolls = <String>[];
  var canModeratePollsValue = false;
  var canModerateMessagesValue = false;
  final sentStickers = <(String, String)>[];
  var pollVoters = <String, List<Profile>>{};

  @override
  Future<void> createPoll({
    required String conversationId,
    required String question,
    required List<String> options,
    required bool multi,
    int? durationHours,
  }) async {
    if (sendError case final error?) {
      throw error;
    }
    createdPolls.add((
      conversationId: conversationId,
      question: question,
      options: options,
      multi: multi,
      durationHours: durationHours,
    ));
  }

  @override
  Future<void> votePoll({
    required String messageId,
    required List<String> optionIds,
  }) async {
    pollVotes.add((messageId, optionIds));
  }

  @override
  Future<void> endPoll({required String messageId}) async {
    endedPolls.add(messageId);
  }

  @override
  Future<bool> canModeratePolls(String conversationId) async =>
      canModeratePollsValue;

  @override
  Future<List<Profile>> listPollVoters({
    required String messageId,
    required String optionId,
  }) async => pollVoters[optionId] ?? const [];

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
  var linkPreviews = <String, LinkPreview>{};
  Object? linkPreviewError;
  final linkPreviewRequests = <String>[];
  final suppressEmbedCalls = <(String, bool)>[];
  final typingUpdates = <TypingUpdate>[];
  final markReadCalls = <String>[];
  final createdThreads =
      <({String parentConversationId, String? rootMessageId, String? title})>[];
  final archiveCalls = <(String, bool)>[];
  var canManageThreads = false;
  String? sentReplyToMessageId;
  ReplyPreview? sentReplyPreview;
  var sentMentions = const <MessageMention>[];
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
    sentMentions = mentions;
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
  Future<void> sendSticker({
    required String conversationId,
    required String stickerId,
  }) async {
    if (sendError case final error?) {
      throw error;
    }
    sentStickers.add((conversationId, stickerId));
  }

  @override
  Future<bool> canModerateMessages(String conversationId) async =>
      canModerateMessagesValue;

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
  Future<LinkPreview?> getLinkPreview(String url) async {
    linkPreviewRequests.add(url);
    if (linkPreviewError case final error?) {
      throw error;
    }
    return linkPreviews[url];
  }

  @override
  Future<void> setMessageSuppressEmbeds({
    required String messageId,
    required bool suppress,
  }) async {
    suppressEmbedCalls.add((messageId, suppress));
    messages = [
      for (final message in messages)
        message.id == messageId
            ? message.copyWith(suppressEmbeds: suppress)
            : message,
    ];
  }

  @override
  Future<ConversationThread> createThread({
    required String parentConversationId,
    String? rootMessageId,
    String? title,
  }) async {
    createdThreads.add((
      parentConversationId: parentConversationId,
      rootMessageId: rootMessageId,
      title: title,
    ));
    return ConversationThread(
      id: 'thread-1',
      conversationId: 'thread-conversation-1',
      parentConversationId: parentConversationId,
      rootMessageId: rootMessageId,
      title: title ?? 'Thread',
      createdAt: DateTime.utc(2026, 10, 13),
    );
  }

  @override
  Future<List<ConversationThread>> listThreads(
    String parentConversationId,
  ) async => const [];

  @override
  Future<ConversationThread> setThreadArchived({
    required String threadId,
    required bool archived,
  }) async {
    archiveCalls.add((threadId, archived));
    conversations = [
      for (final conversation in conversations)
        conversation.threadId == threadId
            ? ConversationSummary(
                id: conversation.id,
                type: conversation.type,
                unreadCount: conversation.unreadCount,
                title: conversation.title,
                parentConversationId: conversation.parentConversationId,
                parentTitle: conversation.parentTitle,
                circleId: conversation.circleId,
                threadId: conversation.threadId,
                threadArchivedAt: archived ? DateTime.utc(2026, 10, 13) : null,
              )
            : conversation,
    ];
    return ConversationThread(
      id: threadId,
      conversationId: 'thread-conversation-1',
      parentConversationId: 'conversation-1',
      title: 'Thread',
      createdAt: DateTime.utc(2026, 10, 13),
      archivedAt: archived ? DateTime.utc(2026, 10, 13) : null,
    );
  }

  @override
  Future<bool> canManageThread(String threadId) async => canManageThreads;

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

  void emitActivity(ConversationActivity next) {
    activity = next;
    _activityChanges.add(next);
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

/// The chat avatars drawn for [name].
Finder _avatarsOf(String name) => find.byWidgetPredicate(
  (widget) => widget is ChatAvatar && widget.name == name,
);

import 'dart:typed_data';

import 'package:file_selector/file_selector.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/media_draft.dart';
import 'package:wecord/features/chats/media_send/media_picker.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/pending_media_store.dart';
import 'package:wecord/features/chats/media_send/media_tray_controller.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/view_once.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/ui/ui.dart';

import 'chat_thread_screen_test.dart' as chat_fakes;
import 'media_send/media_fakes.dart';

class _FakeViewOnce implements ViewOnceRepository {
  final opened = <String>[];
  var opens = <String, List<ViewOnceOpen>>{};
  Object? error;

  @override
  Future<ViewOnceFile> open(String messageId) async {
    if (error case final error?) {
      throw error;
    }
    opened.add(messageId);
    return const ViewOnceFile(
      url: 'https://example.invalid/x.jpg',
      isVideo: false,
    );
  }

  @override
  Stream<List<ViewOnceOpen>> watchOpens(String messageId) =>
      Stream.value(opens[messageId] ?? const []);
}

ChatMessage _once({
  String id = 'once-1',
  String senderId = 'user-2',
  MessageType type = MessageType.image,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'conversation-1',
    senderId: senderId,
    type: type,
    body: '',
    createdAt: DateTime.utc(2026, 10, 17, 9),
    attachment: {
      'kind': type == MessageType.image ? 'image' : 'video',
      'bucket': type == MessageType.image ? 'chat-images' : 'chat-files',
      'path': 'conversation-1/once.jpg',
      'mime_type': 'image/jpeg',
      'size': 10,
      'view_once': true,
    },
  );
}

class _World {
  _World() {
    chats.conversations = const [
      ConversationSummary(
        id: 'conversation-1',
        type: ConversationType.direct,
        unreadCount: 0,
        title: 'Ada',
      ),
    ];
  }

  final chats = chat_fakes.OutboxChatsRepository();
  final once = _FakeViewOnce();
  final picker = FakeChatMediaPicker();
  final uploader = FakeChatMediaUploader();

  Widget app() {
    return ProviderScope(
      overrides: [
        chatsRepositoryProvider.overrideWithValue(chats),
        chatMediaPickerProvider.overrideWithValue(picker),
        chatMediaUploaderProvider.overrideWithValue(uploader),
        pendingMediaStoreProvider.overrideWithValue(MemoryPendingMediaStore()),
        viewOnceRepositoryProvider.overrideWithValue(once),
        voiceMessageRecorderProvider.overrideWithValue(
          chat_fakes.FakeVoiceMessageRecorder(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          chat_fakes.FakeSettingsRepository(),
        ),
        onlineUserIdsProvider.overrideWith(
          (ref) => const Stream<Set<String>>.empty(),
        ),
        authRepositoryProvider.overrideWithValue(
          chat_fakes.FakeAuthRepository()
            ..user = const AuthUser(id: 'user-1', email: 'me@example.com'),
        ),
      ],
      child: const MaterialApp(
        home: ChatThreadScreen(conversationId: 'conversation-1'),
      ),
    );
  }
}

void main() {
  test('messages know they are view-once', () {
    expect(_once().isViewOnce, isTrue);
    expect(_once(type: MessageType.file).isViewOnce, isTrue);
    expect(
      ChatMessage(
        id: 'm',
        conversationId: 'c',
        senderId: 'u',
        type: MessageType.text,
        body: 'hi',
        createdAt: DateTime.utc(2026),
        attachment: const {'view_once': true},
      ).isViewOnce,
      isFalse,
      reason: 'only photos and videos',
    );
  });

  test('view-once media has no blurhash and says so in its attachment', () {
    const media = OutboxMedia(
      kind: OutboxMediaKind.image,
      fileName: 'a.jpg',
      mimeType: 'image/jpeg',
      size: 10,
      blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
      viewOnce: true,
    );
    final json = media.attachmentJson('c/a.jpg');
    expect(json['view_once'], isTrue);
    expect(json.containsKey('blurhash'), isFalse);
    expect(OutboxMedia.fromJson(media.toJson()).viewOnce, isTrue);
    const plain = OutboxMedia(
      kind: OutboxMediaKind.image,
      fileName: 'a.jpg',
      mimeType: 'image/jpeg',
      size: 10,
      blurhash: 'LEHV6nWB2yk8pyo0adR*.7kCMdnj',
    );
    expect(plain.attachmentJson('c/a.jpg').containsKey('view_once'), isFalse);
    expect(plain.attachmentJson('c/a.jpg')['blurhash'], isNotNull);
  });

  test('the tray offers view-once for photos and videos, not files', () {
    final photo = DraftAttachment(
      id: '1',
      file: _file(),
      name: 'a.jpg',
      mimeType: 'image/jpeg',
      size: 1,
      kind: DraftKind.image,
    );
    final doc = DraftAttachment(
      id: '2',
      file: _file(),
      name: 'a.pdf',
      mimeType: 'application/pdf',
      size: 1,
      kind: DraftKind.file,
    );
    expect(const MediaTrayState().canViewOnce, isFalse);
    expect(
      MediaTrayState(items: [photo], viewOnce: true).sendsViewOnce,
      isTrue,
    );
    expect(
      MediaTrayState(items: [photo, doc], viewOnce: true).sendsViewOnce,
      isFalse,
    );
    expect(MediaTrayState(items: [photo]).sendsViewOnce, isFalse);
  });

  testWidgets('a recipient sees a tile, opens it once and then "Opened"', (
    tester,
  ) async {
    final world = _World()..chats.messages = [_once()];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(find.text('Photo'), findsOneWidget);
    expect(find.text('Tap to open · View once'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    await tester.tap(find.byKey(const ValueKey('view-once-once-1')));
    await tester.pumpAndSettle();
    expect(find.textContaining("can't stop screenshots"), findsOneWidget);
    expect(world.once.opened, isEmpty);

    await tester.tap(find.byKey(const ValueKey('view-once-confirm')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(world.once.opened, ['once-1']);
    expect(find.byKey(const ValueKey('view-once-viewer')), findsOneWidget);
    expect(find.textContaining("can't be blocked"), findsOneWidget);
    // Nothing to save, share or forward.
    expect(find.byTooltip('Download'), findsNothing);
    expect(find.byTooltip('Share'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('view-once-close')));
    await tester.pumpAndSettle();
    expect(find.text('Opened'), findsOneWidget);
    expect(find.byKey(const ValueKey('view-once-viewer')), findsNothing);
  });

  testWidgets('cancelling the reminder opens nothing', (tester) async {
    final world = _World()..chats.messages = [_once()];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('view-once-once-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(world.once.opened, isEmpty);
    expect(find.text('Tap to open · View once'), findsOneWidget);
  });

  testWidgets('already opened elsewhere says so', (tester) async {
    final world = _World()
      ..chats.messages = [_once()]
      ..once.error = const ViewOnceAlreadyOpened();
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('view-once-once-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('view-once-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('You already opened this one.'), findsOneWidget);
  });

  testWidgets('opened by me before shows Opened and cannot be tapped', (
    tester,
  ) async {
    final world = _World()
      ..chats.messages = [_once()]
      ..once.opens = {
        'once-1': [
          ViewOnceOpen(userId: 'user-1', openedAt: DateTime.utc(2026, 10, 17)),
        ],
      };
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(find.text('Opened'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('view-once-once-1')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('the sender sees Not opened, then Opened', (tester) async {
    final world = _World()
      ..chats.messages = [
        _once(senderId: 'user-1'),
        _once(id: 'once-2', senderId: 'user-1'),
      ]
      ..once.opens = {
        'once-2': [
          ViewOnceOpen(userId: 'user-2', openedAt: DateTime.utc(2026, 10, 17)),
        ],
      };
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    expect(find.text('Not opened'), findsOneWidget);
    expect(find.text('Opened'), findsOneWidget);
    // The sender cannot look at it again.
    await tester.tap(find.byKey(const ValueKey('view-once-once-1')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('view-once media has no menu entries for saving or forwarding', (
    tester,
  ) async {
    final world = _World()..chats.messages = [_once()];
    await tester.pumpWidget(world.app());
    await tester.pump();
    await tester.pump();

    await tester.longPress(find.text('Photo'));
    await tester.pumpAndSettle();
    expect(find.text('Forward'), findsNothing);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Copy'), findsNothing);
  });

  group('sending', () {
    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump();
      }
    }

    Future<_World> pickTwoPhotos(WidgetTester tester) async {
      final world = _World()
        ..picker.photos = [testPhoto('a.jpg'), testPhoto('holiday-beach.jpg')];
      await tester.pumpWidget(world.app());
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos and videos'));
      await tester.pump();
      await settle(tester);
      return world;
    }

    testWidgets('the tray offers View once and says what it can\'t do', (
      tester,
    ) async {
      await pickTwoPhotos(tester);

      expect(
        find.byKey(const ValueKey('media-tray-view-once')),
        findsOneWidget,
      );
      expect(find.textContaining('Let people open each photo'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media-tray-view-once')));
      await tester.pump();
      expect(find.textContaining("can't be blocked"), findsOneWidget);
    });

    testWidgets('with it on, each photo goes out alone, flagged, anonymous', (
      tester,
    ) async {
      final world = await pickTwoPhotos(tester);
      await tester.tap(find.byKey(const ValueKey('media-tray-view-once')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('media-tray-send')));
      await settle(tester);

      final calls = world.chats.mediaSender.calls;
      expect(calls, hasLength(2));
      expect(calls.map((call) => call['group']), [null, null]);
      expect(calls.map((call) => call['body']), ['', '']);
      for (final call in calls) {
        final attachment = call['attachment']! as Map<String, dynamic>;
        expect(attachment['view_once'], isTrue);
        expect(attachment.containsKey('blurhash'), isFalse);
        expect(attachment['path'], isNot(contains('holiday')));
      }
      // The switch does not stay on for the next picture.
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Photos and videos'));
      await tester.pump();
      await settle(tester);
      expect(
        tester
            .widget<WeCordSwitch>(
              find.byKey(const ValueKey('media-tray-view-once')),
            )
            .value,
        isFalse,
      );
    });

    testWidgets('files are not offered it', (tester) async {
      final world = _World()
        ..picker.files = [
          XFile.fromData(
            Uint8List.fromList([1, 2, 3]),
            name: 'notes.txt',
            path: 'notes.txt',
            mimeType: 'text/plain',
            length: 3,
          ),
        ];
      await tester.pumpWidget(world.app());
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byTooltip('Attach'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Files'));
      await tester.pump();
      await settle(tester);
      expect(find.byKey(const ValueKey('media-tray')), findsOneWidget);
      expect(find.byKey(const ValueKey('media-tray-view-once')), findsNothing);
    });
  });
}

XFile _file() => XFile.fromData(Uint8List(1), name: 'x');

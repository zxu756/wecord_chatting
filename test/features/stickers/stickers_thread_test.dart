import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chat_thread_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/custom_emoji.dart';
import 'package:wecord/features/chats/media_send/album_grid.dart';
import 'package:wecord/features/chats/voice_message_recorder.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/features/settings/settings_repository.dart';
import 'package:wecord/features/stickers/add_to_stickers_action.dart';
import 'package:wecord/features/stickers/sticker_formats.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/message.dart';

import '../chats/chat_thread_screen_test.dart' as chat_fakes;
import '../circles/circle_emojis_test.dart';
import 'sticker_fakes.dart';

const _giphy = 'https://media.giphy.com/media/abc/giphy.gif';

ChatMessage _message(
  String id,
  String body, {
  int minute = 0,
  String senderId = 'user-2',
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
    recalledAt: recalledAt,
    createdAt: DateTime.utc(2026, 10, 22, 9, minute),
  );
}

Map<String, dynamic> _personalSticker({bool animated = false}) => {
  'kind': 'sticker',
  'personal': true,
  'bucket': 'chat-images',
  'path': 'conversation-1/sticker-1.${animated ? 'gif' : 'png'}',
  'mime_type': animated ? 'image/gif' : 'image/png',
  'width': 256,
  'height': 256,
  'animated': animated,
};

Map<String, dynamic> _photo({bool viewOnce = false}) => {
  'kind': 'image',
  'bucket': 'chat-images',
  'path': 'conversation-1/photo.png',
  'mime_type': 'image/png',
  'size': 1200,
  'width': 120,
  'height': 120,
  if (viewOnce) 'view_once': true,
};

chat_fakes.FakeChatsRepository _chat(
  List<ChatMessage> messages, {
  bool channel = false,
}) {
  return chat_fakes.FakeChatsRepository()
    ..conversations = [
      ConversationSummary(
        id: 'conversation-1',
        type: channel ? ConversationType.channel : ConversationType.direct,
        unreadCount: 0,
        title: channel ? 'general' : 'Bart',
        circleId: channel ? 'circle-1' : null,
      ),
    ]
    ..messages = messages;
}

Widget _app(
  chat_fakes.FakeChatsRepository chats,
  FakeUserStickersRepository stickers, {
  FakeStickerCutout? cutout,
  Future<Uint8List> Function(Uri)? fetcher,
}) {
  return ProviderScope(
    overrides: [
      chatsRepositoryProvider.overrideWithValue(chats),
      circleEmojiRepositoryProvider.overrideWithValue(
        FakeCircleEmojiRepository(),
      ),
      testEmojiImageOverride(),
      ...stickerOverrides(stickers, cutout: cutout),
      voiceMessageRecorderProvider.overrideWithValue(
        chat_fakes.FakeVoiceMessageRecorder(),
      ),
      chatImageProviderFactoryProvider.overrideWithValue(
        (url) => MemoryImage(samplePhotoPng(width: 120, height: 120)),
      ),
      if (fetcher != null) stickerUrlFetcherProvider.overrideWithValue(fetcher),
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

/// Lets the sheet download and prepare its picture; its spinner never stops,
/// so this does not wait for the frames to settle.
Future<void> _letSheetLoad(WidgetTester tester) async {
  for (var round = 0; round < 4; round++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 120)),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
}

void main() {
  group('a personal sticker in a chat', () {
    testWidgets('shows its copy without a bubble, and is not forwarded', (
      tester,
    ) async {
      final chats = _chat([
        _message(
          'm1',
          '',
          type: MessageType.sticker,
          attachment: _personalSticker(),
        ),
      ]);
      await tester.pumpWidget(_app(chats, FakeUserStickersRepository()));
      await tester.pumpAndSettle();

      final sticker = find.byKey(
        const ValueKey('sticker-image-conversation-1/sticker-1.png'),
      );
      expect(sticker, findsOneWidget);
      expect(tester.getSize(sticker), const Size.square(stickerSize));
      expect(find.byKey(const ValueKey('sticker-placeholder')), findsNothing);

      await tester.longPress(sticker);
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Add to stickers'), findsOneWidget);
      expect(find.text('Forward'), findsNothing);
    });

    testWidgets('a copy that cannot be loaded shows a placeholder', (
      tester,
    ) async {
      final chats = _chat([
        _message(
          'm1',
          '',
          type: MessageType.sticker,
          attachment: _personalSticker(),
        ),
      ]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatsRepositoryProvider.overrideWithValue(chats),
            circleEmojiRepositoryProvider.overrideWithValue(
              FakeCircleEmojiRepository(),
            ),
            testEmojiImageOverride(),
            ...stickerOverrides(
              FakeUserStickersRepository(),
              imagesLoad: false,
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
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('sticker-placeholder')), findsOneWidget);
    });
  });

  group('Add to stickers in the message menu', () {
    testWidgets('a picture is downloaded, previewed and saved', (tester) async {
      final chats = _chat([
        _message('m1', '', type: MessageType.image, attachment: _photo()),
      ]);
      final stickers = FakeUserStickersRepository();
      stickers.files['conversation-1/photo.png'] = samplePhotoPng();
      await tester.pumpWidget(_app(chats, stickers));
      await tester.pumpAndSettle();

      await tester.longPress(find.byType(Image).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-add-to-stickers')));
      await _letSheetLoad(tester);

      expect(stickers.downloads.single.bucket, 'chat-images');
      expect(stickers.downloads.single.path, 'conversation-1/photo.png');
      // The cut-out switch is there where the device can.
      expect(
        find.byKey(const ValueKey('add-sticker-cutout-switch')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('add-sticker-save')));
      await _letSheetLoad(tester);

      expect(stickers.added, hasLength(1));
      expect(stickers.added.single.format, StickerFormat.png);
      expect(stickers.added.single.width, 512);
      expect(find.text('Added to your stickers.'), findsOneWidget);
    });

    testWidgets('the cut-out switch is hidden where it is not available', (
      tester,
    ) async {
      final chats = _chat([
        _message('m1', '', type: MessageType.image, attachment: _photo()),
      ]);
      await tester.pumpWidget(
        _app(
          chats,
          FakeUserStickersRepository(),
          cutout: FakeStickerCutout(available: false),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(Image).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-add-to-stickers')));
      await _letSheetLoad(tester);
      expect(find.byKey(const ValueKey('add-sticker-save')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('add-sticker-cutout-switch')),
        findsNothing,
      );
    });

    testWidgets('a GIF message is fetched from its address', (tester) async {
      final chats = _chat([_message('m1', _giphy)]);
      final fetched = <Uri>[];
      await tester.pumpWidget(
        _app(
          chats,
          FakeUserStickersRepository(),
          fetcher: (uri) async {
            fetched.add(uri);
            return tinyGif(frames: 3);
          },
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.byType(Image).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-add-to-stickers')));
      await _letSheetLoad(tester);
      expect(fetched, [Uri.parse(_giphy)]);
      // A moving picture is kept moving, so there is nothing to cut out.
      expect(
        find.byKey(const ValueKey('add-sticker-cutout-switch')),
        findsNothing,
      );
    });

    testWidgets('plain text, view-once photos and deleted ones have no entry', (
      tester,
    ) async {
      final chats = _chat([
        _message('m1', 'hello there'),
        _message(
          'm2',
          '',
          minute: 1,
          type: MessageType.image,
          attachment: _photo(viewOnce: true),
        ),
      ]);
      await tester.pumpWidget(_app(chats, FakeUserStickersRepository()));
      await tester.pumpAndSettle();
      await tester.longPress(find.textContaining('hello there'));
      await tester.pumpAndSettle();
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Add to stickers'), findsNothing);
    });
  });

  group('the sticker picker', () {
    Future<void> openPicker(WidgetTester tester) async {
      await tester.tap(find.byKey(const ValueKey('composer-attach-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Send sticker'));
      await tester.pumpAndSettle();
    }

    testWidgets('a direct chat opens on Mine and sends the tapped sticker', (
      tester,
    ) async {
      final stickers = FakeUserStickersRepository([
        userSticker('s1'),
        userSticker('s2', animated: true),
      ]);
      await tester.pumpWidget(_app(_chat([_message('m1', 'Hi')]), stickers));
      await tester.pumpAndSettle();
      await openPicker(tester);

      expect(
        find.byKey(const ValueKey('my-sticker-option-s1')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('my-sticker-option-s2')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('my-sticker-option-s2')));
      await tester.pumpAndSettle();
      expect(stickers.sent, [
        (conversationId: 'conversation-1', stickerId: 's2'),
      ]);
    });

    testWidgets('a channel opens on its circle and Mine is one tap away', (
      tester,
    ) async {
      final stickers = FakeUserStickersRepository([userSticker('s1')]);
      await tester.pumpWidget(
        _app(_chat([_message('m1', 'Hi')], channel: true), stickers),
      );
      await tester.pumpAndSettle();
      await openPicker(tester);

      expect(find.text('This circle'), findsOneWidget);
      expect(find.byKey(const ValueKey('my-sticker-option-s1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('sticker-tab-mine')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('my-sticker-option-s1')),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('my-sticker-option-s1')));
      await tester.pumpAndSettle();
      expect(stickers.sent, [
        (conversationId: 'conversation-1', stickerId: 's1'),
      ]);
    });

    testWidgets('with no stickers of your own it says how to add some', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(_chat([_message('m1', 'Hi')]), FakeUserStickersRepository()),
      );
      await tester.pumpAndSettle();
      await openPicker(tester);
      expect(
        find.byKey(const ValueKey('my-stickers-panel-empty')),
        findsOneWidget,
      );
      expect(find.textContaining('Add to stickers'), findsOneWidget);
    });

    testWidgets('a failed send says so', (tester) async {
      final stickers = FakeUserStickersRepository([userSticker('s1')])
        ..sendError = StateError('no');
      await tester.pumpWidget(_app(_chat([_message('m1', 'Hi')]), stickers));
      await tester.pumpAndSettle();
      await openPicker(tester);
      await tester.tap(find.byKey(const ValueKey('my-sticker-option-s1')));
      await tester.pumpAndSettle();
      expect(find.text('Could not send sticker. Try again.'), findsOneWidget);
    });
  });

  test('the action sits between Forward and Translate', () {
    expect(addToStickersAction.order, inInclusiveRange(301, 399));
  });
}

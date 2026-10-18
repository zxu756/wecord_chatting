import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/circle_emoji_repository.dart';
import 'package:wecord/features/stickers/add_to_stickers_action.dart';
import 'package:wecord/features/stickers/user_stickers_repository.dart';
import 'package:wecord/shared/models/message.dart';

import '../circles/circle_emojis_test.dart';
import 'sticker_fakes.dart';

const _giphy = 'https://media.giphy.com/media/abc/giphy.gif';

ChatMessage _message(
  MessageType type, {
  String body = '',
  Map<String, dynamic>? attachment,
  DateTime? recalledAt,
}) {
  return ChatMessage(
    id: 'm1',
    conversationId: 'c1',
    senderId: 'user-2',
    type: type,
    body: body,
    attachment: attachment,
    recalledAt: recalledAt,
    createdAt: DateTime.utc(2026, 10, 22),
  );
}

Map<String, dynamic> _image({bool viewOnce = false}) => {
  'kind': 'image',
  'bucket': 'chat-images',
  'path': 'c1/p.png',
  'mime_type': 'image/png',
  'size': 10,
  if (viewOnce) 'view_once': true,
};

void main() {
  late FakeUserStickersRepository stickers;
  late ProviderContainer container;

  setUp(() async {
    stickers = FakeUserStickersRepository();
    container = ProviderContainer(
      overrides: [
        userStickersRepositoryProvider.overrideWithValue(stickers),
        circleEmojiRepositoryProvider.overrideWithValue(
          FakeCircleEmojiRepository(),
        ),
        stickerUrlFetcherProvider.overrideWithValue(
          (uri) async => Uint8List.fromList([uri.toString().length]),
        ),
      ],
    );
    addTearDown(container.dispose);
    // The circles' stickers load once, then are known to the menu.
    await container.read(usableEmojisProvider.future);
  });

  Future<Uint8List>? fetch(ChatMessage message) {
    return stickerSourceFor(message, container)?.call();
  }

  test('a picture comes from its file in the chat bucket', () async {
    await fetch(_message(MessageType.image, attachment: _image()));
    expect(stickers.downloads.single.bucket, 'chat-images');
    expect(stickers.downloads.single.path, 'c1/p.png');
  });

  test('a view-once photo and a deleted message cannot be kept', () {
    expect(
      fetch(_message(MessageType.image, attachment: _image(viewOnce: true))),
      isNull,
    );
    expect(
      fetch(
        _message(
          MessageType.image,
          attachment: _image(),
          recalledAt: DateTime.utc(2026, 10, 22),
        ),
      ),
      isNull,
    );
  });

  test('a personal sticker comes from its copy in the chat', () async {
    await fetch(
      _message(
        MessageType.sticker,
        attachment: {
          'kind': 'sticker',
          'personal': true,
          'bucket': 'chat-images',
          'path': 'c1/sticker-1.png',
        },
      ),
    );
    expect(stickers.downloads.single.path, 'c1/sticker-1.png');
  });

  test(
    'a circle sticker comes from the circle bucket, if it is usable',
    () async {
      await fetch(
        _message(
          MessageType.sticker,
          attachment: {
            'kind': 'sticker',
            'emoji_id': waveStickerId,
            'name': 'wave',
            'circle_id': 'circle-1',
          },
        ),
      );
      expect(stickers.downloads.single.bucket, 'circle-emojis');
      expect(stickers.downloads.single.path, contains(waveStickerId));

      // A sticker of a circle the person is not in cannot be read.
      expect(
        fetch(
          _message(
            MessageType.sticker,
            attachment: {
              'kind': 'sticker',
              'emoji_id': '00000000-0000-4000-8000-0000000000ff',
              'name': 'secret',
              'circle_id': 'circle-9',
            },
          ),
        ),
        isNull,
      );
    },
  );

  test('a message that is only a GIF address is fetched', () async {
    final bytes = await fetch(_message(MessageType.text, body: _giphy));
    expect(bytes, isNotEmpty);
    expect(fetch(_message(MessageType.text, body: 'hello')), isNull);
    expect(
      fetch(_message(MessageType.text, body: 'see $_giphy for more')),
      isNull,
    );
  });

  test('files, voice, polls and notices cannot be kept', () {
    for (final type in [
      MessageType.file,
      MessageType.voice,
      MessageType.poll,
      MessageType.system,
    ]) {
      expect(
        fetch(_message(type, attachment: _image())),
        isNull,
        reason: '$type',
      );
    }
  });
}

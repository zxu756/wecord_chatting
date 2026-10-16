import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/media_send/album_fold.dart';
import 'package:wecord/shared/models/message.dart';

ChatMessage _message(
  String id, {
  String sender = 'a',
  String? group,
  MessageType type = MessageType.image,
  DateTime? recalledAt,
}) {
  return ChatMessage(
    id: id,
    conversationId: 'c',
    senderId: sender,
    type: type,
    body: '',
    createdAt: DateTime.utc(2026, 10, 17),
    attachmentGroupId: group,
    recalledAt: recalledAt,
  );
}

void main() {
  test('messages of one album fold into the first', () {
    final result = foldAlbums([
      _message('1', group: 'g'),
      _message('2', group: 'g'),
      _message('3', group: 'g'),
    ]);

    expect(result.messages.map((m) => m.id), ['1']);
    expect(result.messages.single.album!.map((m) => m.id), ['1', '2', '3']);
    expect(result.headOf, {'2': '1', '3': '1'});
  });

  test('messages without an album id are left alone', () {
    final result = foldAlbums([
      _message('1'),
      _message('2'),
      _message('3', type: MessageType.text),
    ]);
    expect(result.messages.map((m) => m.id), ['1', '2', '3']);
    expect(result.messages.every((m) => m.album == null), isTrue);
    expect(result.headOf, isEmpty);
  });

  test('a lone message of an album stays a plain message', () {
    final result = foldAlbums([_message('1', group: 'g')]);
    expect(result.messages.single.album, isNull);
  });

  test('another sender, another album or a text ends a run', () {
    final result = foldAlbums([
      _message('1', group: 'g'),
      _message('2', group: 'g'),
      _message('3', group: 'g', sender: 'b'),
      _message('4', group: 'h', sender: 'b'),
      _message('5', group: 'h', sender: 'b'),
      _message('6', group: 'h', sender: 'b', type: MessageType.text),
      _message('7', group: 'h', sender: 'b'),
    ]);

    expect(result.messages.map((m) => m.id), ['1', '3', '4', '6', '7']);
    expect(result.messages[0].album!.map((m) => m.id), ['1', '2']);
    expect(result.messages[2].album!.map((m) => m.id), ['4', '5']);
    expect(result.messages[1].album, isNull);
    expect(result.messages[4].album, isNull);
  });

  test('a deleted message leaves the album', () {
    final result = foldAlbums([
      _message('1', group: 'g'),
      _message('2', group: 'g', recalledAt: DateTime.utc(2026, 10, 17, 1)),
      _message('3', group: 'g'),
      _message('4', group: 'g'),
    ]);

    // The deleted one shows as "Message deleted"; the rest still group.
    expect(result.messages.map((m) => m.id), ['1', '2', '3']);
    expect(result.messages[2].album!.map((m) => m.id), ['3', '4']);
  });

  test('files fold with pictures', () {
    final result = foldAlbums([
      _message('1', group: 'g'),
      _message('2', group: 'g', type: MessageType.file),
    ]);
    expect(result.messages.single.album, hasLength(2));
  });

  test('the folded message keeps what the first one had', () {
    final first = ChatMessage(
      id: '1',
      conversationId: 'c',
      senderId: 'a',
      type: MessageType.image,
      body: 'Trip',
      createdAt: DateTime.utc(2026, 10, 17),
      attachmentGroupId: 'g',
      reactions: const [MessageReaction(emoji: '👍', count: 2)],
      clientId: 'client-1',
    );
    final folded = foldAlbums([
      first,
      _message('2', group: 'g'),
    ]).messages.single;
    expect(folded.id, '1');
    expect(folded.body, 'Trip');
    expect(folded.reactions.single.count, 2);
    expect(folded.clientId, 'client-1');
    expect(folded.attachmentGroupId, 'g');
  });
}

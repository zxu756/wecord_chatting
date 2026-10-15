import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  test('page reactions are attached to their messages', () {
    final rows = withConversationReactions(
      [
        {
          'id': 'message-1',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-2',
          'type': 'text',
          'body': 'Hello',
          'created_at': '2026-05-18T04:30:00.000Z',
        },
        {
          'id': 'message-2',
          'conversation_id': 'conversation-1',
          'sender_id': 'user-1',
          'type': 'text',
          'body': 'No reactions',
          'created_at': '2026-05-18T04:31:00.000Z',
        },
      ],
      [
        {
          'message_id': 'message-1',
          'reactions': [
            {'emoji': '👍', 'count': 2, 'reacted_by_me': true},
            {
              'emoji': 'custom:00000000-0000-4000-8000-000000000001',
              'count': 1,
              'reacted_by_me': false,
              'custom_name': 'party_parrot',
            },
          ],
        },
        // A message outside the page is ignored.
        {
          'message_id': 'message-9',
          'reactions': [
            {'emoji': '🎉', 'count': 1, 'reacted_by_me': false},
          ],
        },
      ],
    );

    expect(rows, hasLength(2));
    final messages = rows.map(ChatMessage.fromJson).toList();
    expect(messages.first.reactions.map((reaction) => reaction.emoji), [
      '👍',
      'custom:00000000-0000-4000-8000-000000000001',
    ]);
    expect(messages.first.reactions.first.count, 2);
    expect(messages.first.reactions.first.reactedByMe, isTrue);
    expect(messages.last.reactions, isEmpty);
    expect(rows.last['reactions'], isEmpty);
  });
}

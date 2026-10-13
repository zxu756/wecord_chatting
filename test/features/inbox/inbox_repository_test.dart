import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/inbox/inbox_repository.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  test('parses inbox rows', () {
    final item = InboxItem.fromJson({
      'message_id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u2',
      'sender_display_name': 'Bart',
      'sender_avatar_url': 'profile-avatars/u2/a.png',
      'webhook_name': null,
      'body': '@everyone hi',
      'type': 'text',
      'created_at': '2026-10-14T10:00:00Z',
      'reason': 'mention_all',
      'is_unread': true,
    });
    expect(item.senderName, 'Bart');
    expect(item.senderAvatarUrl, 'profile-avatars/u2/a.png');
    expect(item.type, MessageType.text);
    expect(item.reason, InboxReason.mentionAll);
    expect(item.isUnread, isTrue);
    expect(item.createdAt, DateTime.utc(2026, 10, 14, 10));
  });

  test('webhook messages show the webhook, not its owner', () {
    final item = InboxItem.fromJson({
      'message_id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u2',
      'sender_display_name': 'Bart',
      'sender_avatar_url': 'profile-avatars/u2/a.png',
      'webhook_name': 'Deploy bot',
      'body': 'Shipped',
      'type': 'text',
      'created_at': '2026-10-14T10:00:00Z',
      'reason': 'reply',
      'is_unread': false,
    });
    expect(item.senderName, 'Deploy bot');
    expect(item.senderAvatarUrl, isNull);
    expect(item.reason, InboxReason.reply);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/friend_request.dart';
import 'package:wecord/shared/models/friendship.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  test('Profile parses Supabase rows and copies values', () {
    final profile = Profile.fromJson({
      'id': 'user-1',
      'username': 'alex',
      'display_name': 'Alex',
      'avatar_url': null,
      'bio': 'hello',
      'created_at': '2026-05-18T00:00:00.000Z',
      'updated_at': '2026-05-18T00:01:00.000Z',
    });

    expect(profile.id, 'user-1');
    expect(profile.username, 'alex');
    expect(profile.displayName, 'Alex');
    expect(profile.avatarUrl, isNull);
    expect(profile.bio, 'hello');
    expect(profile.createdAt, DateTime.utc(2026, 5, 18));
    expect(profile.updatedAt, DateTime.utc(2026, 5, 18, 0, 1));
    expect(profile.copyWith(displayName: 'A').displayName, 'A');
  });

  test('Profile copyWith can clear avatarUrl', () {
    final profile = Profile.fromJson({
      'id': 'user-1',
      'username': 'alex',
      'display_name': 'Alex',
      'avatar_url': 'https://example.test/avatar.png',
      'bio': 'hello',
      'created_at': '2026-05-18T00:00:00.000Z',
      'updated_at': '2026-05-18T00:01:00.000Z',
    });

    expect(profile.copyWith(avatarUrl: null).avatarUrl, isNull);
  });

  test('Profile toJson includes writable Supabase keys', () {
    final profile = Profile.fromJson({
      'id': 'user-1',
      'username': 'alex',
      'display_name': 'Alex',
      'avatar_url': 'https://example.test/avatar.png',
      'bio': 'hello',
      'created_at': '2026-05-18T00:00:00.000Z',
      'updated_at': '2026-05-18T00:01:00.000Z',
    });

    expect(profile.toJson(), {
      'id': 'user-1',
      'username': 'alex',
      'display_name': 'Alex',
      'avatar_url': 'https://example.test/avatar.png',
      'bio': 'hello',
    });
  });

  test('FriendRequest parses Supabase rows and copies values', () {
    final request = FriendRequest.fromJson({
      'id': 'request-1',
      'requester_id': 'user-1',
      'receiver_id': 'user-2',
      'status': 'pending',
      'created_at': '2026-05-18T00:00:00.000Z',
      'updated_at': '2026-05-18T00:01:00.000Z',
    });

    expect(request.id, 'request-1');
    expect(request.requesterId, 'user-1');
    expect(request.receiverId, 'user-2');
    expect(request.status, FriendRequestStatus.pending);
    expect(request.createdAt, DateTime.utc(2026, 5, 18));
    expect(request.updatedAt, DateTime.utc(2026, 5, 18, 0, 1));
    expect(
      request.copyWith(status: FriendRequestStatus.accepted).status,
      FriendRequestStatus.accepted,
    );
  });

  test('FriendRequest toJson includes writable Supabase keys', () {
    final request = FriendRequest.fromJson({
      'id': 'request-1',
      'requester_id': 'user-1',
      'receiver_id': 'user-2',
      'status': 'accepted',
      'created_at': '2026-05-18T00:00:00.000Z',
      'updated_at': '2026-05-18T00:01:00.000Z',
    });

    expect(request.toJson(), {
      'requester_id': 'user-1',
      'receiver_id': 'user-2',
      'status': 'accepted',
    });
  });

  test('Friendship parses Supabase rows and copies values', () {
    final friendship = Friendship.fromJson({
      'id': 'friendship-1',
      'user_low_id': 'user-1',
      'user_high_id': 'user-2',
      'user_low_remark': 'Al',
      'user_high_remark': null,
      'created_at': '2026-05-18T00:00:00.000Z',
    });

    expect(friendship.id, 'friendship-1');
    expect(friendship.userLowId, 'user-1');
    expect(friendship.userHighId, 'user-2');
    expect(friendship.userLowRemark, 'Al');
    expect(friendship.userHighRemark, isNull);
    expect(friendship.createdAt, DateTime.utc(2026, 5, 18));
    expect(friendship.copyWith(userHighRemark: 'Lex').userHighRemark, 'Lex');
  });

  test('Friendship toJson includes writable Supabase keys', () {
    final friendship = Friendship.fromJson({
      'id': 'friendship-1',
      'user_low_id': 'user-1',
      'user_high_id': 'user-2',
      'user_low_remark': 'Al',
      'user_high_remark': null,
      'created_at': '2026-05-18T00:00:00.000Z',
    });

    expect(friendship.toJson(), {
      'user_low_id': 'user-1',
      'user_high_id': 'user-2',
      'user_low_remark': 'Al',
      'user_high_remark': null,
    });
  });

  test('Friendship copyWith can clear remarks', () {
    final friendship = Friendship.fromJson({
      'id': 'friendship-1',
      'user_low_id': 'user-1',
      'user_high_id': 'user-2',
      'user_low_remark': 'Al',
      'user_high_remark': 'Lex',
      'created_at': '2026-05-18T00:00:00.000Z',
    });

    final updated = friendship.copyWith(
      userLowRemark: null,
      userHighRemark: null,
    );

    expect(updated.userLowRemark, isNull);
    expect(updated.userHighRemark, isNull);
  });

  test(
    'Conversation computes unread count from row value and copies values',
    () {
      final conversation = ConversationSummary.fromJson({
        'id': 'conversation-1',
        'type': 'direct',
        'title': null,
        'avatar_url': null,
        'last_message_body': 'Hi',
        'last_message_at': '2026-05-18T00:00:00.000Z',
        'unread_count': 2,
      });

      expect(conversation.id, 'conversation-1');
      expect(conversation.type, ConversationType.direct);
      expect(conversation.title, isNull);
      expect(conversation.avatarUrl, isNull);
      expect(conversation.lastMessageBody, 'Hi');
      expect(conversation.lastMessageAt, DateTime.utc(2026, 5, 18));
      expect(conversation.unreadCount, 2);
      expect(conversation.copyWith(unreadCount: 0).unreadCount, 0);
    },
  );

  test('Conversation copyWith can clear nullable fields', () {
    final conversation = ConversationSummary.fromJson({
      'id': 'conversation-1',
      'type': 'direct',
      'title': 'Alex',
      'avatar_url': 'https://example.test/conversation.png',
      'last_message_body': 'Hi',
      'last_message_at': '2026-05-18T00:00:00.000Z',
      'unread_count': 2,
    });

    final updated = conversation.copyWith(
      title: null,
      avatarUrl: null,
      lastMessageBody: null,
      lastMessageAt: null,
    );

    expect(updated.title, isNull);
    expect(updated.avatarUrl, isNull);
    expect(updated.lastMessageBody, isNull);
    expect(updated.lastMessageAt, isNull);
  });

  test('Conversation toJson includes writable Supabase keys', () {
    final conversation = ConversationSummary.fromJson({
      'id': 'conversation-1',
      'type': 'group',
      'title': 'Project',
      'avatar_url': 'https://example.test/conversation.png',
      'last_message_body': 'Hi',
      'last_message_at': '2026-05-18T00:00:00.000Z',
      'unread_count': 2,
    });

    expect(conversation.toJson(), {
      'type': 'group',
      'title': 'Project',
      'avatar_url': 'https://example.test/conversation.png',
    });
  });

  test('Message parses text rows and copies values', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'text',
      'body': 'Hello',
      'attachment': null,
      'reply_to_message_id': null,
      'created_at': '2026-05-18T00:00:00.000Z',
      'edited_at': null,
      'recalled_at': null,
    });

    expect(message.id, 'message-1');
    expect(message.conversationId, 'conversation-1');
    expect(message.senderId, 'user-1');
    expect(message.type, MessageType.text);
    expect(message.body, 'Hello');
    expect(message.attachment, isNull);
    expect(message.replyToMessageId, isNull);
    expect(message.createdAt, DateTime.utc(2026, 5, 18));
    expect(message.editedAt, isNull);
    expect(message.recalledAt, isNull);
    expect(message.copyWith(body: 'Updated').body, 'Updated');
  });

  test('Message copyWith can clear nullable fields', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'text',
      'body': 'Hello',
      'attachment': {'path': 'file.png'},
      'reply_to_message_id': 'message-0',
      'created_at': '2026-05-18T00:00:00.000Z',
      'edited_at': '2026-05-18T00:02:00.000Z',
      'recalled_at': '2026-05-18T00:03:00.000Z',
    });

    final updated = message.copyWith(
      attachment: null,
      replyToMessageId: null,
      editedAt: null,
      recalledAt: null,
    );

    expect(updated.attachment, isNull);
    expect(updated.replyToMessageId, isNull);
    expect(updated.editedAt, isNull);
    expect(updated.recalledAt, isNull);
  });

  test('ImageAttachment serializes storage metadata for image messages', () {
    const attachment = ImageAttachment(
      bucket: 'chat-images',
      path: 'conversation-1/message-1/photo.jpg',
      mimeType: 'image/jpeg',
      size: 2048,
      width: 640,
      height: 480,
    );

    expect(attachment.toJson(), {
      'kind': 'image',
      'bucket': 'chat-images',
      'path': 'conversation-1/message-1/photo.jpg',
      'mime_type': 'image/jpeg',
      'size': 2048,
      'width': 640,
      'height': 480,
    });

    expect(ImageAttachment.fromJson(attachment.toJson()).path, attachment.path);
  });

  test('ImageAttachment can be read from an image message', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'image',
      'body': '',
      'attachment': {
        'kind': 'image',
        'bucket': 'chat-images',
        'path': 'conversation-1/message-1/photo.jpg',
        'mime_type': 'image/jpeg',
        'size': 2048,
        'width': null,
        'height': null,
      },
      'reply_to_message_id': null,
      'created_at': '2026-05-18T00:00:00.000Z',
      'edited_at': null,
      'recalled_at': null,
    });

    expect(message.imageAttachment?.bucket, 'chat-images');
    expect(message.imageAttachment?.path, 'conversation-1/message-1/photo.jpg');
    expect(message.imageAttachment?.mimeType, 'image/jpeg');
    expect(message.imageAttachment?.size, 2048);
  });

  test('Message toJson includes writable Supabase keys', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'image',
      'body': 'Hello',
      'attachment': {'path': 'file.png'},
      'reply_to_message_id': 'message-0',
      'created_at': '2026-05-18T00:00:00.000Z',
      'edited_at': null,
      'recalled_at': null,
    });

    expect(message.toJson(), {
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'image',
      'body': 'Hello',
      'attachment': {'path': 'file.png'},
      'reply_to_message_id': 'message-0',
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/friend_request.dart';
import 'package:wecord/shared/models/friendship.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/profile.dart';
import 'package:wecord/shared/models/profile_relationship.dart';

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

  test('Profile prefers alias when present', () {
    final profile = Profile.fromJson({
      'id': 'user-2',
      'username': 'ada',
      'display_name': 'Ada Lovelace',
      'alias': 'Ada L.',
      'avatar_url': null,
      'bio': '',
      'created_at': '2026-05-18T00:00:00Z',
      'updated_at': '2026-05-18T00:00:00Z',
    });

    expect(profile.alias, 'Ada L.');
    expect(profile.displayLabel, 'Ada L.');
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

  test('ProfileRelationship parses profile summary status fields', () {
    final summary = ProfileSummary.fromJson({
      'id': 'user-2',
      'username': 'ada',
      'display_name': 'Ada',
      'alias': 'A',
      'avatar_url': null,
      'bio': 'math',
      'relationship_status': 'friend',
      'incoming_request_id': null,
      'outgoing_request_id': null,
      'is_blocked_by_me': false,
      'has_blocked_me': false,
    });

    expect(summary.profile.displayLabel, 'A');
    expect(summary.relationshipStatus, ProfileRelationshipStatus.friend);
    expect(summary.canStartChat, isTrue);
    expect(summary.canSendFriendRequest, isFalse);
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
        'last_message_sender_id': 'user-2',
        'last_message_at': '2026-05-18T00:00:00.000Z',
        'unread_count': 2,
      });

      expect(conversation.id, 'conversation-1');
      expect(conversation.type, ConversationType.direct);
      expect(conversation.title, isNull);
      expect(conversation.avatarUrl, isNull);
      expect(conversation.lastMessageBody, 'Hi');
      expect(conversation.lastMessageSenderId, 'user-2');
      expect(conversation.lastMessageAt, DateTime.utc(2026, 5, 18));
      expect(conversation.unreadCount, 2);
      expect(conversation.copyWith(unreadCount: 0).unreadCount, 0);
    },
  );

  test('Conversation maps group announcement metadata', () {
    final conversation = ConversationSummary.fromJson({
      'id': 'conversation-1',
      'type': 'group',
      'title': 'Launch Crew',
      'avatar_url': null,
      'last_message_body': null,
      'last_message_sender_id': null,
      'last_message_at': null,
      'last_message_type': null,
      'unread_count': 0,
      'announcement': 'Deploy at noon',
      'announcement_updated_at': '2026-05-19T09:30:00.000Z',
      'announcement_updated_by': 'user-1',
    });

    expect(conversation.announcement, 'Deploy at noon');
    expect(
      conversation.announcementUpdatedAt,
      DateTime.utc(2026, 5, 19, 9, 30),
    );
    expect(conversation.announcementUpdatedBy, 'user-1');
  });

  test('Conversation copyWith can clear nullable fields', () {
    final conversation = ConversationSummary.fromJson({
      'id': 'conversation-1',
      'type': 'direct',
      'title': 'Alex',
      'avatar_url': 'https://example.test/conversation.png',
      'last_message_body': 'Hi',
      'last_message_sender_id': 'user-2',
      'last_message_at': '2026-05-18T00:00:00.000Z',
      'unread_count': 2,
    });

    final updated = conversation.copyWith(
      title: null,
      avatarUrl: null,
      lastMessageBody: null,
      lastMessageSenderId: null,
      lastMessageAt: null,
    );

    expect(updated.title, isNull);
    expect(updated.avatarUrl, isNull);
    expect(updated.lastMessageBody, isNull);
    expect(updated.lastMessageSenderId, isNull);
    expect(updated.lastMessageAt, isNull);
  });

  test('Conversation parses latest message sender id', () {
    final conversation = ConversationSummary.fromJson({
      'id': 'conversation-1',
      'type': 'direct',
      'title': 'Ada',
      'avatar_url': null,
      'last_message_body': 'Hi',
      'last_message_sender_id': 'user-2',
      'last_message_at': '2026-05-18T00:00:00.000Z',
      'unread_count': 1,
    });

    expect(conversation.lastMessageSenderId, 'user-2');
    expect(
      conversation.copyWith(lastMessageSenderId: null).lastMessageSenderId,
      isNull,
    );
  });

  test('Conversation toJson includes writable Supabase keys', () {
    final conversation = ConversationSummary.fromJson({
      'id': 'conversation-1',
      'type': 'group',
      'title': 'Project',
      'avatar_url': 'https://example.test/conversation.png',
      'last_message_body': 'Hi',
      'last_message_sender_id': 'user-2',
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

  test('ChatMessage parses reply preview and edited timestamp', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'text',
      'body': 'Reply body',
      'attachment': null,
      'reply_to_message_id': 'message-0',
      'reply_preview': {
        'message_id': 'message-0',
        'sender_name': 'Ada',
        'body': 'Original body',
        'type': 'text',
      },
      'created_at': '2026-05-18T00:00:00Z',
      'edited_at': '2026-05-18T00:01:00Z',
      'recalled_at': null,
    });

    expect(message.replyToMessageId, 'message-0');
    expect(message.replyPreview?.senderName, 'Ada');
    expect(message.replyPreview?.body, 'Original body');
    expect(message.editedAt, DateTime.utc(2026, 5, 18, 0, 1));
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

  test('ChatMessage parses voice attachment and forward preview', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'voice',
      'body': '',
      'attachment': {
        'kind': 'voice',
        'bucket': 'voice-messages',
        'path': 'conversation-1/message-1.m4a',
        'mime_type': 'audio/mp4',
        'size': 1024,
        'duration_ms': 4200,
      },
      'forwarded_from': {
        'message_id': 'message-0',
        'sender_name': 'Ada',
        'type': 'text',
        'body': 'Original',
      },
      'created_at': '2026-05-18T00:00:00Z',
    });

    expect(message.voiceAttachment?.durationMs, 4200);
    expect(message.forwardPreview?.senderName, 'Ada');
  });

  test('VoiceAttachment serializes and validates voice metadata', () {
    const attachment = VoiceAttachment(
      bucket: 'voice-messages',
      path: 'conversation-1/message-1.m4a',
      mimeType: 'audio/mp4',
      size: 1024,
      durationMs: 4200,
    );

    expect(attachment.toJson(), {
      'kind': 'voice',
      'bucket': 'voice-messages',
      'path': 'conversation-1/message-1.m4a',
      'mime_type': 'audio/mp4',
      'size': 1024,
      'duration_ms': 4200,
    });
    expect(VoiceAttachment.fromJson(attachment.toJson()).path, attachment.path);
    expect(
      () => VoiceAttachment.fromJson({...attachment.toJson(), 'kind': 'image'}),
      throwsArgumentError,
    );
  });

  test('ChatMessage ignores malformed mention metadata', () {
    final message = ChatMessage.fromJson({
      'id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'type': 'text',
      'body': 'Hello @ada',
      'attachment': null,
      'reply_to_message_id': null,
      'created_at': '2026-05-18T00:00:00.000Z',
      'edited_at': null,
      'recalled_at': null,
      'mentions': [
        {'user_id': 'user-2', 'display_name': 'Ada', 'start': 6, 'end': 10},
        {'display_name': 'Missing id', 'start': 0, 'end': 1},
        {'user_id': 42, 'display_name': 'Bad id', 'start': 0, 'end': 1},
      ],
    });

    expect(message.mentions, hasLength(1));
    expect(message.mentions.single.userId, 'user-2');
    expect(message.mentions.single.displayName, 'Ada');
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
      'reply_preview': null,
    });
  });

  test('Circle summary and detail parse RPC payloads', () {
    final summary = CircleSummary.fromJson({
      'id': 'circle-1',
      'name': 'Close Friends',
      'avatar_url': 'circle-avatars/circle-1/a.jpg',
      'member_count': 4,
      'channel_count': 2,
      'latest_activity_at': '2026-05-19T01:02:03Z',
      'current_user_role': 'owner',
    });

    expect(summary.name, 'Close Friends');
    expect(summary.memberCount, 4);
    expect(summary.currentUserRole, 'owner');

    final detail = CircleDetail.fromJson({
      'circle': summary.toJson(),
      'members': [
        {
          'role': 'owner',
          'profile': {
            'id': 'user-1',
            'username': 'xu',
            'display_name': 'Xu',
            'bio': '',
            'created_at': '2026-05-19T01:00:00Z',
            'updated_at': '2026-05-19T01:00:00Z',
          },
        },
      ],
      'channels': [
        {
          'id': 'channel-1',
          'circle_id': 'circle-1',
          'conversation_id': 'conversation-1',
          'name': 'general',
          'position': 0,
        },
      ],
      'posts': const [],
    });

    expect(detail.circle.id, 'circle-1');
    expect(detail.members.single.profile.username, 'xu');
    expect(detail.channels.single.name, 'general');
    expect(detail.canManageCircle, isTrue);
  });

  test('CirclePost parses nested author comments and image metadata', () {
    final post = CirclePost.fromJson({
      'id': 'post-1',
      'circle_id': 'circle-1',
      'author_id': 'user-1',
      'body': 'Photo drop',
      'attachment': {
        'kind': 'image',
        'bucket': 'circle-media',
        'path': 'circle-1/post-1/photo.jpg',
        'mime_type': 'image/jpeg',
        'size': 1234,
        'width': 800,
        'height': 600,
      },
      'created_at': '2026-05-19T01:02:03Z',
      'updated_at': '2026-05-19T01:03:03Z',
      'deleted_at': null,
      'author': {
        'id': 'user-1',
        'username': 'xu',
        'display_name': 'Xu',
        'bio': '',
        'created_at': '2026-05-19T01:00:00Z',
        'updated_at': '2026-05-19T01:00:00Z',
      },
      'comments': [
        {
          'id': 'comment-1',
          'post_id': 'post-1',
          'author_id': 'user-2',
          'body': 'Nice',
          'created_at': '2026-05-19T01:04:03Z',
          'updated_at': '2026-05-19T01:04:03Z',
          'deleted_at': null,
          'author': {
            'id': 'user-2',
            'username': 'ada',
            'display_name': 'Ada',
            'bio': '',
            'created_at': '2026-05-19T01:00:00Z',
            'updated_at': '2026-05-19T01:00:00Z',
          },
        },
      ],
      'is_own_post': true,
      'can_manage_post': true,
      'like_count': 3,
      'comment_count': 1,
      'liked_by_current_user': true,
    });

    expect(post.author.username, 'xu');
    expect(post.comments.single.author.username, 'ada');
    expect(post.imageAttachment?.path, 'circle-1/post-1/photo.jpg');
    expect(post.isOwnPost, isTrue);
    expect(post.canManagePost, isTrue);
    expect(post.likeCount, 3);
    expect(post.commentCount, 1);
    expect(post.likedByCurrentUser, isTrue);
  });

  test('DiscoveryResult parses known result types', () {
    final rows = {
      'contact': DiscoveryResultType.contact,
      'group': DiscoveryResultType.group,
      'circle': DiscoveryResultType.circle,
      'circle_channel': DiscoveryResultType.circleChannel,
      'message': DiscoveryResultType.message,
    };

    for (final entry in rows.entries) {
      final result = DiscoveryResult.fromJson({
        'result_type': entry.key,
        'id': 'result-1',
        'title': 'Result',
        'subtitle': 'Subtitle',
        'rank': 0.8,
      });

      expect(result.type, entry.value);
      expect(result.rank, 0.8);
    }
  });

  test('DiscoveryResult falls back to message only for conversation rows', () {
    final result = DiscoveryResult.fromJson({
      'result_type': 'legacy_message',
      'id': 'message-1',
      'title': 'Hello',
      'subtitle': 'Xu',
      'conversation_id': 'conversation-1',
      'rank': 0.8,
    });

    expect(result.type, DiscoveryResultType.message);
    expect(result.conversationId, 'conversation-1');
    expect(
      () => DiscoveryResult.fromJson({
        'result_type': 'mystery',
        'id': 'result-1',
        'title': 'Mystery',
      }),
      throwsArgumentError,
    );
  });

  test('Discovery and media models parse RPC rows', () {
    final result = DiscoveryResult.fromJson({
      'result_type': 'circle_channel',
      'id': 'channel-1',
      'title': 'general',
      'subtitle': 'Close Friends',
      'conversation_id': 'conversation-1',
      'circle_id': 'circle-1',
      'channel_id': 'channel-1',
      'rank': 0.8,
    });

    expect(result.type, DiscoveryResultType.circleChannel);
    expect(result.conversationId, 'conversation-1');

    final media = ConversationMediaItem.fromJson({
      'message_id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'sender_name': 'Xu',
      'type': 'image',
      'body': '',
      'attachment': {
        'kind': 'image',
        'bucket': 'chat-media',
        'path': 'conversation-1/image.jpg',
        'mime_type': 'image/jpeg',
        'size': 123,
      },
      'created_at': '2026-05-19T01:02:03Z',
    });

    expect(media.type, MessageType.image);
    expect(media.imageAttachment?.path, 'conversation-1/image.jpg');
  });

  test('ConversationMediaItem exposes voice attachments', () {
    final media = ConversationMediaItem.fromJson({
      'message_id': 'message-1',
      'conversation_id': 'conversation-1',
      'sender_id': 'user-1',
      'sender_name': 'Xu',
      'type': 'voice',
      'body': '',
      'attachment': {
        'kind': 'voice',
        'bucket': 'chat-media',
        'path': 'conversation-1/voice.m4a',
        'mime_type': 'audio/mp4',
        'size': 456,
        'duration_ms': 3200,
      },
      'created_at': '2026-05-19T01:02:03Z',
    });

    expect(media.type, MessageType.voice);
    expect(media.voiceAttachment?.durationMs, 3200);
    expect(media.imageAttachment, isNull);
  });
}

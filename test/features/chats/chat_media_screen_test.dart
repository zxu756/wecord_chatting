import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/chats/chat_media_screen.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  testWidgets('chat media screen groups images voice and files', (
    tester,
  ) async {
    final repository = FakeChatsRepository()
      ..media = [
        _media(type: MessageType.image, body: ''),
        _media(type: MessageType.voice, body: ''),
        _media(type: MessageType.file, body: 'report.pdf'),
      ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [chatsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: ChatMediaScreen(conversationId: 'conversation-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Media'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.textContaining('Ada'), findsOneWidget);

    await tester.tap(find.text('Voice'));
    await tester.pumpAndSettle();
    expect(find.text('[Voice]'), findsOneWidget);

    await tester.tap(find.text('Files'));
    await tester.pumpAndSettle();
    expect(find.text('report.pdf'), findsOneWidget);
  });
}

ConversationMediaItem _media({
  required MessageType type,
  required String body,
}) {
  return ConversationMediaItem(
    messageId: 'message-${type.toJson()}',
    conversationId: 'conversation-1',
    senderId: 'user-2',
    senderName: 'Ada',
    type: type,
    body: body,
    attachment: switch (type) {
      MessageType.image => const {
        'kind': 'image',
        'bucket': 'chat-media',
        'path': 'conversation-1/image.png',
        'mime_type': 'image/png',
        'size': 12,
      },
      MessageType.voice => const {
        'kind': 'voice',
        'bucket': 'chat-media',
        'path': 'conversation-1/voice.m4a',
        'mime_type': 'audio/mp4',
        'size': 12,
        'duration_ms': 1500,
      },
      MessageType.file => null,
      MessageType.text => null,
    },
    createdAt: DateTime.utc(2026, 5, 19, 10),
  );
}

class FakeChatsRepository implements ChatsRepository {
  var media = <ConversationMediaItem>[];

  @override
  Future<List<ConversationMediaItem>> listConversationMedia(
    String conversationId,
  ) async {
    return media;
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) async {
    return 'https://example.com/${attachment.path}';
  }

  @override
  Future<List<ConversationSummary>> listConversations() async => const [];

  @override
  Future<ConversationSummary?> getConversationSummary(
    String conversationId,
  ) async => null;

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) async =>
      const [];

  @override
  Future<List<ConversationReadMarker>> listReadMarkers(
    String conversationId,
  ) async => const [];

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) async =>
      'conversation';

  @override
  Future<GroupDetail> getGroupDetail(String conversationId) async {
    return GroupDetail(
      conversationId: conversationId,
      title: conversationId,
      members: const [],
    );
  }

  @override
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
  }) async {}

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  }) async {}

  @override
  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) async {}

  @override
  Future<void> forwardMessage({
    required String sourceMessageId,
    required String targetConversationId,
  }) async {}

  @override
  Future<List<MessageSearchResult>> searchMessages(String query) async =>
      const [];

  @override
  Future<List<DiscoveryResult>> searchDiscovery(String query) async => const [];

  @override
  Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
  }) async => 'group';

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
  Future<String> uploadGroupAvatar({
    required String conversationId,
    required ChatImageUpload image,
  }) async => 'avatar';

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
  Future<String> createVoiceUrl(VoiceAttachment attachment) async {
    return 'https://example.com/${attachment.path}';
  }

  @override
  Future<void> recallMessage({required String messageId}) async {}

  @override
  Future<void> editMessage({
    required String messageId,
    required String body,
  }) async {}

  @override
  Future<void> markConversationRead(String conversationId) async {}

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
  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  ) => conversations;

  @override
  List<ChatMessage> searchThreadMessages(
    List<ChatMessage> messages,
    String query,
  ) => messages;

  @override
  Stream<void> conversationChanges() => const Stream.empty();

  @override
  Stream<void> messageChanges(String conversationId) => const Stream.empty();

  @override
  Stream<void> threadChanges(String conversationId) => const Stream.empty();

  @override
  Stream<ConversationActivity> conversationActivity(String conversationId) {
    return const Stream.empty();
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) async {}
}

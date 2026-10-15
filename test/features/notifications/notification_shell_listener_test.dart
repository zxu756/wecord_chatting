import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/notifications/notification_shell_listener.dart';
import 'package:wecord/features/presence/presence_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/conversation_thread.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/link_preview.dart';
import 'package:wecord/shared/models/media_attachment.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/pinned_message.dart';
import 'package:wecord/shared/models/presence_status.dart';
import 'package:wecord/shared/models/profile.dart';

void main() {
  testWidgets('starts the notification coordinator', (tester) async {
    final coordinator = _RecordingNotificationCoordinator();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationCoordinatorProvider.overrideWithValue(coordinator),
          localNotificationServiceProvider.overrideWithValue(
            FakeLocalNotificationService(),
          ),
        ],
        child: const MaterialApp(
          home: NotificationShellListener(child: Text('child')),
        ),
      ),
    );
    await tester.pump();

    expect(coordinator.startCount, 1);
  });

  testWidgets('stays on app-wide presence while mounted', (tester) async {
    final presence = _FakePresenceRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationCoordinatorProvider.overrideWithValue(
            _RecordingNotificationCoordinator(),
          ),
          localNotificationServiceProvider.overrideWithValue(
            FakeLocalNotificationService(),
          ),
          authStateProvider.overrideWith(
            (ref) => Stream.value(const AuthUser(id: 'user-1')),
          ),
          presenceRepositoryProvider.overrideWithValue(presence),
        ],
        child: const MaterialApp(
          home: NotificationShellListener(child: Text('child')),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(presence.listening, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();

    expect(presence.listening, isFalse);
  });

  testWidgets('disposes the notification coordinator', (tester) async {
    final coordinator = _RecordingNotificationCoordinator();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          notificationCoordinatorProvider.overrideWithValue(coordinator),
          localNotificationServiceProvider.overrideWithValue(
            FakeLocalNotificationService(),
          ),
        ],
        child: const MaterialApp(
          home: NotificationShellListener(child: Text('child')),
        ),
      ),
    );
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    expect(coordinator.disposeCount, 1);
  });
}

class _FakePresenceRepository implements PresenceRepository {
  var listening = false;

  @override
  Future<PresenceSettings> loadSettings() async => const PresenceSettings();

  @override
  Future<void> setStatus(PresenceStatus status) async {}

  @override
  Future<void> setShowOnlineStatus(bool show) async {}

  @override
  Stream<Map<String, PresenceStatus>> statuses(
    ValueListenable<PresenceStatus?> ownStatus,
  ) {
    late StreamController<Map<String, PresenceStatus>> controller;
    controller = StreamController<Map<String, PresenceStatus>>(
      onListen: () {
        listening = true;
        controller.add({'user-1': PresenceStatus.online});
      },
      onCancel: () => listening = false,
    );
    return controller.stream;
  }
}

class _RecordingNotificationCoordinator extends NotificationCoordinator {
  _RecordingNotificationCoordinator()
    : super(
        authRepository: _FakeAuthRepository(),
        chatsRepository: _FakeChatsRepository(),
        preferencesRepository: NotificationPreferencesRepository.withStore(
          InMemoryNotificationPreferencesStore(),
        ),
        notificationService: FakeLocalNotificationService(),
        activeConversationId: () => null,
      );

  int startCount = 0;
  int disposeCount = 0;

  @override
  Future<void> start() async {
    startCount += 1;
  }

  @override
  Future<void> dispose() async {
    disposeCount += 1;
  }
}

class _FakeAuthRepository implements AuthRepository {
  @override
  AuthUser? get currentUser => const AuthUser(id: 'user-1');

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

  @override
  Future<void> ensureCurrentUserProfile() async {}

  @override
  Future<void> signIn(String email, String password) async {}

  @override
  Future<void> signOut() async {}

  @override
  Future<void> signUp(
    String email,
    String password,
    String username,
    String displayName,
  ) async {}
}

class _FakeChatsRepository implements ChatsRepository {
  @override
  Future<void> createPoll({
    required String conversationId,
    required String question,
    required List<String> options,
    required bool multi,
    int? durationHours,
  }) async {}

  @override
  Future<void> votePoll({
    required String messageId,
    required List<String> optionIds,
  }) async {}

  @override
  Future<void> endPoll({required String messageId}) async {}

  @override
  Future<bool> canModeratePolls(String conversationId) async => false;

  @override
  Future<List<Profile>> listPollVoters({
    required String messageId,
    required String optionId,
  }) async => const [];

  @override
  Future<List<ConversationSummary>> listConversations() async => [];

  @override
  Stream<void> conversationChanges() => const Stream<void>.empty();

  @override
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> memberIds,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<ConversationActivity> conversationActivity(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<String> createGroupConversation({
    required String title,
    required List<String> memberIds,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> createImageUrl(ImageAttachment attachment) {
    throw UnimplementedError();
  }

  @override
  Future<String> createVoiceUrl(VoiceAttachment attachment) {
    throw UnimplementedError();
  }

  @override
  Future<void> forwardMessage({
    required String sourceMessageId,
    required String targetConversationId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> editMessage({required String messageId, required String body}) {
    throw UnimplementedError();
  }

  @override
  Future<void> toggleMessageReaction({
    required String messageId,
    required String emoji,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<Profile>> listMessageReactors({
    required String messageId,
    required String emoji,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canPinMessages(String conversationId) async => false;

  @override
  Future<void> pinMessage({required String messageId}) async {}

  @override
  Future<void> unpinMessage({required String messageId}) async {}

  @override
  Future<List<PinnedMessage>> listPinnedMessages(String conversationId) async {
    return const [];
  }

  @override
  Future<ConversationSummary?> getConversationSummary(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<GroupDetail> getGroupDetail(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<String> getOrCreateDirectConversation(String otherUserId) {
    throw UnimplementedError();
  }

  @override
  Future<List<ChatMessage>> listMessages(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<List<ConversationReadMarker>> listReadMarkers(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<LinkPreview?> getLinkPreview(String url) async => null;

  @override
  Future<void> setMessageSuppressEmbeds({
    required String messageId,
    required bool suppress,
  }) async {}

  @override
  Future<ConversationThread> createThread({
    required String parentConversationId,
    String? rootMessageId,
    String? title,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<List<ConversationThread>> listThreads(
    String parentConversationId,
  ) async => const [];

  @override
  Future<ConversationThread> setThreadArchived({
    required String threadId,
    required bool archived,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<bool> canManageThread(String threadId) async => false;

  @override
  Future<void> markConversationRead(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<void> markConversationUnread(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<void> setConversationPinned({
    required String conversationId,
    required bool pinned,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> setConversationMuted({
    required String conversationId,
    required bool muted,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> hideConversation(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Stream<void> messageChanges(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendSticker({
    required String conversationId,
    required String stickerId,
  }) async {}

  @override
  Future<bool> canModerateMessages(String conversationId) async => false;

  @override
  Future<void> recallMessage({required String messageId}) {
    throw UnimplementedError();
  }

  @override
  Future<void> renameGroupConversation({
    required String conversationId,
    required String title,
  }) {
    throw UnimplementedError();
  }

  @override
  List<ConversationSummary> searchConversations(
    List<ConversationSummary> conversations,
    String query,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<List<MessageSearchResult>> searchMessages(String query) {
    throw UnimplementedError();
  }

  @override
  Future<List<DiscoveryResult>> searchDiscovery(String query) {
    throw UnimplementedError();
  }

  @override
  Future<List<ConversationMediaItem>> listConversationMedia(
    String conversationId,
  ) {
    throw UnimplementedError();
  }

  @override
  List<ChatMessage> searchThreadMessages(
    List<ChatMessage> messages,
    String query,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendImageMessage({
    required String conversationId,
    required ChatImageUpload image,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> sendVoiceMessage({
    required String conversationId,
    required Uint8List bytes,
    required String mimeType,
    required int durationMs,
  }) {
    throw UnimplementedError();
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
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
    List<MessageMention> mentions = const <MessageMention>[],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> uploadGroupAvatar({
    required String conversationId,
    required ChatImageUpload image,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> updateGroupProfile({
    required String conversationId,
    required String title,
    required String? avatarUrl,
    required String announcement,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> leaveGroupConversation(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeGroupMember({
    required String conversationId,
    required String memberId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> setTyping({
    required String conversationId,
    required bool isTyping,
  }) {
    throw UnimplementedError();
  }

  @override
  Stream<void> threadChanges(String conversationId) {
    throw UnimplementedError();
  }
}

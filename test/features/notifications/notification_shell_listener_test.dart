import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/notifications/notification_shell_listener.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';

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
  Future<void> editMessage({required String messageId, required String body}) {
    throw UnimplementedError();
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
  Future<void> markConversationRead(String conversationId) {
    throw UnimplementedError();
  }

  @override
  Stream<void> messageChanges(String conversationId) {
    throw UnimplementedError();
  }

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
  List<ChatMessage> searchMessages(List<ChatMessage> messages, String query) {
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
  Future<void> sendTextMessage({
    required String conversationId,
    required String body,
    String? replyToMessageId,
    ReplyPreview? replyPreview,
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

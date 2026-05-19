import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/features/shell/wecord_shell.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/discovery.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  testWidgets('switches between primary tabs', (tester) async {
    var selectedIndex = 0;
    final selectedIndexes = <int>[];

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) {
          return MaterialApp(
            home: ProviderScope(
              overrides: [
                notificationCoordinatorProvider.overrideWithValue(
                  _NoopNotificationCoordinator(),
                ),
                localNotificationServiceProvider.overrideWithValue(
                  FakeLocalNotificationService(),
                ),
              ],
              child: WeCordShell(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) {
                  selectedIndexes.add(index);
                  setState(() {
                    selectedIndex = index;
                  });
                },
                child: const Text('Current screen'),
              ),
            ),
          );
        },
      ),
    );

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Circles'), findsOneWidget);
    expect(find.text('Me'), findsOneWidget);

    await tester.tap(find.text('Contacts'));
    await tester.pump();

    await tester.tap(find.text('Circles'));
    await tester.pump();

    await tester.tap(find.text('Me'));
    await tester.pump();

    expect(selectedIndexes, [1, 2, 3]);
  });
}

class _NoopNotificationCoordinator extends NotificationCoordinator {
  _NoopNotificationCoordinator()
    : super(
        authRepository: _FakeAuthRepository(),
        chatsRepository: _FakeChatsRepository(),
        preferencesRepository: NotificationPreferencesRepository.withStore(
          InMemoryNotificationPreferencesStore(),
        ),
        notificationService: FakeLocalNotificationService(),
        activeConversationId: () => null,
      );

  @override
  Future<void> start() async {}
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

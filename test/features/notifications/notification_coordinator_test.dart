import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/auth/auth_repository.dart';
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/notifications/local_notification_service.dart';
import 'package:wecord/features/notifications/notification_coordinator.dart';
import 'package:wecord/features/notifications/notification_preferences_repository.dart';
import 'package:wecord/shared/models/chat_status.dart';
import 'package:wecord/shared/models/conversation.dart';
import 'package:wecord/shared/models/group.dart';
import 'package:wecord/shared/models/message.dart';

void main() {
  test('does not notify on initial snapshot', () async {
    final harness = NotificationCoordinatorHarness();
    harness.seed([harness.summary(id: 'c1', unreadCount: 1)]);

    await harness.start();

    expect(harness.notifications, isEmpty);
  });

  test(
    'notifies when a conversation gains a newer unread incoming message',
    () async {
      final harness = NotificationCoordinatorHarness();
      harness.seed([harness.summary(id: 'c1')]);
      await harness.start();

      await harness.emit([
        harness.summary(id: 'c1', unreadCount: 1, body: 'hello'),
      ]);

      expect(harness.notifications.single.body, 'hello');
      expect(harness.notifications.single.title, 'Ada');
      expect(harness.notifications.single.payload, 'c1');
    },
  );

  test('does not notify for the active conversation', () async {
    final harness = NotificationCoordinatorHarness(activeConversationId: 'c1');
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);

    expect(harness.notifications, isEmpty);
  });

  test('does not notify when notifications are disabled', () async {
    final harness = NotificationCoordinatorHarness(notificationsEnabled: false);
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);

    expect(harness.notifications, isEmpty);
  });

  test('uses New message when previews are disabled', () async {
    final harness = NotificationCoordinatorHarness(previewsEnabled: false);
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    await harness.emit([
      harness.summary(id: 'c1', unreadCount: 1, body: 'secret'),
    ]);

    expect(harness.notifications.single.body, 'New message');
  });

  test('uses New message when preview body is empty', () async {
    final harness = NotificationCoordinatorHarness();
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    await harness.emit([harness.summary(id: 'c1', unreadCount: 1, body: '  ')]);

    expect(harness.notifications.single.body, 'New message');
  });

  test('uses fallback title when conversation title is empty', () async {
    final harness = NotificationCoordinatorHarness();
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    await harness.emit([harness.summary(id: 'c1', title: ' ', unreadCount: 1)]);

    expect(harness.notifications.single.title, 'Conversation');
  });

  test('does not notify for messages from the current user', () async {
    final harness = NotificationCoordinatorHarness(currentUserId: 'me');
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    await harness.emit([
      harness.summary(id: 'c1', unreadCount: 1, lastMessageSenderId: 'me'),
    ]);

    expect(harness.notifications, isEmpty);
  });

  test('does not notify when signed out', () async {
    final harness = NotificationCoordinatorHarness(currentUserId: null);
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);

    expect(harness.notifications, isEmpty);
  });

  test('does not notify when latest message timestamp is missing', () async {
    final harness = NotificationCoordinatorHarness();
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    await harness.emit([
      harness.summary(id: 'c1', unreadCount: 1, hasLastMessageAt: false),
    ]);

    expect(harness.notifications, isEmpty);
  });

  test('does not notify when latest message is not newer', () async {
    final harness = NotificationCoordinatorHarness();
    final timestamp = DateTime.utc(2026, 5, 18, 1);
    harness.seed([harness.summary(id: 'c1', lastMessageAt: timestamp)]);
    await harness.start();

    await harness.emit([
      harness.summary(id: 'c1', unreadCount: 1, lastMessageAt: timestamp),
    ]);

    expect(harness.notifications, isEmpty);
  });

  test('catches repository reload errors and keeps listening', () async {
    final harness = NotificationCoordinatorHarness();
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();

    harness.failNextList();
    await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);
    await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);

    expect(harness.notifications.single.payload, 'c1');
  });

  test(
    'initial baseline failure does not notify on the recovery snapshot',
    () async {
      final harness = NotificationCoordinatorHarness();
      final firstIncomingAt = DateTime.utc(2026, 5, 18, 12);
      final secondIncomingAt = DateTime.utc(2026, 5, 18, 13);
      harness.seed([harness.summary(id: 'c1')]);
      harness.failNextList();
      await harness.start();

      await harness.emit([
        harness.summary(
          id: 'c1',
          unreadCount: 1,
          lastMessageAt: firstIncomingAt,
        ),
      ]);

      expect(harness.notifications, isEmpty);

      await harness.emit([
        harness.summary(
          id: 'c1',
          unreadCount: 1,
          lastMessageAt: secondIncomingAt,
        ),
      ]);

      expect(harness.notifications.single.payload, 'c1');
    },
  );

  test('processes changes that arrive while baseline is loading', () async {
    final harness = NotificationCoordinatorHarness();
    final baselineAt = DateTime.utc(2026, 5, 18, 12);
    final incomingAt = DateTime.utc(2026, 5, 18, 13);
    final baseline = harness.pauseNextList();

    final start = harness.start();
    await Future<void>.delayed(Duration.zero);

    await harness.emit([
      harness.summary(
        id: 'c1',
        unreadCount: 1,
        body: 'after baseline',
        lastMessageAt: incomingAt,
      ),
    ]);
    baseline.complete([harness.summary(id: 'c1', lastMessageAt: baselineAt)]);

    await start;
    await harness.pump();

    expect(harness.notifications.single.body, 'after baseline');
  });

  test(
    'processes baseline-loading changes when baseline includes the change',
    () async {
      final harness = NotificationCoordinatorHarness();
      final incomingAt = DateTime.utc(2026, 5, 18, 13);
      final baseline = harness.pauseNextList();

      final start = harness.start();
      await Future<void>.delayed(Duration.zero);

      final incomingSummary = harness.summary(
        id: 'c1',
        unreadCount: 1,
        body: 'included in baseline',
        lastMessageAt: incomingAt,
      );
      await harness.emit([incomingSummary]);
      baseline.complete([incomingSummary]);

      await start;
      await harness.pump();

      expect(harness.notifications.single.body, 'included in baseline');
    },
  );

  test(
    'baseline-loading changes do not notify older unread conversations',
    () async {
      final harness = NotificationCoordinatorHarness();
      final oldUnreadAt = DateTime.utc(2026, 5, 18, 12);
      final incomingAt = DateTime.utc(2026, 5, 18, 13);
      final baseline = harness.pauseNextList();

      final start = harness.start();
      await Future<void>.delayed(Duration.zero);

      final oldUnread = harness.summary(
        id: 'old',
        unreadCount: 1,
        body: 'already unread',
        lastMessageAt: oldUnreadAt,
      );
      final incoming = harness.summary(
        id: 'new',
        unreadCount: 1,
        body: 'new incoming',
        lastMessageAt: incomingAt,
      );
      await harness.emit([oldUnread, incoming]);
      baseline.complete([oldUnread, incoming]);

      await start;
      await harness.pump();

      expect(harness.notifications.single.body, 'new incoming');
    },
  );

  test(
    'serializes reloads when changes arrive faster than list calls',
    () async {
      final harness = NotificationCoordinatorHarness();
      final firstAt = DateTime.utc(2026, 5, 18, 13);
      final secondAt = DateTime.utc(2026, 5, 18, 14);
      harness.seed([harness.summary(id: 'c1')]);
      await harness.start();

      final firstReload = harness.pauseNextList();
      await harness.emit([
        harness.summary(
          id: 'c1',
          unreadCount: 1,
          body: 'first',
          lastMessageAt: firstAt,
        ),
      ]);
      await harness.emit([
        harness.summary(
          id: 'c1',
          unreadCount: 1,
          body: 'second',
          lastMessageAt: secondAt,
        ),
      ]);

      expect(harness.maxConcurrentListCalls, 1);

      firstReload.complete([
        harness.summary(
          id: 'c1',
          unreadCount: 1,
          body: 'first',
          lastMessageAt: firstAt,
        ),
      ]);
      await harness.pump();

      expect(harness.maxConcurrentListCalls, 1);
      expect(harness.notifications.map((notification) => notification.body), [
        'first',
        'second',
      ]);
    },
  );

  test('catches notification service errors and keeps listening', () async {
    final harness = NotificationCoordinatorHarness();
    harness.seed([harness.summary(id: 'c1'), harness.summary(id: 'c2')]);
    await harness.start();

    harness.failNextNotification();
    await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);
    await harness.emit([harness.summary(id: 'c2', unreadCount: 1)]);

    expect(harness.notifications.single.payload, 'c2');
  });

  test('stops listening after dispose', () async {
    final harness = NotificationCoordinatorHarness();
    harness.seed([harness.summary(id: 'c1')]);
    await harness.start();
    await harness.stop();

    await harness.emit([harness.summary(id: 'c1', unreadCount: 1)]);

    expect(harness.notifications, isEmpty);
  });
}

class NotificationCoordinatorHarness {
  NotificationCoordinatorHarness({
    String? activeConversationId,
    bool notificationsEnabled = true,
    bool previewsEnabled = true,
    String? currentUserId = 'current-user',
  }) : _activeConversationId = activeConversationId,
       _authRepository = _FakeAuthRepository(currentUserId),
       _chatsRepository = _FakeChatsRepository(),
       _notificationService = _ThrowingFakeLocalNotificationService(),
       _preferencesRepository = NotificationPreferencesRepository.withStore(
         InMemoryNotificationPreferencesStore(
           NotificationPreferences(
             enabled: notificationsEnabled,
             showPreviews: previewsEnabled,
           ),
         ),
       ) {
    coordinator = NotificationCoordinator(
      authRepository: _authRepository,
      chatsRepository: _chatsRepository,
      preferencesRepository: _preferencesRepository,
      notificationService: _notificationService,
      activeConversationId: () => _activeConversationId,
      now: () => DateTime.utc(2026, 5, 18, 12, 30),
    );
  }

  final String? _activeConversationId;
  final _FakeAuthRepository _authRepository;
  final _FakeChatsRepository _chatsRepository;
  final _ThrowingFakeLocalNotificationService _notificationService;
  final NotificationPreferencesRepository _preferencesRepository;
  late final NotificationCoordinator coordinator;

  List<ShownMessageNotification> get notifications =>
      _notificationService.shownNotifications;

  ConversationSummary summary({
    required String id,
    String? title = 'Ada',
    int unreadCount = 0,
    String? body = 'Hi',
    String? lastMessageSenderId = 'sender-1',
    DateTime? lastMessageAt,
    bool hasLastMessageAt = true,
  }) {
    return ConversationSummary(
      id: id,
      type: ConversationType.direct,
      title: title,
      lastMessageBody: body,
      lastMessageSenderId: lastMessageSenderId,
      lastMessageAt: hasLastMessageAt
          ? lastMessageAt ?? DateTime.utc(2026, 5, 18, 12, unreadCount + 1)
          : null,
      unreadCount: unreadCount,
    );
  }

  void seed(List<ConversationSummary> conversations) {
    _chatsRepository.conversations = conversations;
  }

  Future<void> start() => coordinator.start();

  Future<void> stop() => coordinator.dispose();

  Completer<List<ConversationSummary>> pauseNextList() {
    return _chatsRepository.pauseNextList();
  }

  int get maxConcurrentListCalls => _chatsRepository.maxConcurrentListCalls;

  void failNextList() {
    _chatsRepository.failNextList = true;
  }

  void failNextNotification() {
    _notificationService.failNextShow = true;
  }

  Future<void> emit(List<ConversationSummary> conversations) async {
    _chatsRepository.conversations = conversations;
    _chatsRepository.emitChange();
    await pump();
  }

  Future<void> pump() async {
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }
}

class _ThrowingFakeLocalNotificationService
    extends FakeLocalNotificationService {
  bool failNextShow = false;

  @override
  Future<void> showMessageNotification({
    required String conversationId,
    required String title,
    required String body,
  }) {
    if (failNextShow) {
      failNextShow = false;
      throw StateError('notification failed');
    }
    return super.showMessageNotification(
      conversationId: conversationId,
      title: title,
      body: body,
    );
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository(String? currentUserId)
    : currentUser = currentUserId == null ? null : AuthUser(id: currentUserId);

  @override
  final AuthUser? currentUser;

  @override
  Future<void> ensureCurrentUserProfile() async {}

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(currentUser);

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
  final _changes = StreamController<void>.broadcast();
  final _pendingListResponses = <Completer<List<ConversationSummary>>>[];
  List<ConversationSummary> conversations = [];
  bool failNextList = false;
  int _activeListCalls = 0;
  int maxConcurrentListCalls = 0;

  void emitChange() {
    _changes.add(null);
  }

  Completer<List<ConversationSummary>> pauseNextList() {
    final completer = Completer<List<ConversationSummary>>();
    _pendingListResponses.add(completer);
    return completer;
  }

  @override
  Future<List<ConversationSummary>> listConversations() async {
    _activeListCalls += 1;
    if (_activeListCalls > maxConcurrentListCalls) {
      maxConcurrentListCalls = _activeListCalls;
    }
    try {
      if (failNextList) {
        failNextList = false;
        throw StateError('reload failed');
      }
      if (_pendingListResponses.isNotEmpty) {
        return await _pendingListResponses.removeAt(0).future;
      }
      return conversations;
    } finally {
      _activeListCalls -= 1;
    }
  }

  @override
  Stream<void> conversationChanges() => _changes.stream;

  @override
  Future<void> addGroupMembers({
    required String conversationId,
    required List<String> memberIds,
  }) {
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
  Stream<ConversationActivity> conversationActivity(String conversationId) {
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

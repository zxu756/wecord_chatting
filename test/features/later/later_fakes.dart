import 'package:wecord/features/later/reminders_repository.dart';
import 'package:wecord/features/later/saved_messages_repository.dart';
import 'package:wecord/features/later/scheduled_messages_repository.dart';
import 'package:wecord/features/push/push_gateway.dart';
import 'package:wecord/features/push/push_repository.dart';

/// An in-memory scheduled message queue.
class FakeScheduledMessagesRepository implements ScheduledMessagesRepository {
  FakeScheduledMessagesRepository([List<ScheduledMessage> initial = const []])
    : messages = [...initial];

  final List<ScheduledMessage> messages;
  final created = <({String conversationId, String body, DateTime sendAt})>[];
  final sentNow = <String>[];
  final deleted = <String>[];
  var _next = 0;

  /// Fails every write with this.
  Object? failWith;

  @override
  Future<List<ScheduledMessage>> list(String conversationId) async => [
    for (final message in messages)
      if (message.conversationId == conversationId) message,
  ]..sort((a, b) => a.sendAt.compareTo(b.sendAt));

  @override
  Future<ScheduledMessage> create({
    required String conversationId,
    required String body,
    required DateTime sendAt,
    List<Map<String, dynamic>> mentions = const [],
  }) async {
    if (failWith case final error?) {
      throw error;
    }
    created.add((conversationId: conversationId, body: body, sendAt: sendAt));
    final message = ScheduledMessage(
      id: 'scheduled-${_next++}',
      conversationId: conversationId,
      body: body,
      sendAt: sendAt.toUtc(),
      mentions: mentions,
    );
    messages.add(message);
    return message;
  }

  @override
  Future<ScheduledMessage> update(
    String id, {
    required String body,
    required DateTime sendAt,
    required List<Map<String, dynamic>> mentions,
  }) async {
    if (failWith case final error?) {
      throw error;
    }
    final index = messages.indexWhere((message) => message.id == id);
    final updated = ScheduledMessage(
      id: id,
      conversationId: messages[index].conversationId,
      body: body,
      sendAt: sendAt.toUtc(),
      mentions: mentions,
    );
    messages[index] = updated;
    return updated;
  }

  @override
  Future<void> delete(String id) async {
    if (failWith case final error?) {
      throw error;
    }
    deleted.add(id);
    messages.removeWhere((message) => message.id == id);
  }

  @override
  Future<String> sendNow(String id) async {
    if (failWith case final error?) {
      throw error;
    }
    sentNow.add(id);
    messages.removeWhere((message) => message.id == id);
    return 'sent-$id';
  }
}

/// A push repository that remembers the messages it was asked to push.
class RecordingPushRepository implements PushRepository {
  final notified = <String>[];

  @override
  Future<String> vapidPublicKey() async =>
      throw const PushNotConfiguredException();

  @override
  Future<void> register(
    PushSubscriptionInfo subscription, {
    String language = 'en',
    String? userAgent,
  }) async {}

  @override
  Future<void> unregister(String endpoint) async {}

  @override
  Future<void> notifySent(String messageId) async => notified.add(messageId);

  @override
  Future<void> notifyCall(String callId) async {}
}

/// In-memory reminders.
class FakeRemindersRepository implements RemindersRepository {
  FakeRemindersRepository([List<MessageReminder> initial = const []])
    : reminders = [...initial];

  final List<MessageReminder> reminders;
  final setCalls = <({String messageId, DateTime at})>[];
  final dismissed = <String>[];

  /// What the next claim returns (and then clears).
  var due = <LocalReminder>[];
  var claims = 0;
  var failClaims = false;
  Object? failSetWith;

  @override
  Future<List<MessageReminder>> list() async => [...reminders];

  @override
  Future<void> set(String messageId, DateTime remindAt) async {
    if (failSetWith case final error?) {
      throw error;
    }
    setCalls.add((messageId: messageId, at: remindAt));
  }

  @override
  Future<void> dismiss(String id) async {
    dismissed.add(id);
    reminders.removeWhere((reminder) => reminder.id == id);
  }

  @override
  Future<List<LocalReminder>> claimDue() async {
    claims++;
    if (failClaims) {
      throw StateError('offline');
    }
    final result = due;
    due = [];
    return result;
  }
}

/// In-memory saved messages.
class FakeSavedMessagesRepository implements SavedMessagesRepository {
  FakeSavedMessagesRepository([List<SavedMessage> initial = const []])
    : entries = [...initial];

  final List<SavedMessage> entries;
  final saved = <String>[];
  final removed = <String>[];
  final doneCalls = <({String id, bool done})>[];
  var failWrites = false;

  @override
  Future<List<SavedMessage>> list() async => [...entries];

  @override
  Future<void> save(String messageId) async {
    if (failWrites) {
      throw StateError('offline');
    }
    saved.add(messageId);
    entries.insert(
      0,
      SavedMessage(
        id: 'saved-${entries.length}',
        messageId: messageId,
        conversationId: 'conversation-1',
        savedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> remove(String id) async {
    if (failWrites) {
      throw StateError('offline');
    }
    removed.add(id);
    entries.removeWhere((entry) => entry.id == id);
  }

  @override
  Future<void> setDone(String id, {required bool done}) async {
    if (failWrites) {
      throw StateError('offline');
    }
    doneCalls.add((id: id, done: done));
    final index = entries.indexWhere((entry) => entry.id == id);
    final entry = entries[index];
    entries[index] = SavedMessage(
      id: entry.id,
      messageId: entry.messageId,
      conversationId: entry.conversationId,
      savedAt: entry.savedAt,
      doneAt: done ? DateTime.now() : null,
      senderId: entry.senderId,
      senderName: entry.senderName,
      senderAvatarUrl: entry.senderAvatarUrl,
      body: entry.body,
      type: entry.type,
      messageCreatedAt: entry.messageCreatedAt,
      available: entry.available,
    );
  }
}

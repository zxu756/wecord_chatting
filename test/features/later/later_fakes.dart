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
    String? userAgent,
  }) async {}

  @override
  Future<void> unregister(String endpoint) async {}

  @override
  Future<void> notifySent(String messageId) async => notified.add(messageId);

  @override
  Future<void> notifyCall(String callId) async {}
}

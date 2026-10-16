import 'dart:async';
import 'dart:math' as math;

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/offline/outbox.dart';
import 'package:wecord/shared/models/message.dart';

/// A server that stores one message per client id, like
/// messages_sender_client_id_key, and can fail before or after storing.
class _FakeServer {
  final stored = <String, String>{};
  final calls = <String>[];

  /// Failures to throw on the next sends, in order.
  final failures = <Object>[];

  /// Store the message, then fail as if the answer was lost.
  var loseNextAnswer = false;

  Future<String?> send(OutboxEntry entry) async {
    calls.add(entry.clientId);
    if (failures.isNotEmpty) {
      throw failures.removeAt(0);
    }
    final id = stored.putIfAbsent(entry.clientId, () => 'm${stored.length}');
    if (loseNextAnswer) {
      loseNextAnswer = false;
      throw http.ClientException('Connection reset');
    }
    return id;
  }
}

OutboxEntry _entry(String clientId, {int minute = 0}) {
  return OutboxEntry(
    clientId: clientId,
    conversationId: 'conversation-1',
    body: 'Hello $clientId',
    createdAt: DateTime.utc(2026, 1, 1, 0, minute),
  );
}

void main() {
  late _FakeServer server;
  late List<List<OutboxEntry>> changes;
  late List<(String, String?)> sent;

  OutboxEngine engine({int maxAttempts = 4, DateTime Function()? clock}) {
    return OutboxEngine(
      send: server.send,
      maxAttempts: maxAttempts,
      baseDelay: const Duration(seconds: 1),
      maxDelay: const Duration(seconds: 8),
      clock: clock,
      random: math.Random(1),
      onChanged: changes.add,
      onSent: (entry, messageId) async => sent.add((entry.clientId, messageId)),
    );
  }

  setUp(() {
    server = _FakeServer();
    changes = [];
    sent = [];
  });

  test('a message shows as sending until it is stored', () async {
    final outbox = engine();
    outbox.enqueue(_entry('a'));
    expect(outbox.entries.single.state, OutboxState.sending);

    final result = await outbox.sendNow('a');

    expect(result, isA<OutboxSent>());
    expect((result as OutboxSent).messageId, 'm0');
    expect(sent, [('a', 'm0')]);
    expect(outbox.entries, isEmpty);
    outbox.dispose();
  });

  test('network failures retry with growing waits, then give up', () {
    fakeAsync((async) {
      final outbox = engine(
        maxAttempts: 4,
        clock: () => async.getClock(DateTime.utc(2026)).now(),
      );
      server.failures.addAll([
        http.ClientException('offline'),
        TimeoutException('slow'),
        const PostgrestException(message: 'Bad gateway', code: 'PGRST000'),
        http.ClientException('still offline'),
      ]);
      outbox.enqueue(_entry('a'));
      OutboxAttempt? first;
      unawaited(outbox.sendNow('a').then((result) => first = result));
      async.flushMicrotasks();
      expect(first, isA<OutboxWillRetry>());
      expect((first! as OutboxWillRetry).gaveUp, isFalse);
      expect(outbox.entries.single.attempts, 1);
      expect(outbox.entries.single.state, OutboxState.sending);

      // About a second (with jitter) before the second try.
      async.elapse(const Duration(milliseconds: 700));
      expect(server.calls, hasLength(1));
      async.elapse(const Duration(milliseconds: 600));
      expect(server.calls, hasLength(2));
      // Then about two seconds, then four.
      async.elapse(const Duration(milliseconds: 2500));
      expect(server.calls, hasLength(3));
      async.elapse(const Duration(seconds: 5));
      expect(server.calls, hasLength(4));

      final entry = outbox.entries.single;
      expect(entry.state, OutboxState.failed);
      expect(entry.attempts, 4);
      // Failed messages wait for the reader.
      async.elapse(const Duration(minutes: 5));
      expect(server.calls, hasLength(4));
      outbox.dispose();
    });
  });

  test('backoff doubles up to the cap, with jitter', () {
    final outbox = engine();
    for (final (attempts, seconds) in [
      (1, 1),
      (2, 2),
      (3, 4),
      (4, 8),
      (9, 8),
    ]) {
      final wait = outbox.backoffFor(attempts).inMilliseconds;
      expect(wait, greaterThanOrEqualTo(seconds * 800));
      expect(wait, lessThanOrEqualTo(seconds * 1200));
    }
    outbox.dispose();
  });

  test('tapping a failed message tries it again from scratch', () async {
    final outbox = engine(maxAttempts: 1);
    server.failures.add(http.ClientException('offline'));
    outbox.enqueue(_entry('a'));
    final first = await outbox.sendNow('a');
    expect((first as OutboxWillRetry).gaveUp, isTrue);
    expect(outbox.entries.single.state, OutboxState.failed);

    final retried = await outbox.retry('a');

    expect(retried, isA<OutboxSent>());
    expect(outbox.entries, isEmpty);
    expect(server.calls, ['a', 'a']);
    outbox.dispose();
  });

  test('a send whose answer was lost is stored once', () async {
    final outbox = engine();
    server.loseNextAnswer = true;
    outbox.enqueue(_entry('a'));

    final first = await outbox.sendNow('a');
    expect(first, isA<OutboxWillRetry>());
    expect(server.stored, {'a': 'm0'});

    final second = await outbox.sendNow('a');
    expect(second, isA<OutboxSent>());
    expect((second as OutboxSent).messageId, 'm0');
    expect(server.stored, hasLength(1));
    expect(sent, [('a', 'm0')]);
    outbox.dispose();
  });

  test('refusals are not retried', () async {
    final outbox = engine();
    server.failures.add(const SlowmodeException(30));
    outbox.enqueue(_entry('a'));

    final result = await outbox.sendNow('a');

    expect(result, isA<OutboxRefused>());
    expect((result as OutboxRefused).error, isA<SlowmodeException>());
    expect(outbox.entries.single.state, OutboxState.failed);
    outbox.dispose();
  });

  test('offline, nothing is sent; back online, the queue drains in order', () {
    fakeAsync((async) {
      final outbox = engine();
      outbox.setOnline(false);
      outbox.enqueue(_entry('a', minute: 1));
      outbox.enqueue(_entry('b', minute: 2));
      OutboxAttempt? attempt;
      unawaited(outbox.sendNow('a').then((result) => attempt = result));
      async.flushMicrotasks();
      expect(attempt, isA<OutboxWillRetry>());
      async.elapse(const Duration(minutes: 1));
      expect(server.calls, isEmpty);
      expect(
        outbox.entries.map((entry) => entry.state),
        everyElement(OutboxState.sending),
      );

      outbox.setOnline(true);
      async.elapse(Duration.zero);
      async.flushMicrotasks();

      expect(server.calls, ['a', 'b']);
      expect(outbox.entries, isEmpty);
      outbox.dispose();
    });
  });

  test('coming back online skips the backoff wait', () {
    fakeAsync((async) {
      final outbox = engine(
        clock: () => async.getClock(DateTime.utc(2026)).now(),
      );
      server.failures.addAll([
        http.ClientException('offline'),
        http.ClientException('offline'),
      ]);
      outbox.enqueue(_entry('a'));
      unawaited(outbox.sendNow('a'));
      async.flushMicrotasks();
      async.elapse(const Duration(milliseconds: 1300));
      expect(server.calls, hasLength(2));

      outbox.setOnline(false);
      outbox.setOnline(true);
      async.elapse(Duration.zero);
      async.flushMicrotasks();

      expect(server.calls, hasLength(3));
      expect(outbox.entries, isEmpty);
      outbox.dispose();
    });
  });

  test('entries survive a restart as JSON', () {
    final entry = OutboxEntry(
      clientId: 'a',
      conversationId: 'conversation-1',
      body: 'Hi @Grace',
      createdAt: DateTime.utc(2026, 1, 1, 12),
      replyToMessageId: 'message-1',
      replyPreview: const ReplyPreview(
        messageId: 'message-1',
        senderName: 'Grace',
        body: 'Hello',
        type: MessageType.text,
      ),
      mentions: const [
        MessageMention(
          userId: 'user-2',
          displayName: 'Grace',
          start: 3,
          end: 9,
        ),
      ],
      attempts: 3,
      state: OutboxState.failed,
    );

    final restored = OutboxEntry.fromJson(entry.toJson());

    expect(restored.clientId, 'a');
    expect(restored.body, 'Hi @Grace');
    expect(restored.createdAt, entry.createdAt);
    expect(restored.replyPreview?.messageId, 'message-1');
    expect(restored.mentions.single.userId, 'user-2');
    expect(restored.attempts, 3);
    expect(restored.state, OutboxState.failed);

    final outbox = engine();
    outbox.restore([restored, entry]);
    expect(outbox.entries, hasLength(1), reason: 'restored once');
    outbox.dispose();
  });

  test('pending messages show as the current user\'s', () {
    final message = _entry('a').toPendingMessage('user-1');
    expect(message.id, pendingMessageIdFor('a'));
    expect(isPendingMessageId(message.id), isTrue);
    expect(isPendingMessageId('message-1'), isFalse);
    expect(message.senderId, 'user-1');
    expect(message.clientId, 'a');
  });

  test('refusals and network failures are told apart', () {
    expect(isSendRefusal(const SlowmodeException(3)), isTrue);
    expect(isSendRefusal(const AutoModBlockedException()), isTrue);
    expect(
      isSendRefusal(const PostgrestException(message: 'no', code: '42501')),
      isTrue,
    );
    expect(
      isSendRefusal(const PostgrestException(message: 'down', code: '08006')),
      isFalse,
    );
    expect(
      isSendRefusal(const PostgrestException(message: 'gw', code: 'PGRST000')),
      isFalse,
    );
    expect(isSendRefusal(http.ClientException('offline')), isFalse);
    expect(isSendRefusal(TimeoutException('slow')), isFalse);
  });

  test('client ids are random version 4 UUIDs', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final ids = {for (var i = 0; i < 200; i++) newClientId()};
    expect(ids, hasLength(200));
    for (final id in ids) {
      expect(id, matches(pattern));
    }
  });
}

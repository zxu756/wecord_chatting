import 'dart:async';
import 'dart:math' as math;

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/chats/chats_repository.dart';
import 'package:wecord/features/chats/media_send/media_upload.dart';
import 'package:wecord/features/chats/media_send/outbox_media.dart';
import 'package:wecord/features/chats/offline/outbox_failure.dart';
import 'package:wecord/shared/models/message.dart';

enum OutboxState {
  /// Waiting to be sent, or being sent: shown as "Sending…".
  sending,

  /// Gave up after [OutboxEngine.maxAttempts] tries, or the server refused
  /// it: shown as "Failed — tap to retry".
  failed,
}

/// A message the current user wrote (text), or an attachment they sent
/// ([media]: one picture, video or file, perhaps of an album), that the
/// server has not stored yet.
@immutable
class OutboxEntry {
  const OutboxEntry({
    required this.clientId,
    required this.conversationId,
    required this.body,
    required this.createdAt,
    this.replyToMessageId,
    this.replyPreview,
    this.mentions = const [],
    this.media,
    this.attempts = 0,
    this.state = OutboxState.sending,
    this.nextAttemptAt,
    this.error,
    this.failedAt,
  });

  factory OutboxEntry.fromJson(Map<String, dynamic> json) {
    final reply = json['reply_preview'];
    final mentions = json['mentions'];
    final media = json['media'];
    return OutboxEntry(
      clientId: json['client_id'] as String,
      conversationId: json['conversation_id'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      replyToMessageId: json['reply_to_message_id'] as String?,
      replyPreview: reply is Map
          ? ReplyPreview.fromJson(Map<String, dynamic>.from(reply))
          : null,
      mentions: [
        if (mentions is List)
          for (final mention in mentions)
            if (mention is Map)
              MessageMention.fromJson(Map<String, dynamic>.from(mention)),
      ],
      media: media is Map
          ? OutboxMedia.fromJson(Map<String, dynamic>.from(media))
          : null,
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
      state: json['state'] == 'failed'
          ? OutboxState.failed
          : OutboxState.sending,
      error: outboxFailureFromJson(json['failure']),
      failedAt: switch (json['failed_at']) {
        final String at => DateTime.tryParse(at),
        _ => null,
      },
    );
  }

  final String clientId;
  final String conversationId;
  final String body;
  final DateTime createdAt;
  final String? replyToMessageId;
  final ReplyPreview? replyPreview;
  final List<MessageMention> mentions;

  /// The attachment to upload and send ([body] is then its caption).
  final OutboxMedia? media;

  /// Sends tried so far.
  final int attempts;
  final OutboxState state;

  /// When the next try is due, while [state] is sending and a try failed.
  final DateTime? nextAttemptAt;

  /// Why the last try failed. Refusals the reader should read again are
  /// kept with the entry across restarts (see [outboxFailureToJson]).
  final Object? error;

  /// When the last try failed: a slowmode wait counts down from here.
  final DateTime? failedAt;

  /// The id the message shows under until the server stores it.
  String get pendingMessageId => pendingMessageIdFor(clientId);

  /// The path its attachment shows under until it is uploaded; no such
  /// object exists, the bubble draws the kept file instead.
  String get pendingAttachmentPath => 'pending/$clientId';

  OutboxEntry copyWith({
    int? attempts,
    OutboxState? state,
    Object? nextAttemptAt = _keep,
    Object? error = _keep,
    Object? failedAt = _keep,
  }) {
    return OutboxEntry(
      clientId: clientId,
      conversationId: conversationId,
      body: body,
      createdAt: createdAt,
      replyToMessageId: replyToMessageId,
      replyPreview: replyPreview,
      mentions: mentions,
      media: media,
      attempts: attempts ?? this.attempts,
      state: state ?? this.state,
      nextAttemptAt: identical(nextAttemptAt, _keep)
          ? this.nextAttemptAt
          : nextAttemptAt as DateTime?,
      error: identical(error, _keep) ? this.error : error,
      failedAt: identical(failedAt, _keep)
          ? this.failedAt
          : failedAt as DateTime?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      'conversation_id': conversationId,
      'body': body,
      'created_at': createdAt.toUtc().toIso8601String(),
      'reply_to_message_id': replyToMessageId,
      'reply_preview': replyPreview?.toJson(),
      'mentions': [for (final mention in mentions) mention.toJson()],
      if (media != null) 'media': media!.toJson(),
      'attempts': attempts,
      'state': state == OutboxState.failed ? 'failed' : 'sending',
      if (state == OutboxState.failed &&
          outboxFailureToJson(error) != null) ...{
        'failure': outboxFailureToJson(error),
        'failed_at': failedAt?.toUtc().toIso8601String(),
      },
    };
  }

  /// How the message shows in the chat while it waits.
  ChatMessage toPendingMessage(String senderId) {
    return ChatMessage(
      id: pendingMessageId,
      conversationId: conversationId,
      senderId: senderId,
      type: media?.messageType ?? MessageType.text,
      body: body,
      attachment: media?.attachmentJson(pendingAttachmentPath),
      attachmentGroupId: media?.groupId,
      createdAt: createdAt,
      replyToMessageId: replyToMessageId,
      replyPreview: replyPreview,
      mentions: mentions,
      clientId: clientId,
    );
  }
}

const _keep = Object();

const _pendingPrefix = 'outbox:';

String pendingMessageIdFor(String clientId) => '$_pendingPrefix$clientId';

/// Whether [messageId] is a message still in the outbox.
bool isPendingMessageId(String messageId) =>
    messageId.startsWith(_pendingPrefix);

/// The outcome of one try.
sealed class OutboxAttempt {
  const OutboxAttempt();
}

/// Stored on the server as [messageId].
class OutboxSent extends OutboxAttempt {
  const OutboxSent(this.messageId);

  final String? messageId;
}

/// Failed for a reason that may pass (the network); tried again later, or
/// marked failed after the last try.
class OutboxWillRetry extends OutboxAttempt {
  const OutboxWillRetry(this.error, {required this.gaveUp});

  final Object error;

  /// That was the last try: the entry is now failed.
  final bool gaveUp;
}

/// The server refused the message (slowmode, AutoMod, permissions):
/// sending it again would not help.
class OutboxRefused extends OutboxAttempt {
  const OutboxRefused(this.error);

  final Object error;
}

/// Whether [error] is the server saying no rather than the network
/// failing. PostgREST errors carry a SQLSTATE (five characters) for
/// refusals, and PGRST codes or none when the request did not get through.
bool isSendRefusal(Object error) {
  if (error is SlowmodeException ||
      error is SendRefusedException ||
      error is ChatFileTooLargeException ||
      error is UploadCancelledException ||
      (error is UploadException && error.isRefusal) ||
      error is StateError ||
      error is ArgumentError) {
    return true;
  }
  if (error is PostgrestException) {
    final code = error.code;
    if (code == null || code.startsWith('PGRST')) {
      return false;
    }
    // 08xxx: connection exceptions; 53xxx/57xxx: the server is busy or
    // shutting down; 40001/40P01: retryable conflicts.
    if (code.length == 5 &&
        (code.startsWith('08') ||
            code.startsWith('53') ||
            code.startsWith('57') ||
            code == '40001' ||
            code == '40P01')) {
      return false;
    }
    return code.length == 5;
  }
  return false;
}

/// Sends queued messages in order, one at a time, retrying failures with
/// exponential backoff (with jitter) while online, up to [maxAttempts]
/// tries. Pure logic; [OutboxNotifier] wires it to the app.
class OutboxEngine {
  OutboxEngine({
    required this._send,
    this.maxAttempts = 5,
    this.baseDelay = const Duration(seconds: 2),
    this.maxDelay = const Duration(minutes: 1),
    DateTime Function()? clock,
    math.Random? random,
    this.onChanged,
    this.onSent,
  }) : _clock = clock ?? (() => clockNow()),
       _random = random ?? math.Random();

  final Future<String?> Function(OutboxEntry entry) _send;
  final int maxAttempts;
  final Duration baseDelay;
  final Duration maxDelay;
  final DateTime Function() _clock;
  final math.Random _random;

  /// Called with the entries after every change.
  final void Function(List<OutboxEntry> entries)? onChanged;

  /// Called when an entry was stored, before it leaves the outbox.
  final Future<void> Function(OutboxEntry entry, String? messageId)? onSent;

  var _entries = <OutboxEntry>[];
  var _online = true;
  var _disposed = false;
  Timer? _timer;

  /// Entries in flight, by client id: an entry is never sent twice at
  /// once.
  final _inFlight = <String, Future<OutboxAttempt>>{};

  List<OutboxEntry> get entries => List.unmodifiable(_entries);

  bool get isOnline => _online;

  OutboxEntry? entry(String clientId) {
    for (final entry in _entries) {
      if (entry.clientId == clientId) {
        return entry;
      }
    }
    return null;
  }

  /// Puts back entries kept from an earlier run: waiting ones are tried
  /// once online.
  void restore(Iterable<OutboxEntry> restored) {
    final known = {for (final entry in _entries) entry.clientId};
    _entries = [
      ..._entries,
      for (final entry in restored)
        if (known.add(entry.clientId)) entry.copyWith(nextAttemptAt: null),
    ];
    _changed();
    _schedule();
  }

  /// Adds a message to send; [sendNow] (or the next pass while online)
  /// tries it.
  OutboxEntry enqueue(OutboxEntry entry) {
    _entries = [..._entries, entry];
    _changed();
    return entry;
  }

  /// Tries [clientId] now (while online), and reports how it went.
  Future<OutboxAttempt> sendNow(String clientId) {
    final inFlight = _inFlight[clientId];
    if (inFlight != null) {
      return inFlight;
    }
    final current = entry(clientId);
    if (current == null) {
      return Future.value(const OutboxSent(null));
    }
    if (!_online) {
      return Future.value(
        OutboxWillRetry(const _OfflineError(), gaveUp: false),
      );
    }
    final attempt = _attempt(current).whenComplete(() {
      _inFlight.remove(clientId);
      // A failed try waits for its backoff.
      _schedule();
    });
    _inFlight[clientId] = attempt;
    return attempt;
  }

  /// The reader tapped a failed message: try it again from scratch.
  Future<OutboxAttempt> retry(String clientId) {
    reset(clientId);
    return sendNow(clientId);
  }

  /// Puts a failed message back in the queue as new, without sending it
  /// yet (the next [drain] does).
  void reset(String clientId) {
    _replace(
      clientId,
      (entry) => entry.copyWith(
        state: OutboxState.sending,
        attempts: 0,
        nextAttemptAt: null,
        error: null,
        failedAt: null,
      ),
    );
  }

  /// Drops a message the reader no longer wants sent.
  void discard(String clientId) {
    _entries = [
      for (final entry in _entries)
        if (entry.clientId != clientId) entry,
    ];
    _changed();
  }

  /// Tries every waiting entry when the connection comes back, at once
  /// rather than after their backoff.
  void setOnline(bool online) {
    if (_online == online) {
      return;
    }
    _online = online;
    if (online) {
      _entries = [
        for (final entry in _entries)
          entry.state == OutboxState.sending
              ? entry.copyWith(nextAttemptAt: null)
              : entry,
      ];
      _changed();
    }
    _schedule();
  }

  /// Sends what is due, oldest first, one at a time.
  Future<void> drain() async {
    while (!_disposed && _online) {
      final now = _clock();
      final due = _entries.where((entry) {
        return entry.state == OutboxState.sending &&
            !_inFlight.containsKey(entry.clientId) &&
            (entry.nextAttemptAt == null || !entry.nextAttemptAt!.isAfter(now));
      }).firstOrNull;
      if (due == null) {
        break;
      }
      final result = await sendNow(due.clientId);
      if (result is OutboxWillRetry && !result.gaveUp) {
        // The network is still failing: later ones would fail too.
        break;
      }
    }
    _schedule();
  }

  Future<OutboxAttempt> _attempt(OutboxEntry entry) async {
    final attempts = entry.attempts + 1;
    _replace(entry.clientId, (entry) => entry.copyWith(attempts: attempts));
    try {
      final messageId = await _send(entry);
      if (_disposed) {
        return OutboxSent(messageId);
      }
      try {
        await onSent?.call(entry, messageId);
      } catch (_) {
        // Showing the stored message is best effort.
      }
      discard(entry.clientId);
      return OutboxSent(messageId);
    } catch (error) {
      if (_disposed) {
        return OutboxRefused(error);
      }
      if (isSendRefusal(error)) {
        _replace(
          entry.clientId,
          (entry) => entry.copyWith(
            state: OutboxState.failed,
            nextAttemptAt: null,
            error: error,
            failedAt: _clock(),
          ),
        );
        return OutboxRefused(error);
      }
      final gaveUp = attempts >= maxAttempts;
      _replace(
        entry.clientId,
        (entry) => entry.copyWith(
          state: gaveUp ? OutboxState.failed : OutboxState.sending,
          nextAttemptAt: gaveUp ? null : _clock().add(backoffFor(attempts)),
          error: error,
          failedAt: _clock(),
        ),
      );
      return OutboxWillRetry(error, gaveUp: gaveUp);
    }
  }

  /// The wait after [attempts] failed tries: [baseDelay] doubled per try,
  /// up to [maxDelay], give or take a fifth.
  Duration backoffFor(int attempts) {
    final exponent = math.max(0, attempts - 1);
    final raw = baseDelay.inMilliseconds * math.pow(2, exponent);
    final capped = math.min(raw.toDouble(), maxDelay.inMilliseconds.toDouble());
    final jitter = 0.8 + _random.nextDouble() * 0.4;
    return Duration(milliseconds: (capped * jitter).round());
  }

  void _replace(String clientId, OutboxEntry Function(OutboxEntry) update) {
    if (!_entries.any((entry) => entry.clientId == clientId)) {
      return;
    }
    _entries = [
      for (final entry in _entries)
        entry.clientId == clientId ? update(entry) : entry,
    ];
    _changed();
  }

  void _changed() {
    if (!_disposed) {
      onChanged?.call(entries);
    }
  }

  /// Wakes [drain] when the next entry is due.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (_disposed || !_online) {
      return;
    }
    final waiting = _entries.where(
      (entry) =>
          entry.state == OutboxState.sending &&
          !_inFlight.containsKey(entry.clientId),
    );
    if (waiting.isEmpty) {
      return;
    }
    final now = _clock();
    var next = waiting.first.nextAttemptAt ?? now;
    for (final entry in waiting) {
      final at = entry.nextAttemptAt ?? now;
      if (at.isBefore(next)) {
        next = at;
      }
    }
    final wait = next.isAfter(now) ? next.difference(now) : Duration.zero;
    _timer = Timer(wait, () => unawaited(drain()));
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

class _OfflineError implements Exception {
  const _OfflineError();

  @override
  String toString() => 'Offline';
}

final _secureRandom = () {
  try {
    return math.Random.secure();
  } catch (_) {
    return math.Random();
  }
}();

/// A random (version 4) UUID for a new outbox message.
String newClientId([math.Random? random]) {
  final source = random ?? _secureRandom;
  final bytes = List<int>.generate(16, (_) => source.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = [
    for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
  ].join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

/// The time from `package:clock`, which tests can fake.
DateTime clockNow() => clock.now();

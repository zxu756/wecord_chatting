import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

enum ScheduledMessageStatus {
  pending,
  failed;

  static ScheduledMessageStatus fromJson(String value) {
    return value == 'failed'
        ? ScheduledMessageStatus.failed
        : ScheduledMessageStatus.pending;
  }
}

/// A text message waiting to be sent at [sendAt] (a UTC instant).
class ScheduledMessage {
  const ScheduledMessage({
    required this.id,
    required this.conversationId,
    required this.body,
    required this.sendAt,
    this.mentions = const [],
    this.status = ScheduledMessageStatus.pending,
    this.lastError,
  });

  factory ScheduledMessage.fromJson(Map<String, dynamic> json) {
    return ScheduledMessage(
      id: json['id'] as String,
      conversationId: json['conversation_id'] as String,
      body: json['body'] as String? ?? '',
      mentions: [
        for (final mention in json['mentions'] as List<dynamic>? ?? const [])
          Map<String, dynamic>.from(mention as Map),
      ],
      sendAt: DateTime.parse(json['send_at'] as String),
      status: ScheduledMessageStatus.fromJson(
        json['status'] as String? ?? 'pending',
      ),
      lastError: json['last_error'] as String?,
    );
  }

  final String id;
  final String conversationId;
  final String body;

  /// The mentions as the server stores them (offsets into [body]).
  final List<Map<String, dynamic>> mentions;
  final DateTime sendAt;
  final ScheduledMessageStatus status;

  /// Why a failed message was not sent (the server's words, or
  /// `automod:<reason>`).
  final String? lastError;

  bool get isFailed => status == ScheduledMessageStatus.failed;

  /// [lastError] as a sentence for the owner.
  String? get failureReason {
    final error = lastError;
    if (!isFailed || error == null) {
      return isFailed ? tr('It could not be sent.') : null;
    }
    if (error.startsWith('automod:')) {
      final reason = error.substring('automod:'.length).trim();
      return reason.isEmpty
          ? tr('AutoMod blocked it.')
          : tr('AutoMod blocked it: {reason}', {'reason': reason});
    }
    return error;
  }
}

/// [mentions] that still point at the same text in [newBody], moved if the
/// text around them changed; mentions whose text is gone are dropped (they
/// would not notify anyone).
List<Map<String, dynamic>> retainMentions({
  required String oldBody,
  required String newBody,
  required List<Map<String, dynamic>> mentions,
}) {
  final kept = <Map<String, dynamic>>[];
  for (final mention in mentions) {
    final start = (mention['start'] as num?)?.toInt() ?? 0;
    final end = (mention['end'] as num?)?.toInt() ?? 0;
    if (start < 0 || end <= start || end > oldBody.length) {
      continue;
    }
    final text = oldBody.substring(start, end);
    var best = -1;
    // The occurrence nearest to where it was.
    for (
      var index = newBody.indexOf(text);
      index != -1;
      index = newBody.indexOf(text, index + 1)
    ) {
      if (best == -1 || (index - start).abs() < (best - start).abs()) {
        best = index;
      }
    }
    if (best == -1) {
      continue;
    }
    kept.add({...mention, 'start': best, 'end': best + text.length});
  }
  return kept;
}

abstract interface class ScheduledMessagesRepository {
  /// The current user's pending and failed scheduled messages in a
  /// conversation, soonest first.
  Future<List<ScheduledMessage>> list(String conversationId);

  Future<ScheduledMessage> create({
    required String conversationId,
    required String body,
    required DateTime sendAt,
    List<Map<String, dynamic>> mentions = const [],
  });

  /// Changes the text or time; a failed message goes back in the queue.
  Future<ScheduledMessage> update(
    String id, {
    required String body,
    required DateTime sendAt,
    required List<Map<String, dynamic>> mentions,
  });

  Future<void> delete(String id);

  /// Sends it now; returns the sent message's id.
  Future<String> sendNow(String id);
}

final scheduledMessagesRepositoryProvider =
    Provider<ScheduledMessagesRepository>((ref) {
      try {
        return SupabaseScheduledMessagesRepository(
          ref.watch(supabaseClientProvider),
        );
      } on ProviderException {
        return const UninitializedScheduledMessagesRepository();
      }
    });

/// The current user's scheduled messages in a conversation.
final scheduledMessagesProvider = FutureProvider.autoDispose
    .family<List<ScheduledMessage>, String>((ref, conversationId) {
      return ref
          .watch(scheduledMessagesRepositoryProvider)
          .list(conversationId);
    });

class SupabaseScheduledMessagesRepository
    implements ScheduledMessagesRepository {
  const SupabaseScheduledMessagesRepository(this._client);

  final SupabaseClient _client;

  static const _table = 'scheduled_messages';

  @override
  Future<List<ScheduledMessage>> list(String conversationId) async {
    final rows = await _client
        .from(_table)
        .select()
        .eq('conversation_id', conversationId)
        .inFilter('status', ['pending', 'failed'])
        .order('send_at');
    return [for (final row in rows) ScheduledMessage.fromJson(row)];
  }

  @override
  Future<ScheduledMessage> create({
    required String conversationId,
    required String body,
    required DateTime sendAt,
    List<Map<String, dynamic>> mentions = const [],
  }) async {
    final ownerId = _client.auth.currentUser?.id;
    if (ownerId == null) {
      throw StateError('Sign in to schedule messages.');
    }
    final row = await _client
        .from(_table)
        .insert({
          'owner_id': ownerId,
          'conversation_id': conversationId,
          'body': body,
          'mentions': mentions,
          'send_at': sendAt.toUtc().toIso8601String(),
        })
        .select()
        .single();
    return ScheduledMessage.fromJson(row);
  }

  @override
  Future<ScheduledMessage> update(
    String id, {
    required String body,
    required DateTime sendAt,
    required List<Map<String, dynamic>> mentions,
  }) async {
    final row = await _client
        .from(_table)
        .update({
          'body': body,
          'mentions': mentions,
          'send_at': sendAt.toUtc().toIso8601String(),
        })
        .eq('id', id)
        .select()
        .single();
    return ScheduledMessage.fromJson(row);
  }

  @override
  Future<void> delete(String id) async {
    await _client.from(_table).delete().eq('id', id);
  }

  @override
  Future<String> sendNow(String id) async {
    final sent = await _client.rpc<dynamic>(
      'send_scheduled_message_now',
      params: {'p_id': id},
    );
    return sent as String;
  }
}

class UninitializedScheduledMessagesRepository
    implements ScheduledMessagesRepository {
  const UninitializedScheduledMessagesRepository();

  @override
  Future<List<ScheduledMessage>> list(String conversationId) async => const [];

  @override
  Future<ScheduledMessage> create({
    required String conversationId,
    required String body,
    required DateTime sendAt,
    List<Map<String, dynamic>> mentions = const [],
  }) => throw StateError('Supabase must be initialized to schedule messages.');

  @override
  Future<ScheduledMessage> update(
    String id, {
    required String body,
    required DateTime sendAt,
    required List<Map<String, dynamic>> mentions,
  }) => throw StateError('Supabase must be initialized to schedule messages.');

  @override
  Future<void> delete(String id) async {}

  @override
  Future<String> sendNow(String id) =>
      throw StateError('Supabase must be initialized to send messages.');
}

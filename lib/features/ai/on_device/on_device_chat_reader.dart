import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/ai/on_device/on_device_text.dart';

/// The most messages a summary on the device reads: its model is small and
/// each part of a long chat is one more request to it.
const onDeviceSummaryMessages = 200;
const onDeviceRecentMessages = 100;

/// A chat as the model reads it for a summary.
@immutable
class OnDeviceChatLog {
  const OnDeviceChatLog({
    required this.lines,
    required this.total,
    this.firstMessageId,
  });

  /// "Name: text", oldest first.
  final List<String> lines;

  /// How many messages the range holds (the log may be shorter).
  final int total;

  /// The first message of the range, to jump to.
  final String? firstMessageId;
}

/// A message the device may translate.
@immutable
class OnDeviceMessageText {
  const OnDeviceMessageText({
    required this.id,
    required this.type,
    required this.body,
    this.recalled = false,
    this.expired = false,
    this.underReview = false,
    this.viewOnce = false,
  });

  final String id;
  final String type;
  final String body;
  final bool recalled;
  final bool expired;

  /// Held or removed by the AI guard, or waiting for its check.
  final bool underReview;
  final bool viewOnce;

  bool get unavailable => recalled || expired || underReview || viewOnce;
}

/// Reads the chat text the on-device model works on. It reads as the signed
/// in person, so what they cannot see in the app is not read either, and it
/// leaves out what the `ai` function leaves out: recalled, expired and held
/// messages.
abstract interface class OnDeviceChatReader {
  /// The log for a catch-up summary of [conversationId]: the messages after
  /// [afterMessageId] (or after the stored read marker with [useStoredMarker]),
  /// or the latest ones with [recent]. Null when the chat can't be read.
  Future<OnDeviceChatLog?> loadLog({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
  });

  /// The messages [ids] of [conversationId] that can be read.
  Future<List<OnDeviceMessageText>> loadMessages({
    required String conversationId,
    required List<String> ids,
  });
}

/// Where there is no server (tests): nothing can be read.
class NoOnDeviceChatReader implements OnDeviceChatReader {
  const NoOnDeviceChatReader();

  @override
  Future<OnDeviceChatLog?> loadLog({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
  }) async => null;

  @override
  Future<List<OnDeviceMessageText>> loadMessages({
    required String conversationId,
    required List<String> ids,
  }) async => const [];
}

const _columns =
    'id,sender_id,type,body,attachment,webhook_name,created_at,expires_at,review_state';

/// The reader on the Supabase client: row level security decides what is
/// visible, as it does in the app.
class SupabaseOnDeviceChatReader implements OnDeviceChatReader {
  const SupabaseOnDeviceChatReader(this._client);

  final SupabaseClient _client;

  static bool _isViewOnce(Object? attachment) =>
      attachment is Map && attachment['view_once'] == true;

  static bool _expired(Object? expiresAt) {
    if (expiresAt is! String) {
      return false;
    }
    final at = DateTime.tryParse(expiresAt);
    return at != null && !at.isAfter(DateTime.now());
  }

  @override
  Future<OnDeviceChatLog?> loadLog({
    required String conversationId,
    String? afterMessageId,
    bool useStoredMarker = false,
    bool recent = false,
  }) async {
    final conversation = await _client
        .from('conversations')
        .select('id')
        .eq('id', conversationId)
        .maybeSingle();
    if (conversation == null) {
      return null;
    }
    // Where the unread messages start: the reader's last read message as the
    // app remembered it when the chat opened, or as stored now.
    var anchorId = recent ? null : afterMessageId;
    final userId = _client.auth.currentUser?.id;
    if (!recent && useStoredMarker && userId != null) {
      final member = await _client
          .from('conversation_members')
          .select('last_read_message_id')
          .eq('conversation_id', conversationId)
          .eq('user_id', userId)
          .maybeSingle();
      anchorId = member?['last_read_message_id'] as String?;
    }
    String? anchorTime;
    var latest = recent;
    if (anchorId != null) {
      final anchor = await _client
          .from('messages')
          .select('created_at')
          .eq('id', anchorId)
          .eq('conversation_id', conversationId)
          .maybeSingle();
      anchorTime = anchor?['created_at'] as String?;
      if (anchorTime == null) {
        // The marker's message is gone: the latest messages stand in.
        latest = true;
      }
    }
    final limit = latest ? onDeviceRecentMessages : onDeviceSummaryMessages;
    var query = _client
        .from('messages')
        .select(_columns)
        .eq('conversation_id', conversationId)
        .isFilter('recalled_at', null);
    if (anchorTime != null) {
      query = query.gt('created_at', anchorTime);
    }
    final rows = await query
        .order('created_at', ascending: false)
        .order('id', ascending: false)
        .limit(limit);
    final ordered = rows.reversed
        .where(
          (row) =>
              row['review_state'] == null &&
              !_expired(row['expires_at']) &&
              !_isViewOnce(row['attachment']),
        )
        .toList();
    if (ordered.isEmpty) {
      return const OnDeviceChatLog(lines: [], total: 0);
    }
    final senderIds = {for (final row in ordered) row['sender_id'] as String};
    final names = <String, String>{};
    final profiles = await _client
        .from('profiles')
        .select('id,display_name,username')
        .inFilter('id', senderIds.toList());
    for (final profile in profiles) {
      final name = (profile['display_name'] as String?)?.trim();
      names[profile['id'] as String] = name != null && name.isNotEmpty
          ? name
          : (profile['username'] as String?) ?? 'Someone';
    }
    final lines = <String>[];
    for (final row in ordered) {
      final attachment = row['attachment'];
      final line = onDeviceMessageLine(
        sender: names[row['sender_id'] as String] ?? 'Someone',
        type: row['type'] as String? ?? 'text',
        body: row['body'] as String? ?? '',
        fileName: attachment is Map && attachment['name'] is String
            ? attachment['name'] as String
            : null,
        botName: row['webhook_name'] as String?,
      );
      if (line != null) {
        lines.add(line);
      }
    }
    return OnDeviceChatLog(
      lines: lines,
      total: ordered.length,
      firstMessageId: ordered.first['id'] as String?,
    );
  }

  @override
  Future<List<OnDeviceMessageText>> loadMessages({
    required String conversationId,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) {
      return const [];
    }
    final rows = await _client
        .from('messages')
        .select('$_columns,recalled_at')
        .eq('conversation_id', conversationId)
        .inFilter('id', ids);
    return [
      for (final row in rows)
        OnDeviceMessageText(
          id: row['id'] as String,
          type: row['type'] as String? ?? 'text',
          body: row['body'] as String? ?? '',
          recalled: row['recalled_at'] != null,
          expired: _expired(row['expires_at']),
          underReview: row['review_state'] != null,
          viewOnce: _isViewOnce(row['attachment']),
        ),
    ];
  }
}

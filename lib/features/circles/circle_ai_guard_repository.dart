import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wecord/features/circles/circle_automod_repository.dart'
    show RpcDataSource, SupabaseRpcDataSource, UninitializedRpcDataSource;
import 'package:wecord/shared/api/supabase_providers.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// Who counts as a new member for the AI guard.
enum AiGuardNewRule {
  /// Joined less than [CircleAiGuard.joinedDays] days ago.
  joinedDays('joined_days'),

  /// Has sent fewer than [CircleAiGuard.messageCount] messages in the
  /// circle.
  messageCount('message_count');

  const AiGuardNewRule(this.key);

  final String key;

  static AiGuardNewRule fromKey(Object? key) => values.firstWhere(
    (rule) => rule.key == key,
    orElse: () => AiGuardNewRule.joinedDays,
  );
}

/// What happens to a message the AI flags.
enum AiGuardAction {
  /// Stays hidden until a moderator approves or removes it.
  hold('hold'),

  /// Is shown to everyone, with a flag for the moderators.
  flag('flag');

  const AiGuardAction(this.key);

  final String key;

  static AiGuardAction fromKey(Object? key) => values.firstWhere(
    (action) => action.key == key,
    orElse: () => AiGuardAction.hold,
  );
}

/// The days a member counts as new for ([AiGuardNewRule.joinedDays]).
const aiGuardJoinedDayChoices = [1, 3, 7];

/// The message counts offered for [AiGuardNewRule.messageCount].
const aiGuardMessageCountChoices = [3, 5, 10, 20, 50];

/// A circle's AI guard settings (`get_circle_ai_guard`).
class CircleAiGuard {
  const CircleAiGuard({
    this.enabled = false,
    this.newRule = AiGuardNewRule.joinedDays,
    this.joinedDays = 3,
    this.messageCount = 10,
    this.action = AiGuardAction.hold,
    this.circleAiEnabled = true,
  });

  factory CircleAiGuard.fromJson(Map<String, dynamic> json) {
    return CircleAiGuard(
      enabled: json['enabled'] == true,
      newRule: AiGuardNewRule.fromKey(json['new_rule']),
      joinedDays: (json['joined_days'] as num?)?.toInt() ?? 3,
      messageCount: (json['message_count'] as num?)?.toInt() ?? 10,
      action: AiGuardAction.fromKey(json['action']),
      circleAiEnabled: json['circle_ai_enabled'] != false,
    );
  }

  final bool enabled;
  final AiGuardNewRule newRule;
  final int joinedDays;
  final int messageCount;
  final AiGuardAction action;

  /// The circle's own AI switch. The guard only works while it is on.
  final bool circleAiEnabled;

  /// Whether the guard is checking messages right now.
  bool get isActive => enabled && circleAiEnabled;

  CircleAiGuard copyWith({
    bool? enabled,
    AiGuardNewRule? newRule,
    int? joinedDays,
    int? messageCount,
    AiGuardAction? action,
  }) {
    return CircleAiGuard(
      enabled: enabled ?? this.enabled,
      newRule: newRule ?? this.newRule,
      joinedDays: joinedDays ?? this.joinedDays,
      messageCount: messageCount ?? this.messageCount,
      action: action ?? this.action,
      circleAiEnabled: circleAiEnabled,
    );
  }
}

/// What the AI found in a flagged message.
enum AiGuardVerdict {
  spam('spam'),
  scam('scam'),
  harassment('harassment'),
  sexual('sexual'),
  other('other');

  const AiGuardVerdict(this.key);

  final String key;

  static AiGuardVerdict fromKey(Object? key) => values.firstWhere(
    (verdict) => verdict.key == key,
    orElse: () => AiGuardVerdict.other,
  );

  String get label => switch (this) {
    AiGuardVerdict.spam => tr('Spam'),
    AiGuardVerdict.scam => tr('Scam or phishing'),
    AiGuardVerdict.harassment => tr('Harassment'),
    AiGuardVerdict.sexual => tr('Sexual content'),
    AiGuardVerdict.other => tr('Other'),
  };
}

/// One message the AI flagged, waiting for a moderator
/// (`list_message_reviews`).
class MessageReview {
  const MessageReview({
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.senderName,
    required this.body,
    required this.held,
    required this.verdict,
    required this.sentAt,
    this.channelName,
    this.senderAvatarUrl,
    this.reason,
    this.reasonZh,
  });

  factory MessageReview.fromJson(Map<String, dynamic> json) {
    return MessageReview(
      messageId: json['message_id'] as String,
      conversationId: json['conversation_id'] as String,
      senderId: json['sender_id'] as String,
      senderName: json['sender_name'] as String? ?? '',
      senderAvatarUrl: json['sender_avatar_url'] as String?,
      channelName: json['channel_name'] as String?,
      body: json['body'] as String? ?? '',
      held: json['state'] == 'held',
      verdict: AiGuardVerdict.fromKey(json['verdict']),
      reason: json['reason'] as String?,
      reasonZh: json['reason_zh'] as String?,
      sentAt: DateTime.parse(json['sent_at'] as String),
    );
  }

  final String messageId;
  final String conversationId;
  final String senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final String? channelName;
  final String body;

  /// Hidden from everyone but the author and moderators (hold mode);
  /// otherwise it was released with a flag (flag mode).
  final bool held;
  final AiGuardVerdict verdict;
  final String? reason;

  /// The AI's reason in Simplified Chinese; null for reviews made before it
  /// was asked for.
  final String? reasonZh;
  final DateTime sentAt;

  /// The reason in the app's language: the Chinese one when the app is in
  /// Chinese and there is one, else the English one.
  String? get localizedReason {
    final zh = reasonZh?.trim() ?? '';
    if (AppStrings.isChinese && zh.isNotEmpty) {
      return zh;
    }
    return reason;
  }
}

/// The AI guard's settings and review queue.
class CircleAiGuardRepository {
  const CircleAiGuardRepository(this._rpc, {this.changeSource});

  final RpcDataSource _rpc;

  /// Follows the review queue of a circle in realtime; none in tests.
  final Stream<void> Function(String circleId)? changeSource;

  Future<CircleAiGuard> getGuard(String circleId) async {
    final row = await _rpc.rpc('get_circle_ai_guard', {
      'target_circle_id': circleId,
    });
    return CircleAiGuard.fromJson(Map<String, dynamic>.from(row! as Map));
  }

  Future<CircleAiGuard> saveGuard(String circleId, CircleAiGuard guard) async {
    final row = await _rpc.rpc('set_circle_ai_guard', {
      'target_circle_id': circleId,
      'guard_enabled': guard.enabled,
      'guard_new_rule': guard.newRule.key,
      'guard_joined_days': guard.joinedDays,
      'guard_message_count': guard.messageCount,
      'guard_action': guard.action.key,
    });
    return CircleAiGuard.fromJson(Map<String, dynamic>.from(row! as Map));
  }

  /// The messages waiting for the current user to review, newest first.
  Future<List<MessageReview>> listReviews(String circleId) async {
    final rows = await _rpc.rpc('list_message_reviews', {
      'target_circle_id': circleId,
      'max_results': 100,
    });
    return [
      for (final row in (rows as List? ?? const []))
        MessageReview.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  /// How many messages wait for review (up to 99).
  Future<int> countReviews(String circleId) async {
    final count = await _rpc.rpc('count_message_reviews', {
      'target_circle_id': circleId,
    });
    return (count as num?)?.toInt() ?? 0;
  }

  /// Approves a held message (it becomes visible) or closes a flagged one.
  Future<void> approve(String messageId) async {
    await _rpc.rpc('decide_message_review', {
      'target_message_id': messageId,
      'decision': 'approve',
    });
  }

  /// Deletes the message.
  Future<void> remove(String messageId) async {
    await _rpc.rpc('decide_message_review', {
      'target_message_id': messageId,
      'decision': 'remove',
    });
  }

  /// Emits when the queue of [circleId] changes.
  Stream<void> changes(String circleId) =>
      changeSource?.call(circleId) ?? const Stream<void>.empty();
}

/// Listens to `message_reviews` of one circle through Supabase Realtime.
Stream<void> _reviewChanges(SupabaseClient client, String circleId) {
  late RealtimeChannel channel;
  late StreamController<void> controller;
  controller = StreamController<void>(
    onListen: () {
      channel = client
          .channel('message-reviews-$circleId')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'message_reviews',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'circle_id',
              value: circleId,
            ),
            callback: (_) => controller.add(null),
          )
          .subscribe();
    },
    onCancel: () async {
      await client.removeChannel(channel);
    },
  );
  return controller.stream;
}

final circleAiGuardRepositoryProvider = Provider<CircleAiGuardRepository>((
  ref,
) {
  try {
    final client = ref.watch(supabaseClientProvider);
    return CircleAiGuardRepository(
      SupabaseRpcDataSource(client),
      changeSource: (circleId) => _reviewChanges(client, circleId),
    );
  } on ProviderException {
    return const CircleAiGuardRepository(UninitializedRpcDataSource());
  }
});

/// The guard settings of a circle (managers only).
final circleAiGuardProvider = FutureProvider.autoDispose
    .family<CircleAiGuard, String>((ref, circleId) {
      return ref.watch(circleAiGuardRepositoryProvider).getGuard(circleId);
    });

/// The messages waiting for review in a circle, kept up to date.
final messageReviewsProvider = FutureProvider.autoDispose
    .family<List<MessageReview>, String>((ref, circleId) {
      final repository = ref.watch(circleAiGuardRepositoryProvider);
      final subscription = repository
          .changes(circleId)
          .listen((_) => ref.invalidateSelf());
      ref.onDispose(subscription.cancel);
      return repository.listReviews(circleId);
    });

/// How many messages wait for review in a circle, for the badge on its
/// moderation tools. 0 while loading and when it cannot be read.
final messageReviewCountProvider = FutureProvider.autoDispose
    .family<int, String>((ref, circleId) {
      final repository = ref.watch(circleAiGuardRepositoryProvider);
      final subscription = repository
          .changes(circleId)
          .listen((_) => ref.invalidateSelf());
      ref.onDispose(subscription.cancel);
      return repository.countReviews(circleId);
    });

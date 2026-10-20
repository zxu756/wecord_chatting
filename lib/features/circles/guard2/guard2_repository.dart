import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wecord/features/circles/circle_ai_guard_repository.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/l10n/l10n.dart';

/// What the AI guard looks at besides the text of messages
/// (`get_circle_ai_guard_scope`): polls, the titles of events, notes and
/// tasks, and pictures.
@immutable
class CircleAiGuardScope {
  const CircleAiGuardScope({
    this.polls = true,
    this.items = true,
    this.images = false,
    this.visionAvailable = false,
  });

  factory CircleAiGuardScope.fromJson(Map<String, dynamic> json) {
    return CircleAiGuardScope(
      polls: json['check_polls'] != false,
      items: json['check_items'] != false,
      images: json['check_images'] == true,
      visionAvailable: json['vision_available'] == true,
    );
  }

  final bool polls;
  final bool items;
  final bool images;

  /// Whether the server can read pictures right now. Without it a picture
  /// is sent as usual whatever [images] says.
  final bool visionAvailable;

  CircleAiGuardScope copyWith({bool? polls, bool? items, bool? images}) {
    return CircleAiGuardScope(
      polls: polls ?? this.polls,
      items: items ?? this.items,
      images: images ?? this.images,
      visionAvailable: visionAvailable,
    );
  }
}

/// What kind of thing the AI flagged in the Review queue.
enum GuardItemType {
  circleEvent('circle_event'),
  note('note'),
  taskList('task_list'),
  taskItem('task_item');

  const GuardItemType(this.key);

  final String key;

  static GuardItemType fromKey(Object? key) => values.firstWhere(
    (type) => type.key == key,
    orElse: () => GuardItemType.note,
  );

  String get label => switch (this) {
    GuardItemType.circleEvent => tr('Event'),
    GuardItemType.note => tr('Note'),
    GuardItemType.taskList => tr('Task list'),
    GuardItemType.taskItem => tr('Task'),
  };
}

/// An event, note or task the AI flagged (`list_guard_item_reviews`).
@immutable
class GuardItemReview {
  const GuardItemReview({
    required this.id,
    required this.type,
    required this.itemId,
    required this.actorName,
    required this.title,
    required this.verdict,
    required this.flaggedAt,
    this.conversationId,
    this.channelId,
    this.channelName,
    this.actorAvatarUrl,
    this.detail = '',
    this.reason,
    this.reasonZh,
  });

  factory GuardItemReview.fromJson(Map<String, dynamic> json) {
    return GuardItemReview(
      id: json['id'] as String,
      type: GuardItemType.fromKey(json['item_type']),
      itemId: json['item_id'] as String,
      conversationId: json['conversation_id'] as String?,
      channelId: json['channel_id'] as String?,
      channelName: json['channel_name'] as String?,
      actorName: json['actor_name'] as String? ?? '',
      actorAvatarUrl: json['actor_avatar_url'] as String?,
      title: json['title'] as String? ?? '',
      detail: json['detail'] as String? ?? '',
      verdict: AiGuardVerdict.fromKey(json['verdict']),
      reason: json['reason'] as String?,
      reasonZh: json['reason_zh'] as String?,
      flaggedAt: DateTime.parse(json['flagged_at'] as String),
    );
  }

  final String id;
  final GuardItemType type;
  final String itemId;
  final String? conversationId;
  final String? channelId;
  final String? channelName;
  final String actorName;
  final String? actorAvatarUrl;
  final String title;
  final String detail;
  final AiGuardVerdict verdict;
  final String? reason;
  final String? reasonZh;
  final DateTime flaggedAt;

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

/// The scope settings and the queue of flagged events, notes and tasks.
class Guard2Repository {
  const Guard2Repository(this._rpc);

  final CircleRpc _rpc;

  Future<CircleAiGuardScope> getScope(String circleId) async {
    final row = await _rpc('get_circle_ai_guard_scope', {
      'target_circle_id': circleId,
    });
    return CircleAiGuardScope.fromJson(Map<String, dynamic>.from(row! as Map));
  }

  Future<CircleAiGuardScope> saveScope(
    String circleId,
    CircleAiGuardScope scope,
  ) async {
    final row = await _rpc('set_circle_ai_guard_scope', {
      'target_circle_id': circleId,
      'scope_polls': scope.polls,
      'scope_items': scope.items,
      'scope_images': scope.images,
    });
    return CircleAiGuardScope.fromJson(Map<String, dynamic>.from(row! as Map));
  }

  Future<List<GuardItemReview>> listItems(String circleId) async {
    final rows = await _rpc('list_guard_item_reviews', {
      'target_circle_id': circleId,
      'max_results': 100,
    });
    return [
      for (final row in (rows as List? ?? const []))
        GuardItemReview.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
  }

  Future<int> countItems(String circleId) async {
    final count = await _rpc('count_guard_item_reviews', {
      'target_circle_id': circleId,
    });
    return (count as num?)?.toInt() ?? 0;
  }

  /// Closes a flagged card.
  Future<void> dismiss(String reviewId) async {
    await _rpc('dismiss_guard_item_review', {'target_review_id': reviewId});
  }
}

final guard2RepositoryProvider = Provider<Guard2Repository>((ref) {
  return Guard2Repository(ref.watch(circleRpcProvider));
});

/// What the guard checks besides text (managers only).
final circleAiGuardScopeProvider = FutureProvider.autoDispose
    .family<CircleAiGuardScope, String>((ref, circleId) {
      return ref.watch(guard2RepositoryProvider).getScope(circleId);
    });

/// The events, notes and tasks the AI flagged in a circle.
final guardItemReviewsProvider = FutureProvider.autoDispose
    .family<List<GuardItemReview>, String>((ref, circleId) {
      return ref.watch(guard2RepositoryProvider).listItems(circleId);
    });

/// How many flagged items wait for a moderator (0 when they cannot be read).
final guardItemCountProvider = FutureProvider.autoDispose.family<int, String>((
  ref,
  circleId,
) async {
  try {
    return await ref.watch(guard2RepositoryProvider).countItems(circleId);
  } on Object {
    return 0;
  }
});

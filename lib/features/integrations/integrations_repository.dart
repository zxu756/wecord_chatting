// RSS feeds and GitHub connections of a channel (roadmap I6): the
// functions behind channel settings -> Integrations. Reading and changing
// them needs the "manage webhooks" permission; the database checks it.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/circles/circle_rpc.dart';

DateTime? _time(Object? value) =>
    value is String ? DateTime.tryParse(value)?.toUtc() : null;

/// The events a GitHub connection can send, in the order they are listed.
/// The names are GitHub's own, so they stay in English.
const githubEventNames = <String>[
  'push',
  'pull_request',
  'issues',
  'issue_comment',
  'release',
  'workflow_run',
];

/// A circle can follow this many feeds, and a channel this many.
const maxFeedsPerCircle = 10;
const maxFeedsPerChannel = 5;

/// A circle can have this many GitHub connections, and a channel this many.
const maxGithubPerCircle = 10;
const maxGithubPerChannel = 5;

/// Why a feed or connection is switched off by itself.
enum PausedReason {
  /// The feed failed too many times in a row (or can never work).
  failing,

  /// The person who added it can no longer post here.
  creatorLostAccess,

  /// The person who added it left WeCord.
  creatorGone;

  static PausedReason? fromJson(Object? value) => switch (value) {
    'failing' => PausedReason.failing,
    'creator_lost_access' => PausedReason.creatorLostAccess,
    'creator_gone' => PausedReason.creatorGone,
    _ => null,
  };
}

/// A feed a channel follows.
class ChannelFeed {
  const ChannelFeed({
    required this.id,
    required this.channelId,
    required this.url,
    required this.enabled,
    this.title,
    this.pausedReason,
    this.consecutiveFailures = 0,
    this.lastError,
    this.lastSuccessAt,
    this.lastItemAt,
    this.itemsPosted = 0,
    this.creatorName,
    this.createdAt,
  });

  factory ChannelFeed.fromJson(Map<String, dynamic> json) {
    return ChannelFeed(
      id: json['id'] as String,
      channelId: json['channel_id'] as String? ?? '',
      url: json['url'] as String? ?? '',
      title: json['title'] as String?,
      enabled: json['enabled'] == true,
      pausedReason: PausedReason.fromJson(json['paused_reason']),
      consecutiveFailures: (json['consecutive_failures'] as num?)?.toInt() ?? 0,
      lastError: json['last_error'] as String?,
      lastSuccessAt: _time(json['last_success_at']),
      lastItemAt: _time(json['last_item_at']),
      itemsPosted: (json['items_posted'] as num?)?.toInt() ?? 0,
      creatorName: json['creator_name'] as String?,
      createdAt: _time(json['created_at']),
    );
  }

  final String id;
  final String channelId;
  final String url;

  /// The feed's own name, known after the first read.
  final String? title;
  final bool enabled;
  final PausedReason? pausedReason;
  final int consecutiveFailures;

  /// A short code of what went wrong last, never a page's words.
  final String? lastError;
  final DateTime? lastSuccessAt;
  final DateTime? lastItemAt;
  final int itemsPosted;
  final String? creatorName;
  final DateTime? createdAt;

  /// The name to show: the feed's title, else its web site.
  String get displayName {
    final name = title?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return Uri.tryParse(url)?.host ?? url;
  }

  bool get hasProblem => enabled && consecutiveFailures > 0;
}

/// A GitHub repository connected to a channel. The secret is only there right
/// after it was made.
class GithubHook {
  const GithubHook({
    required this.id,
    required this.channelId,
    required this.label,
    required this.events,
    required this.enabled,
    this.pausedReason,
    this.lastDeliveryAt,
    this.lastEvent,
    this.deliveriesCount = 0,
    this.creatorName,
    this.createdAt,
    this.secret,
  });

  factory GithubHook.fromJson(Map<String, dynamic> json) {
    return GithubHook(
      id: json['id'] as String,
      channelId: json['channel_id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      events: [
        for (final name in json['events'] as List<dynamic>? ?? const [])
          name as String,
      ],
      enabled: json['enabled'] == true,
      pausedReason: PausedReason.fromJson(json['paused_reason']),
      lastDeliveryAt: _time(json['last_delivery_at']),
      lastEvent: json['last_event'] as String?,
      deliveriesCount: (json['deliveries_count'] as num?)?.toInt() ?? 0,
      creatorName: json['creator_name'] as String?,
      createdAt: _time(json['created_at']),
      secret: json['secret'] as String?,
    );
  }

  final String id;
  final String channelId;
  final String label;
  final List<String> events;
  final bool enabled;
  final PausedReason? pausedReason;
  final DateTime? lastDeliveryAt;
  final String? lastEvent;
  final int deliveriesCount;
  final String? creatorName;
  final DateTime? createdAt;

  /// Shown once, when the connection is made or the secret is replaced.
  final String? secret;

  /// `<SUPABASE_URL>/functions/v1/github/<id>`: what GitHub posts to.
  String payloadUrlFor(Uri supabaseUrl) {
    final base = supabaseUrl.toString().replaceFirst(RegExp(r'/+$'), '');
    return '$base/functions/v1/github/$id';
  }
}

enum IntegrationProblem {
  /// The address is not a public https address.
  badAddress,

  /// The circle or the channel has all it can have.
  limit,

  /// The channel already follows that feed.
  duplicate,

  /// The person may not manage integrations here (any more).
  notAllowed,

  /// A name or an event list the server does not take.
  invalid,
}

/// A change the server refused, in terms the screen can word.
class IntegrationException implements Exception {
  const IntegrationException(this.problem);

  final IntegrationProblem problem;

  @override
  String toString() => 'IntegrationException($problem)';
}

final integrationsRepositoryProvider = Provider<IntegrationsRepository>((ref) {
  return IntegrationsRepository(ref.watch(circleRpcProvider));
});

/// The feeds a channel follows.
final channelFeedsProvider = FutureProvider.autoDispose
    .family<List<ChannelFeed>, String>((ref, channelId) {
      return ref.watch(integrationsRepositoryProvider).listFeeds(channelId);
    });

/// The GitHub connections of a channel.
final githubHooksProvider = FutureProvider.autoDispose
    .family<List<GithubHook>, String>((ref, channelId) {
      return ref.watch(integrationsRepositoryProvider).listHooks(channelId);
    });

class IntegrationsRepository {
  const IntegrationsRepository(this._rpc);

  final CircleRpc _rpc;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (error) {
      final problem = switch (error.code) {
        '23505' => IntegrationProblem.duplicate,
        '54000' => IntegrationProblem.limit,
        '42501' => IntegrationProblem.notAllowed,
        '22023' =>
          error.message.startsWith('The address') ||
                  error.message.startsWith('That name')
              ? IntegrationProblem.badAddress
              : IntegrationProblem.invalid,
        _ => null,
      };
      if (problem == null) {
        rethrow;
      }
      throw IntegrationException(problem);
    }
  }

  Future<List<ChannelFeed>> listFeeds(String channelId) async {
    final rows = await _guard(
      () => _rpc('list_channel_feeds', {'target_channel_id': channelId}),
    );
    return rpcRows(rows).map(ChannelFeed.fromJson).toList();
  }

  Future<ChannelFeed> addFeed(String channelId, String url) async {
    final row = await _guard(
      () => _rpc('add_channel_feed', {
        'target_channel_id': channelId,
        'feed_url': url.trim(),
      }),
    );
    return ChannelFeed.fromJson(rpcObject(row));
  }

  Future<ChannelFeed> setFeedEnabled(String feedId, {required bool on}) async {
    final row = await _guard(
      () => _rpc('set_channel_feed_enabled', {
        'target_feed_id': feedId,
        'turn_on': on,
      }),
    );
    return ChannelFeed.fromJson(rpcObject(row));
  }

  Future<void> removeFeed(String feedId) async {
    await _guard(() => _rpc('remove_channel_feed', {'target_feed_id': feedId}));
  }

  Future<List<GithubHook>> listHooks(String channelId) async {
    final rows = await _guard(
      () => _rpc('list_github_hooks', {'target_channel_id': channelId}),
    );
    return rpcRows(rows).map(GithubHook.fromJson).toList();
  }

  /// Makes a connection; the result carries the secret, once.
  Future<GithubHook> addHook(
    String channelId, {
    required String label,
    required List<String> events,
  }) async {
    final row = await _guard(
      () => _rpc('add_github_hook', {
        'target_channel_id': channelId,
        'hook_label': label.trim(),
        'event_names': events,
      }),
    );
    return GithubHook.fromJson(rpcObject(row));
  }

  Future<GithubHook> updateHook(
    String hookId, {
    required String label,
    required List<String> events,
  }) async {
    final row = await _guard(
      () => _rpc('update_github_hook', {
        'target_hook_id': hookId,
        'hook_label': label.trim(),
        'event_names': events,
      }),
    );
    return GithubHook.fromJson(rpcObject(row));
  }

  /// Makes a new secret; the old one stops working at once.
  Future<GithubHook> regenerateSecret(String hookId) async {
    final row = await _guard(
      () => _rpc('regenerate_github_secret', {'target_hook_id': hookId}),
    );
    return GithubHook.fromJson(rpcObject(row));
  }

  Future<GithubHook> setHookEnabled(String hookId, {required bool on}) async {
    final row = await _guard(
      () => _rpc('set_github_hook_enabled', {
        'target_hook_id': hookId,
        'turn_on': on,
      }),
    );
    return GithubHook.fromJson(rpcObject(row));
  }

  Future<void> removeHook(String hookId) async {
    await _guard(() => _rpc('remove_github_hook', {'target_hook_id': hookId}));
  }
}

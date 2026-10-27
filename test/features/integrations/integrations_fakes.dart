// A pretend database for the feeds and GitHub connections of a channel: the
// shapes the Postgres functions return, kept in memory so a test can change
// something and see it come back. Nothing here reaches the web.
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/models/message_embeds.dart';

Map<String, dynamic> feedJson({
  String id = 'feed-1',
  String url = 'https://blog.example.com/feed.xml',
  String? title = 'Example Blog',
  bool enabled = true,
  String? pausedReason,
  int failures = 0,
  String? lastError,
  String? lastItemAt,
}) {
  return {
    'id': id,
    'circle_id': 'circle-1',
    'channel_id': 'channel-1',
    'url': url,
    'title': title,
    'enabled': enabled,
    'paused_reason': pausedReason,
    'consecutive_failures': failures,
    'last_error': lastError,
    'last_success_at': '2026-10-28T09:00:00Z',
    'last_item_at': lastItemAt,
    'items_posted': 3,
    'created_at': '2026-10-20T08:00:00Z',
    'created_by': 'user-1',
    'creator_name': 'Ada',
  };
}

Map<String, dynamic> hookJson({
  String id = 'hook-1',
  String label = 'wecord/app',
  List<String> events = const ['push', 'pull_request'],
  bool enabled = true,
  String? pausedReason,
  String? lastDeliveryAt,
}) {
  return {
    'id': id,
    'circle_id': 'circle-1',
    'channel_id': 'channel-1',
    'label': label,
    'events': events,
    'enabled': enabled,
    'paused_reason': pausedReason,
    'last_delivery_at': lastDeliveryAt,
    'last_event': null,
    'deliveries_count': 0,
    'created_at': '2026-10-20T08:00:00Z',
    'created_by': 'user-1',
    'creator_name': 'Ada',
  };
}

/// The calls the pretend database answers, with what was asked of it.
class FakeIntegrationsBackend {
  FakeIntegrationsBackend({
    List<Map<String, dynamic>>? feeds,
    List<Map<String, dynamic>>? hooks,
  }) : feeds = feeds ?? [],
       hooks = hooks ?? [];

  final List<Map<String, dynamic>> feeds;
  final List<Map<String, dynamic>> hooks;

  /// Every call, in order: name and arguments.
  final calls = <(String, Map<String, dynamic>)>[];

  /// A function that should fail, by name, with this Postgres error code.
  final failing = <String, String>{};

  var _next = 10;

  List<Map<String, dynamic>> callsOf(String name) => [
    for (final (called, params) in calls)
      if (called == name) params,
  ];

  Map<String, dynamic> _find(List<Map<String, dynamic>> rows, Object? id) =>
      rows.firstWhere((row) => row['id'] == id);

  Future<Object?> call(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    if (failing[name] case final code?) {
      throw PostgrestException(message: '$name failed', code: code);
    }
    switch (name) {
      case 'list_channel_feeds':
        return feeds;
      case 'add_channel_feed':
        final feed = feedJson(
          id: 'feed-${_next++}',
          url: params['feed_url'] as String,
          title: null,
        )..['last_success_at'] = null;
        feeds.add(feed);
        return feed;
      case 'set_channel_feed_enabled':
        final feed = _find(feeds, params['target_feed_id']);
        feed['enabled'] = params['turn_on'];
        feed['paused_reason'] = null;
        feed['consecutive_failures'] = 0;
        return feed;
      case 'remove_channel_feed':
        feeds.removeWhere((feed) => feed['id'] == params['target_feed_id']);
        return null;
      case 'list_github_hooks':
        return hooks;
      case 'add_github_hook':
        final hook = {
          ...hookJson(
            id: 'hook-${_next++}',
            label: params['hook_label'] as String,
            events: List<String>.from(params['event_names'] as List),
          ),
        };
        hooks.add(hook);
        return {...hook, 'secret': 'whs_first_0123456789'};
      case 'update_github_hook':
        final hook = _find(hooks, params['target_hook_id']);
        hook['label'] = params['hook_label'];
        hook['events'] = params['event_names'];
        return hook;
      case 'regenerate_github_secret':
        return {
          ..._find(hooks, params['target_hook_id']),
          'secret': 'whs_second_9876543210',
        };
      case 'set_github_hook_enabled':
        final hook = _find(hooks, params['target_hook_id']);
        hook['enabled'] = params['turn_on'];
        hook['paused_reason'] = null;
        return hook;
      case 'remove_github_hook':
        hooks.removeWhere((hook) => hook['id'] == params['target_hook_id']);
        return null;
    }
    throw StateError('Unexpected $name');
  }

  Override get override => circleRpcProvider.overrideWithValue(call);
}

/// A made-up cards payload of a CI message.
Map<String, dynamic> ciEmbedsJson({bool summary = true}) => {
  'cards': [
    {
      'title': '[wecord/app] CI failed',
      'url': 'https://github.com/wecord/app/actions/runs/1',
      'description': 'Fix the thing\nAdd a test',
      'color': '#cf222e',
      'author': {'name': 'wecord/app', 'url': 'https://github.com/wecord/app'},
      'fields': [
        {'name': 'Branch', 'value': 'main', 'inline': true},
        {'name': 'Event', 'value': 'push', 'inline': true},
      ],
      'footer': {'text': 'ada'},
      'timestamp': '2026-10-28T10:00:00Z',
    },
  ],
  'components': [
    [
      {
        'type': 'link',
        'label': 'Open run',
        'url': 'https://github.com/wecord/app/actions/runs/1',
      },
    ],
  ],
  'summary': summary,
};

MessageEmbeds ciEmbeds({bool summary = true}) =>
    MessageEmbeds.maybeFromJson(ciEmbedsJson(summary: summary))!;

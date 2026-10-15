import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/features/circles/announcement_repository.dart';
import 'package:wecord/features/circles/announcement_widgets.dart';
import 'package:wecord/features/circles/circle_rpc.dart';
import 'package:wecord/shared/models/circle.dart';
import 'package:wecord/shared/models/message.dart';
import 'package:wecord/shared/models/message_origin.dart';

class RecordingRpc {
  RecordingRpc(this.responses);

  final Map<String, Object? Function(Map<String, dynamic> params)> responses;
  final calls = <(String, Map<String, dynamic>)>[];

  Future<Object?> call(String name, Map<String, dynamic> params) async {
    calls.add((name, params));
    final response = responses[name];
    if (response == null) {
      throw StateError('Unexpected $name');
    }
    return response(params);
  }
}

const _channel = CircleChannel(
  id: 'channel-1',
  circleId: 'circle-1',
  conversationId: 'conversation-1',
  name: 'news',
  position: 0,
  kind: CircleChannelKind.announcement,
);

Map<String, dynamic> _followJson() => {
  'id': 'follow-1',
  'source_channel_id': 'source-channel',
  'source_channel_name': 'updates',
  'source_circle_id': 'source-circle',
  'source_circle_name': 'Alpha News',
  'target_channel_id': 'channel-1',
  'target_circle_id': 'circle-1',
  'creator_name': 'Bob',
};

void main() {
  test('announcement is a text-like channel kind', () {
    expect(
      CircleChannelKind.fromJson('announcement'),
      CircleChannelKind.announcement,
    );
    expect(_channel.isAnnouncement, isTrue);
    expect(_channel.isTextLike, isTrue);
    expect(
      const CircleChannel(
        id: 'v',
        circleId: 'c',
        conversationId: 'x',
        name: 'General',
        position: 0,
        kind: CircleChannelKind.voice,
      ).isTextLike,
      isFalse,
    );
  });

  test('messages read their crosspost origin and published time', () {
    final message = ChatMessage.fromJson({
      'id': 'm1',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'type': 'text',
      'body': 'Release day',
      'created_at': '2026-10-16T10:00:00Z',
      'webhook_name': 'Alpha News #updates',
      'crosspost': {
        'source_message_id': 'source-message',
        'source_conversation_id': 'source-conversation',
        'source_channel_id': 'source-channel',
        'source_circle_id': 'source-circle',
        'circle_name': 'Alpha News',
        'channel_name': 'updates',
        'author_id': 'author',
        'author_name': 'Alice',
      },
    });
    expect(message.crosspost?.authorName, 'Alice');
    expect(message.crosspost?.sourceConversationId, 'source-conversation');
    expect(message.isWebhook, isTrue);
    expect(message.isPublished, isFalse);

    final published = ChatMessage.fromJson({
      'id': 'm2',
      'conversation_id': 'c1',
      'sender_id': 'u1',
      'type': 'text',
      'body': 'Hello',
      'created_at': '2026-10-16T10:00:00Z',
      'published_at': '2026-10-16T10:05:00Z',
    });
    expect(published.isPublished, isTrue);
    expect(published.copyWith(body: 'Edited').isPublished, isTrue);
    expect(MessageCrosspost.maybeFromJson({'source_message_id': 1}), isNull);
  });

  test('the repository calls the announcement functions', () async {
    final rpc = RecordingRpc({
      'set_channel_announcement': (_) => null,
      'list_follow_targets': (_) => [
        {
          'channel_id': 'target',
          'channel_name': 'general',
          'circle_id': 'circle-2',
          'circle_name': 'Beta',
          'is_following': true,
        },
      ],
      'follow_announcement_channel': (_) => _followJson(),
      'unfollow_announcement_channel': (_) => null,
      'list_channel_follows': (_) => [_followJson()],
      'publish_message': (_) => 3,
    });
    final repository = AnnouncementRepository(rpc.call);

    await repository.setAnnouncementChannel(channelId: 'c', enabled: true);
    final targets = await repository.listFollowTargets('source');
    final follow = await repository.follow(
      sourceChannelId: 'source',
      targetChannelId: 'target',
    );
    await repository.unfollow(follow.id);
    final follows = await repository.listFollows('channel-1');
    final delivered = await repository.publish('message');

    expect(targets.single.isFollowing, isTrue);
    expect(follow.sourceCircleName, 'Alpha News');
    expect(follows.single.creatorName, 'Bob');
    expect(delivered, 3);
    expect(rpc.calls.map((call) => call.$1), [
      'set_channel_announcement',
      'list_follow_targets',
      'follow_announcement_channel',
      'unfollow_announcement_channel',
      'list_channel_follows',
      'publish_message',
    ]);
    expect(rpc.calls.first.$2, {'target_channel_id': 'c', 'enabled': true});
    expect(rpc.calls[2].$2, {
      'source_channel_id': 'source',
      'target_channel_id': 'target',
    });
    expect(rpc.calls.last.$2, {'target_message_id': 'message'});
  });

  testWidgets('a copied announcement names its author and source', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CrosspostOrigin(
            crosspost: MessageCrosspost(
              sourceMessageId: 'm',
              sourceConversationId: 'c',
              sourceChannelId: 'ch',
              sourceCircleId: 'ci',
              circleName: 'Alpha News',
              channelName: 'updates',
              authorName: 'Alice',
            ),
            foregroundColor: Colors.black,
          ),
        ),
      ),
    );
    expect(find.text('Alice · from #updates · Alpha News'), findsOneWidget);
  });

  testWidgets('followed channels list and unfollow', (tester) async {
    var follows = [_followJson()];
    final rpc = RecordingRpc({
      'list_channel_follows': (_) => follows,
      'unfollow_announcement_channel': (_) {
        follows = [];
        return null;
      },
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
        child: const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: FollowedChannelsSection(channel: _channel),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('#updates'), findsOneWidget);
    expect(find.text('Alpha News · followed by Bob'), findsOneWidget);

    await tester.tap(find.text('Unfollow'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('unfollow-confirm')));
    await tester.pumpAndSettle();

    expect(
      rpc.calls.where((call) => call.$1 == 'unfollow_announcement_channel'),
      hasLength(1),
    );
    expect(find.text('#updates'), findsNothing);
  });

  testWidgets('following picks a channel of another circle', (tester) async {
    final rpc = RecordingRpc({
      'list_follow_targets': (_) => [
        {
          'channel_id': 'target',
          'channel_name': 'general',
          'circle_id': 'circle-2',
          'circle_name': 'Beta',
          'is_following': false,
        },
      ],
      'follow_announcement_channel': (_) => _followJson(),
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [circleRpcProvider.overrideWithValue(rpc.call)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () =>
                    showFollowChannelSheet(context, channel: _channel),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Follow #news'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('follow-target-target')));
    await tester.pumpAndSettle();

    expect(rpc.calls.last.$1, 'follow_announcement_channel');
    expect(find.text('#news now posts to #general in Beta.'), findsOneWidget);
  });
}

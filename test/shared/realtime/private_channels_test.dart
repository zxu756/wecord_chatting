import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecord/shared/realtime/private_channels.dart';

void main() {
  test('broadcast and presence channels are private', () {
    final config = privateChannelConfig().toMap()['config'] as Map;
    expect(config['private'], isTrue);
  });

  test('the presence key is kept', () {
    final config =
        privateChannelConfig(presenceKey: 'user-1').toMap()['config'] as Map;
    expect(config['private'], isTrue);
    expect((config['presence'] as Map)['key'], 'user-1');
  });

  test('topics are the ones the realtime.messages policies expect', () {
    const id = '00000000-0000-4000-8000-0000000000a1';
    expect(presenceUpdatesTopic(id), 'presence-updates:$id');
    expect(chatActivityTopic(id), 'chat-activity-$id');
    expect(notePresenceTopic(id), 'note-presence-$id');
    expect(liveLocationTopic(id), 'live-location:$id');
    expect(momentsTopic(id), 'moments:$id');
  });

  test('the policies name the same topic formats', () {
    final sql = File(
      'supabase/migrations/202610190050_realtime_private.sql',
    ).readAsStringSync();
    expect(sql, contains("'chat-activity-'"));
    expect(sql, contains("'note-presence-'"));
    final presence = File(
      'supabase/migrations/202610190070_presence_visibility.sql',
    ).readAsStringSync();
    expect(presence, contains("'presence-updates:'"));
    // The global channel's policies are dropped, and nothing joins it.
    final dropped = File(
      'supabase/migrations/202610190071_drop_online_users_policy.sql',
    ).readAsStringSync();
    expect(dropped, contains('drop policy if exists online_users_receive'));
    expect(dropped, contains('drop policy if exists online_users_send'));
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dart')) {
        expect(
          entity.readAsStringSync(),
          isNot(contains("'online-users'")),
          reason: entity.path,
        );
      }
    }
  });

  // Every channel that carries broadcast or presence goes through
  // privateChannelConfig, so "Allow public access" can stay off. A channel
  // written with a bare RealtimeChannelConfig would be public. (Channels that
  // only carry postgres_changes take no options and are guarded by the row
  // level security of their tables.)
  test('no channel with broadcast or presence is opened public', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      if (entity.path.endsWith('shared/realtime/private_channels.dart')) {
        continue;
      }
      final source = entity.readAsStringSync();
      if (source.contains('RealtimeChannelConfig(')) {
        offenders.add('${entity.path}: builds its own RealtimeChannelConfig');
      }
      final usesBroadcastOrPresence = RegExp(
        r'\.(onBroadcast|onPresenceSync|onPresenceJoin|onPresenceLeave|'
        r'sendBroadcastMessage|track)\(',
      ).hasMatch(source);
      if (usesBroadcastOrPresence &&
          !source.contains('privateChannelConfig(')) {
        offenders.add('${entity.path}: broadcast or presence, not private');
      }
    }
    expect(offenders, isEmpty);
  });
}

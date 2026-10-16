import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for the backend fixes (202610160034 onwards).
void main() {
  String migration(String prefix) {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere(
          (file) => file.uri.pathSegments.last.startsWith(prefix),
          orElse: () => throw StateError('Missing migration $prefix'),
        );
    return file.readAsStringSync();
  }

  String functionBody(String sql, String name) {
    final match = RegExp(
      'create or replace function public\\.$name\\s*\\([\\s\\S]*?\\n\\\$\\\$;',
    ).allMatches(sql);
    expect(match, isNotEmpty, reason: 'Missing function $name');
    return match.last.group(0)!;
  }

  test('bots: no friend requests, friendships or mutual friends', () {
    final sql = migration('202610160034');

    final guard = functionBody(sql, 'reject_friendship_with_bot');
    expect(guard, contains('p.is_bot'));
    expect(guard, contains("errcode = '42501'"));
    expect(
      sql,
      contains(
        'before insert on public.friend_requests\n'
        '  for each row execute function public.reject_friendship_with_bot();',
      ),
    );
    expect(
      sql,
      contains(
        'before insert on public.friendships\n'
        '  for each row execute function public.reject_friendship_with_bot();',
      ),
    );
    expect(
      functionBody(sql, 'list_friends_with_aliases'),
      contains('and not p.is_bot'),
    );
    final summary = functionBody(sql, 'get_profile_summary');
    expect(summary, contains('and not p.is_bot'));
    expect(summary, contains("when p.is_bot then 'bot'"));
  });

  test('AutoMod drops refused stickers, polls, forwards and posts', () {
    final sql = migration('202610160035');
    for (final name in [
      'send_sticker',
      'forward_message',
      'create_poll',
      'create_forum_post',
    ]) {
      final body = functionBody(sql, name);
      expect(
        body,
        contains("perform set_config('wecord.automod_soft', 'on', true);"),
        reason: name,
      );
      expect(
        body,
        contains("perform set_config('wecord.automod_soft', 'off', true);"),
        reason: name,
      );
    }
    final post = functionBody(sql, 'create_forum_post');
    expect(post, contains('if created_message_id is null then'));
    expect(
      post,
      contains(
        'delete from public.conversations c where c.id = created_conversation_id;',
      ),
    );
    expect(post, contains("'automod_blocked', true"));
  });

  test('voice tokens wait for the circle rules', () {
    final sql = migration('202610160036');
    final body = functionBody(sql, 'can_current_user_connect_voice');
    expect(
      body,
      contains(
        'if public.circle_member_needs_rules(channel.circle_id, auth.uid()) then\n'
        '    return null;',
      ),
    );
    // Still the stage-aware definition of 202610160018.
    expect(body, contains("'stage_speaker', channel.kind = 'stage'"));
  });

  test('webhooks post into announcement channels', () {
    final sql = migration('202610160037');
    final body = functionBody(sql, 'create_channel_webhook');
    expect(
      body,
      contains("if channel.kind not in ('text', 'announcement') then"),
    );
    expect(body, isNot(contains("if channel.kind <> 'text' then")));
    // Publishing stays manual.
    expect(sql, isNot(contains('publish_message(')));
  });
}

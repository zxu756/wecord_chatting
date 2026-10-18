import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Moments push (migration 202610190021): the claim function, the switch,
/// and the dispatcher wake-up, plus the behaviour script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610190021_moments_push.sql',
    ).readAsStringSync();
  });

  test('claims are for the service role only', () {
    expect(
      sql,
      contains(
        'revoke execute on function public.claim_moments_pushes(uuid, uuid) from public, anon, authenticated;',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.claim_moments_pushes(uuid, uuid) to service_role;',
      ),
    );
  });

  test('a push is claimed once and the visibility rules are re-checked', () {
    expect(sql, contains('set pushed_at = now()'));
    expect(sql, contains('n.pushed_at is null'));
    expect(sql, contains('moments_post_visible_to(c.user_id, p)'));
    expect(sql, contains('moments_interaction_visible('));
  });

  test('Do Not Disturb and the Moments switch are respected', () {
    expect(sql, contains("coalesce(ups.presence_status, 'online') <> 'dnd'"));
    expect(sql, contains('coalesce(ms.push_enabled, true)'));
  });

  test('the push is written in the language of the subscription', () {
    expect(sql, contains("s.language = 'zh'"));
    expect(sql, contains('赞了你的朋友圈'));
    expect(sql, contains(' liked your Moment'));
  });

  test('new posts never push', () {
    expect(sql, isNot(contains('moments_posts_push')));
    expect(sql, isNot(contains("kind = 'post'")));
  });

  test('the dispatcher wakes the function for waiting Moments pushes', () {
    expect(sql, contains('create or replace function public.run_later_dispatch'));
    expect(sql, contains('from public.moments_notifications mn'));
    // Everything the 202610170070 version looked at is still there.
    for (final table in [
      'scheduled_messages',
      'message_reminders',
      'chat_event_reminders',
      'task_items',
      'recalled_message_media',
    ]) {
      expect(sql, contains('public.$table'));
    }
  });

  behaviourTest(
    'moments push: likes, comments and replies, once, only what is visible',
    'test/supabase/moments_push_behaviour.sql',
  );
}

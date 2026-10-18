import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Moments live (migration 202610190020): signals, not data. Schema checks
/// plus the behaviour script (who is told, who may listen).
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610190020_moments_realtime.sql',
    ).readAsStringSync();
  });

  test('nothing of Moments is published to postgres_changes', () {
    expect(sql, isNot(contains('alter publication')));
    expect(sql, isNot(contains('supabase_realtime')));
  });

  test('signals go out on a private channel of the recipient only', () {
    expect(sql, contains("'moments:' || recipient::text"));
    expect(sql, contains('      true\n'));
    expect(
      sql,
      contains("(select realtime.topic()) = 'moments:' || (select auth.uid())"),
    );
    expect(sql, contains('on realtime.messages for select'));
    expect(sql, isNot(contains('realtime.messages for insert')));
  });

  test('the payload is only the post id', () {
    expect(sql, contains("jsonb_build_object('post_id', target_post)"));
  });

  test('the senders are not callable by the app', () {
    for (final signature in [
      'moments_signal(uuid, text, uuid)',
      'moments_signal_reaction(uuid, uuid, uuid)',
      'moments_signal_like()',
      'moments_signal_comment()',
    ]) {
      expect(
        sql,
        contains(
          'revoke execute on function public.$signature from public, anon, authenticated;',
        ),
      );
    }
  });

  behaviourTest(
    'moments live: who is told of posts, likes and comments, who may listen',
    'test/supabase/moments_live_behaviour.sql',
  );
}

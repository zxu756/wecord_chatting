import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Topics and circle posts 2.0 (B8: migrations 202610280700 to 202610280770):
/// what the SQL says, as text, plus the behaviour script that plays people
/// through it against the local database.
void main() {
  final names = [
    '202610280700_hashtags_schema.sql',
    '202610280710_circle_posts_rpcs.sql',
    '202610280720_circle_posts_read.sql',
    '202610280730_moments_hashtags.sql',
    '202610280740_posts_guard.sql',
    '202610280750_featured_posts_tab.sql',
    '202610280760_featured_push.sql',
    '202610280770_hashtags_account.sql',
  ];
  late Map<String, String> sql;
  late String all;

  setUpAll(() {
    sql = {
      for (final name in names)
        name: File('supabase/migrations/$name').readAsStringSync(),
    };
    all = sql.values.join('\n');
  });

  group('numbering and what is left alone', () {
    test('the migrations are in this package\'s range, ten apart', () {
      final numbers = [
        for (final name in names) int.parse(name.substring(0, 12)),
      ];
      for (var i = 0; i < numbers.length; i++) {
        expect(numbers[i], 202610280700 + i * 10);
      }
      expect(numbers.last, lessThan(202610280800));
    });

    test('run_later_dispatch and the cron jobs are not touched', () {
      expect(
        all,
        isNot(
          contains('create or replace function public.run_later_dispatch('),
        ),
      );
      expect(all, isNot(contains('cron.schedule')));
      expect(all, contains('wake_scheduled_dispatch'));
    });

    test('existing functions are only patched in place', () {
      for (final old in [
        'get_circle_detail',
        'list_saved_items',
        'report_snapshot',
        'moments_feed',
        'guard_item_text',
        'guard_items_after_write',
        'conversation_tab_target_ok',
        'get_conversation_tabs',
        'prepare_account_deletion',
        'forum_post_payload',
        'message_search_entries',
      ]) {
        expect(
          all,
          isNot(contains('create or replace function public.$old(')),
          reason: old,
        );
      }
      for (final name in [
        '202610280720_circle_posts_read.sql',
        '202610280730_moments_hashtags.sql',
        '202610280740_posts_guard.sql',
        '202610280750_featured_posts_tab.sql',
      ]) {
        expect(sql[name], contains('pg_get_functiondef'), reason: name);
      }
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('the old three-argument create_circle_post is replaced', () {
      expect(
        sql['202610280710_circle_posts_rpcs.sql'],
        contains('drop function if exists public.create_circle_post('),
      );
    });
  });

  group('the new functions are guarded', () {
    test('RPCs check the caller and the take-down', () {
      final rpcs = sql['202610280710_circle_posts_rpcs.sql']!;
      expect(rpcs, contains('auth.uid()'));
      expect(rpcs, contains('circle_is_suspended'));
      expect(rpcs, contains("'manage_messages'"));
      expect(rpcs, contains('security definer'));
      expect(rpcs, contains('set search_path = public'));
    });

    test('the push is service-only, honours blocks and the language', () {
      final push = sql['202610280760_featured_push.sql']!;
      expect(
        push,
        contains(
          'revoke execute on function public.claim_featured_post_pushes()',
        ),
      );
      expect(push, contains('to service_role'));
      expect(push, contains('are_users_blocked'));
      expect(push, contains("'zh'"));
    });

    test('topics respect the Moments visibility rules', () {
      final moments = sql['202610280730_moments_hashtags.sql']!;
      expect(moments, contains('moments_post_visible_to'));
      expect(moments, contains('hide_theirs'));
      expect(moments, contains('disabled_mode'));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/hashtags_behaviour.sql',
  );
}

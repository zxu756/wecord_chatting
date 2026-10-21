import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Member titles and honors (C7: migrations 202610270200 to 202610270240):
/// what the SQL says, as text, plus the behaviour script that plays people
/// through it against the local database.
void main() {
  late String schema;
  late String titles;
  late String compute;
  late String rpcs;
  late String export;

  setUpAll(() {
    String read(String name) =>
        File('supabase/migrations/$name').readAsStringSync();
    schema = read('202610270200_member_honors_schema.sql');
    titles = read('202610270210_member_titles.sql');
    compute = read('202610270220_member_honors_compute.sql');
    rpcs = read('202610270230_member_honors_rpcs.sql');
    export = read('202610270240_member_honors_export.sql');
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('what is stored', () {
    test('a title is short and plain; honors count days, not messages', () {
      expect(schema, contains('char_length(title) between 1 and 10'));
      expect(schema, contains("kind in ('weekly', 'streak')"));
      expect(schema, contains('level in (7, 30, 100)'));
      expect(schema, isNot(contains('message_count')));
      expect(compute, contains('circle_member_daily'));
      expect(compute, isNot(contains('public.messages')));
    });

    test('everything is closed to clients', () {
      for (final table in [
        'circle_honor_prefs',
        'circle_member_honors',
        'circle_member_honor_stats',
        'circle_title_notices',
      ]) {
        expect(
          schema,
          contains('alter table public.$table enable row level security;'),
          reason: table,
        );
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated;',
          ),
          reason: table,
        );
      }
      expect(schema, isNot(contains('create policy')));
    });

    test('leaving and deleting an account erase it', () {
      expect(schema, contains('create trigger circle_members_forget_honors'));
      expect(schema, contains('after delete on public.circle_members'));
      expect(schema, contains('create trigger profiles_erase_honors'));
      expect(schema, contains('after update of deleted_at on public.profiles'));
      final erase = body(schema, 'erase_honors_of_deleted_account');
      for (final table in [
        'circle_member_honors',
        'circle_member_honor_stats',
        'circle_honor_prefs',
        'circle_title_notices',
      ]) {
        expect(erase, contains('delete from public.$table'), reason: table);
      }
      expect(erase, contains('set title = null'));
    });
  });

  group('titles', () {
    test('follow the nickname rules and the K1 take-down', () {
      final set = body(titles, 'set_circle_member_title');
      expect(set, contains("'manage_nicknames'"));
      expect(set, contains('circle_member_rank'));
      expect(set, contains('assert_circle_up'));
      expect(set, contains('is_user_suspended'));
      expect(set, contains("'member_title_update'"));
      expect(set, contains('wake_scheduled_dispatch'));
      // Angle brackets, controls, invisible and direction characters.
      expect(set, contains(r'\\u202a-\\u202e'));
      expect(set, contains(r'\\u200b-\\u200f'));
    });

    test('the grants', () {
      expect(
        titles,
        contains(
          'revoke execute on function public.set_circle_member_title(uuid, uuid, text)\n  from public, anon;',
        ),
      );
      expect(
        titles,
        contains(
          'grant execute on function public.set_circle_member_title(uuid, uuid, text)\n  to authenticated;',
        ),
      );
      expect(titles, isNot(contains('to anon')));
      expect(
        titles,
        contains(
          'grant execute on function public.claim_circle_title_pushes() to service_role;',
        ),
      );
    });

    test('the push is worded in both languages and cleans names', () {
      final push = body(titles, 'claim_circle_title_pushes');
      expect(push, contains("s.language = 'zh'"));
      expect(push, contains('你有新头衔了'));
      expect(push, contains("replace(replace(c.title, '<', ''), '>', '')"));
    });
  });

  group('honors', () {
    test('only circles with five people work them out', () {
      expect(compute, contains('>= 5'));
      expect(titles, contains(') >= 5;'));
      expect(compute, contains('c.honors_enabled'));
      expect(compute, contains('c.disabled_at is null'));
      expect(compute, contains('circle_honor_prefs'));
    });

    test('has its own cron job and leaves the dispatcher alone', () {
      expect(compute, contains("'wecord-circle-honors'"));
      expect(compute, contains("'40 0 * * *'"));
      for (final sql in [schema, titles, compute, rpcs, export]) {
        expect(
          sql,
          isNot(
            contains('create or replace function public.run_later_dispatch'),
          ),
        );
        expect(
          sql,
          isNot(contains('function public.aggregate_circle_insights')),
        );
      }
    });

    test('the page is for members, the switch for moderators', () {
      expect(
        body(rpcs, 'set_circle_honors_enabled'),
        contains("'manage_circle'"),
      );
      expect(
        body(rpcs, 'set_circle_honors_enabled'),
        contains('assert_circle_up'),
      );
      expect(
        body(rpcs, 'set_my_honors_participation'),
        contains('assert_circle_up'),
      );
      expect(body(rpcs, 'get_circle_honors'), contains('circle_is_suspended'));
      expect(rpcs, isNot(contains('to anon')));
    });

    test('another member\'s numbers are never in the answer', () {
      final page = body(rpcs, 'get_circle_honors');
      // The board has user ids and levels, nothing else about other people.
      expect(
        page,
        contains("jsonb_build_object('user_id', h.user_id, 'level', h.level)"),
      );
      expect(page, contains('honors_board_published'));
      final flair = body(titles, 'list_circle_member_flair');
      expect(flair, contains('honors_board_published'));
      expect(flair, contains('circle_honor_prefs'));
    });
  });

  group('exporting', () {
    test('the export is closed to clients', () {
      expect(
        export,
        contains(
          'grant execute on function public.export_my_honors(uuid) to service_role;',
        ),
      );
      expect(
        export,
        contains(
          'revoke execute on function public.export_my_honors(uuid)\n  from public, anon, authenticated;',
        ),
      );
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/member_honors_behaviour.sql',
  );
}

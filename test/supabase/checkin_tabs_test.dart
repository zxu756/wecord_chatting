import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Group check-in (D3: migrations 202610280500 to 202610280530) and group
/// tabs (D8: 202610280540 to 202610280560): what the SQL says, as text, plus
/// the behaviour script that plays people through it against the local
/// database.
void main() {
  final names = [
    '202610280500_checkin_schema.sql',
    '202610280510_checkin_rpcs.sql',
    '202610280520_checkin_push.sql',
    '202610280530_checkin_account.sql',
    '202610280540_group_tabs_schema.sql',
    '202610280550_group_tabs_rpcs.sql',
    '202610280560_group_tabs_account.sql',
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

  String body(String name, String function) {
    final source = sql[name]!;
    final start = source.indexOf(
      'create or replace function public.$function(',
    );
    expect(start, isNonNegative, reason: function);
    return source.substring(start, source.indexOf('\n\$\$;', start));
  }

  group('numbering and what is left alone', () {
    test('the migrations are in this package\'s range, ten apart', () {
      final numbers = [
        for (final name in names) int.parse(name.substring(0, 12)),
      ];
      for (var i = 0; i < numbers.length; i++) {
        expect(numbers[i], 202610280500 + i * 10);
      }
      expect(numbers.last, lessThan(202610280600));
    });

    test('the every-minute dispatcher is not redefined', () {
      expect(all, isNot(contains('function public.run_later_dispatch')));
      expect(all, isNot(contains('run_later_dispatch()')));
    });

    test('no function other packages patched is rewritten', () {
      for (final name in [
        'guard_item_text',
        'guard_items_after_write',
        'prepare_account_deletion',
        'list_read_reminder_notices',
        'is_current_user_conversation_member',
        'can_current_user_pin_messages',
        'chain_note_needs_review',
        'chain_card_visible',
      ]) {
        expect(
          all,
          isNot(contains('create or replace function public.$name(')),
          reason: name,
        );
      }
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('every function is security definer with a fixed search path', () {
      for (final MapEntry(:key, :value) in sql.entries) {
        final functions = RegExp(
          r'create or replace function public\.(\w+)\(([\s\S]*?)\n\$\$;',
        ).allMatches(value);
        for (final match in functions) {
          final text = match.group(0)!;
          final name = match.group(1)!;
          // Plain helpers that read nothing of the caller's.
          if (const {
            'check_in_local_day',
            'check_in_clean_zone',
            'check_in_today',
            'check_in_is_closed',
            'check_in_live_streak',
          }.contains(name)) {
            continue;
          }
          expect(
            text,
            contains('security definer'),
            reason: '$name in $key is security definer',
          );
          expect(
            text,
            contains('set search_path = public'),
            reason: '$name in $key sets its search path',
          );
        }
      }
    });

    test('the tables are closed to clients, which only read', () {
      final schema = sql['202610280500_checkin_schema.sql']!;
      for (final table in [
        'check_in_boards',
        'check_in_entries',
        'check_in_streaks',
        'check_in_notices',
      ]) {
        expect(schema, contains('alter table public.$table enable row level security'));
        expect(schema, contains('revoke all on public.$table from anon, authenticated'));
      }
      expect(schema, contains('grant select on public.check_in_boards to authenticated'));
      expect(schema, isNot(contains('grant insert')));
      expect(schema, isNot(contains('grant update')));
      final tabs = sql['202610280540_group_tabs_schema.sql']!;
      expect(tabs, contains('grant select on public.conversation_tabs to authenticated'));
      expect(tabs, isNot(contains('grant insert')));
    });
  });

  group('check-in', () {
    test('a day is a day of the zone the maker was in', () {
      final schema = sql['202610280500_checkin_schema.sql']!;
      expect(schema, contains('time_zone text not null default \'UTC\''));
      expect(
        body('202610280500_checkin_schema.sql', 'check_in_local_day'),
        contains('at time zone coalesce(nullif(zone'),
      );
      // An unknown zone counts as UTC, it does not fail.
      expect(
        body('202610280500_checkin_schema.sql', 'check_in_clean_zone'),
        contains('pg_timezone_names'),
      );
    });

    test('one entry per person per day, edited by the same call', () {
      expect(
        sql['202610280500_checkin_schema.sql'],
        contains('unique (board_id, user_id, day)'),
      );
      final submit = body('202610280510_checkin_rpcs.sql', 'submit_check_in');
      expect(submit, contains('on conflict (board_id, user_id, day) do update'));
    });

    test('the run is worked out from the days by a trigger', () {
      final schema = sql['202610280500_checkin_schema.sql']!;
      expect(schema, contains('row_number() over (order by e.day)'));
      expect(schema, contains('after insert or update or delete on public.check_in_entries'));
      // A run is alive while its last day is today or yesterday.
      expect(
        body('202610280500_checkin_schema.sql', 'check_in_live_streak'),
        contains('last_day >= today - 1'),
      );
    });

    test('a check-in follows its card and its chat', () {
      final schema = sql['202610280500_checkin_schema.sql']!;
      expect(schema, contains('check_in_card_visible'));
      expect(schema, contains('public.chain_card_visible(card_message_id)'));
      final rpcs = sql['202610280510_checkin_rpcs.sql']!;
      expect(rpcs, contains('chain_conversation_allowed'));
      expect(rpcs, contains('can_current_user_send_in_conversation'));
      expect(rpcs, contains('is_current_user_blocked_in_conversation'));
      expect(rpcs, contains('chain_note_needs_review'));
      expect(rpcs, contains('are_users_blocked'));
      expect(rpcs, contains('is_user_suspended'));
    });

    test('a picture is a file of the check-in folder, uploaded by the caller', () {
      final submit = body('202610280510_checkin_rpcs.sql', 'submit_check_in');
      expect(submit, contains("/check-ins/"));
      expect(submit, contains('storage.objects'));
      expect(submit, contains('o.owner = uid'));
    });

    test('a check-in in a circle channel is a day of activity for C3/C7', () {
      final submit = body('202610280510_checkin_rpcs.sql', 'submit_check_in');
      expect(submit, contains('insert into public.circle_member_daily'));
      expect(submit, contains('on conflict do nothing'));
    });

    test('the reminder is a job of its own, every five minutes', () {
      final push = sql['202610280520_checkin_push.sql']!;
      expect(push, contains("'wecord-check-in-sweep'"));
      expect(push, contains("'*/5 * * * *'"));
      expect(push, contains("pg_extension where extname = 'pg_cron'"));
      expect(push, contains('perform public.wake_scheduled_dispatch()'));
      // Once per board per day, and not for a stale time.
      expect(push, contains('last_reminded_on'));
      expect(push, contains('b.remind_minute + 180'));
    });

    test('the push is worded for the device and respects mutes and K1', () {
      final claim = body('202610280520_checkin_push.sql', 'claim_check_in_pushes');
      expect(claim, contains("s.language = 'zh'"));
      expect(claim, contains('今天还没打卡'));
      expect(claim, contains('muted_until'));
      expect(claim, contains("disabled_mode is distinct from 'suspend'"));
      expect(claim, contains('circle_notification_settings'));
      // The row carries its chat, so locked chats and quiet hours apply.
      expect(claim, contains('notice_conversation_id'));
      expect(claim, contains("interval '30 minutes'"));
    });

    test('deleting an account erases the check-ins, the data export has them', () {
      final account = sql['202610280530_checkin_account.sql']!;
      expect(account, contains('profiles_erase_check_ins'));
      expect(account, contains('delete from public.check_in_entries where user_id = new.id'));
      expect(account, contains('grant execute on function public.export_my_check_ins(uuid) to service_role'));
      expect(account, contains('revoke execute on function public.export_my_check_ins(uuid)'));
    });
  });

  group('group tabs', () {
    test('only groups and circle channels have tabs', () {
      expect(
        body('202610280550_group_tabs_rpcs.sql', 'conversation_tabs_allowed'),
        contains("c.type in ('group', 'channel')"),
      );
    });

    test('the people who can pin messages change the tabs', () {
      final rpcs = sql['202610280550_group_tabs_rpcs.sql']!;
      expect('can_current_user_pin_messages'.allMatches(rpcs).length, greaterThanOrEqualTo(5));
      for (final function in [
        'add_conversation_tab',
        'update_conversation_tab',
        'delete_conversation_tab',
        'reorder_conversation_tabs',
      ]) {
        expect(
          body('202610280550_group_tabs_rpcs.sql', function),
          contains('can_current_user_pin_messages'),
          reason: function,
        );
      }
    });

    test('a target has to be this chat\'s, a link http(s) only', () {
      final target = body('202610280550_group_tabs_rpcs.sql', 'conversation_tab_target_ok');
      expect(target, contains('n.conversation_id = p_conversation_id'));
      expect(target, contains('l.conversation_id = p_conversation_id'));
      expect(target, contains('f.conversation_id = p_conversation_id'));
      expect(target, contains('b.conversation_id = p_conversation_id'));
      expect(target, contains('^https?://'));
    });

    test('kinds are rows, so another package adds one with an insert', () {
      final schema = sql['202610280540_group_tabs_schema.sql']!;
      expect(schema, contains('create table if not exists public.conversation_tab_kinds'));
      expect(schema, contains("('space', 'none')"));
      expect(schema, contains("('check_in', 'id')"));
    });

    test('a tab goes with its target', () {
      final schema = sql['202610280540_group_tabs_schema.sql']!;
      for (final trigger in [
        'conversation_tabs_note_gone',
        'conversation_tabs_list_gone',
        'conversation_tabs_form_deleted',
        'conversation_tabs_check_in_deleted',
      ]) {
        expect(schema, contains(trigger));
      }
    });

    test('at most twelve tabs, none twice', () {
      final add = body('202610280550_group_tabs_rpcs.sql', 'add_conversation_tab');
      expect(add, contains(">= 12"));
      expect(add, contains("raise exception 'tab_exists'"));
      expect(add, contains("raise exception 'tab_limit'"));
    });

    test('deleting an account takes the name off the tabs, the export lists them', () {
      final account = sql['202610280560_group_tabs_account.sql']!;
      expect(account, contains('profiles_erase_group_tabs'));
      expect(account, contains('set created_by = null'));
      expect(account, contains('grant execute on function public.export_my_group_tabs(uuid) to service_role'));
    });
  });

  group('behaviour', () {
    behaviourTest(
      'check-in and group tabs against the local database',
      'test/supabase/checkin_tabs_behaviour.sql',
    );
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the moderator tools (C5) and raid protection (C6),
/// migrations 202610250200 to 202610250280, plus the behaviour script that
/// plays every permission branch, rank, expiry, lock, appeal, filter, batch and
/// lockdown through the RPCs.
void main() {
  late Map<String, String> sql;

  setUpAll(() {
    sql = {
      for (final name in const [
        '202610250200_ban_expiry',
        '202610250210_thread_lock',
        '202610250220_mod_notes',
        '202610250230_ban_appeals',
        '202610250240_member_filter_batch',
        '202610250250_raid_schema',
        '202610250260_raid_detect',
        '202610250270_raid_rpcs',
        '202610250280_moderation_push',
      ])
        name: File('supabase/migrations/$name.sql').readAsStringSync(),
    };
  });

  String body(String file, String name) {
    final text = sql[file]!;
    final start = text.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return text.substring(start, text.indexOf('\n\$\$;', start));
  }

  group('every new function is closed to the outside', () {
    test('definers pin the search path', () {
      for (final MapEntry(:key, :value) in sql.entries) {
        final functions = RegExp(
          r'create or replace function public\.(\w+)\(',
        ).allMatches(value);
        for (final match in functions) {
          final text = body(key, match.group(1)!);
          expect(
            text,
            contains('set search_path = public'),
            reason: '${match.group(1)} in $key',
          );
        }
      }
    });

    test('the tables are closed to clients', () {
      final all = sql.values.join('\n');
      for (final table in [
        'circle_mod_notes',
        'circle_ban_appeals',
        'circle_security',
        'circle_raid_events',
      ]) {
        expect(
          all,
          contains('alter table public.$table enable row level security'),
          reason: table,
        );
        expect(
          all,
          contains(
            'revoke all on public.$table from public, anon, authenticated',
          ),
          reason: table,
        );
      }
      expect(all, isNot(contains('grant select on public.circle_')));
    });

    test('internals are not callable by clients', () {
      expect(
        sql['202610250260_raid_detect']!,
        contains(
          'revoke execute on function public.start_circle_lockdown_internal(',
        ),
      );
      expect(
        sql['202610250260_raid_detect']!,
        contains(
          'grant execute on function public.run_circle_safety_sweep() to service_role',
        ),
      );
      expect(
        sql['202610250200_ban_expiry']!,
        contains(
          'grant execute on function public.expire_circle_bans() to service_role',
        ),
      );
      expect(
        sql['202610250280_moderation_push']!,
        contains(
          'grant execute on function public.claim_moderation_pushes() to service_role',
        ),
      );
    });
  });

  group('bans that end', () {
    test('ban_circle_member keeps what 202610140007 had', () {
      final ban = body('202610250200_ban_expiry', 'ban_circle_member');
      for (final kept in [
        "'ban_members'",
        'circle_member_rank(target_circle_id, target_user_id)',
        'The circle owner cannot be banned',
        "'chat-files'",
        'remove_circle_member_rows',
        'recalled_message_media',
        "'member_ban'",
      ]) {
        expect(ban, contains(kept), reason: kept);
      }
      expect(ban, contains('assert_circle_up'));
      expect(ban, contains('ban_duration_seconds'));
      // The four-argument call of the report queue still resolves.
      expect(ban, contains('ban_duration_seconds integer default null'));
    });

    test('ending is done by the clock and by the join guard', () {
      final file = sql['202610250200_ban_expiry']!;
      expect(file, contains('add column if not exists expires_at timestamptz'));
      expect(file, contains("'member_unban_auto'"));
      expect(
        body('202610250200_ban_expiry', 'reject_banned_circle_member'),
        contains('b.expires_at <= now()'),
      );
      // The one-minute job is its own; run_later_dispatch is not rewritten.
      for (final text in sql.values) {
        expect(text, isNot(contains('function public.run_later_dispatch')));
      }
      expect(
        sql['202610250260_raid_detect']!,
        contains("'wecord-circle-safety-sweep'"),
      );
    });
  });

  group('threads, notes, appeals', () {
    test('locking needs manage_messages in the channel and audits', () {
      final lock = body('202610250210_thread_lock', 'set_thread_locked');
      expect(lock, contains("'manage_messages'"));
      expect(lock, contains('assert_circle_up'));
      expect(lock, contains("'thread_lock'"));
      expect(lock, contains("'thread_unlock'"));
      final guard = body(
        '202610250210_thread_lock',
        'reject_locked_thread_message',
      );
      expect(guard, contains("detail = 'thread_locked'"));
      expect(guard, contains("new.type = 'system'"));
      expect(
        sql['202610250210_thread_lock']!,
        contains('before insert on public.messages'),
      );
    });

    test(
      'notes are for moderate_members, below their rank, and not logged in words',
      () {
        final check = body(
          '202610250220_mod_notes',
          'assert_can_moderate_member',
        );
        expect(check, contains("'moderate_members'"));
        expect(check, contains('circle_member_rank'));
        final add = body('202610250220_mod_notes', 'add_circle_mod_note');
        expect(add, contains("'mod_warn'"));
        expect(add, isNot(contains("'body'")));
      },
    );

    test('an appeal is one per ban, decided by ban_members, rank-checked', () {
      final file = sql['202610250230_ban_appeals']!;
      expect(file, contains('unique (circle_id, user_id, ban_created_at)'));
      final decide = body('202610250230_ban_appeals', 'decide_ban_appeal');
      expect(decide, contains("'ban_members'"));
      expect(
        decide,
        contains('Cannot overturn a ban by a member ranked above you'),
      );
      expect(decide, contains('assert_circle_up'));
      expect(decide, contains('wake_scheduled_dispatch'));
      expect(
        body('202610250230_ban_appeals', 'my_circle_bans'),
        isNot(contains('b.reason')),
      );
    });
  });

  group('filter and batch', () {
    test('batch goes through the single actions, at most 50', () {
      final batch = body(
        '202610250240_member_filter_batch',
        'batch_moderate_circle_members',
      );
      expect(batch, contains('timeout_circle_member'));
      expect(batch, contains('kick_circle_member'));
      expect(batch, contains('ban_circle_member'));
      expect(batch, contains('Up to 50 members at a time'));
      expect(batch, contains('exception when others then'));
      expect(batch, contains("'member_batch_action'"));
    });
  });

  group('raid protection', () {
    test('invites are paused on every invite path', () {
      final file = sql['202610250250_raid_schema']!;
      expect(
        file,
        contains(
          "when public.circle_invites_paused(invite_row.circle_id) then 'paused'",
        ),
      );
      expect(file, contains('before insert on public.circle_invites'));
      expect(
        file,
        contains(
          "pg_get_functiondef('public.invite_circle_members(uuid, uuid[])'::regprocedure)",
        ),
      );
      expect(file, contains('assert_circle_invites_open(target_circle_id)'));
    });

    test('the check waits for the commit and never raises', () {
      final file = sql['202610250260_raid_detect']!;
      expect(
        file,
        contains('create constraint trigger circle_members_raid_watch'),
      );
      expect(file, contains('deferrable initially deferred'));
      expect(
        file,
        contains('create constraint trigger circle_join_requests_raid_watch'),
      );
      final check = body('202610250260_raid_detect', 'circle_raid_check');
      expect(check, contains('exception when others then'));
      expect(check, contains("interval '1 hour'"));
    });

    test('every control checks who asks', () {
      final file = sql['202610250270_raid_rpcs']!;
      expect(file, contains("'kick_members'"));
      expect(file, contains("'manage_circle'"));
      for (final name in [
        'pause_circle_invites',
        'resume_circle_invites',
        'start_circle_lockdown',
        'end_circle_lockdown',
      ]) {
        expect(
          body('202610250270_raid_rpcs', name),
          contains('assert_can_run_circle_safety'),
          reason: name,
        );
      }
      expect(
        body('202610250270_raid_rpcs', 'set_circle_raid_settings'),
        contains("'manage_circle'"),
      );
    });

    test('newcomers cannot post links and the AI guard checks them', () {
      final trigger = body('202610250270_raid_rpcs', 'messages_review_raid');
      expect(trigger, contains("detail = 'raid_newcomer_links'"));
      expect(trigger, contains("new.review_state := 'checking'"));
      expect(trigger, contains('circle_ai_guard'));
    });
  });

  behaviourTest(
    'mod tools: bans that end, locks, notes, appeals, filter, batch and raid protection',
    'test/supabase/mod_tools_behaviour.sql',
  );
}

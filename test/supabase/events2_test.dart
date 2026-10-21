import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Events 2.0 (C10: migrations 202610270400 to 202610270470): what the SQL
/// says, as text, plus the behaviour script that plays people through it
/// against the local database.
void main() {
  final names = [
    '202610270400_events2_schema.sql',
    '202610270410_events2_chat_events.sql',
    '202610270420_events2_circle_events.sql',
    '202610270430_events2_sweep.sql',
    '202610270440_events2_checkin.sql',
    '202610270450_events2_photos.sql',
    '202610270460_events2_push_guard.sql',
    '202610270470_events2_account.sql',
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
        expect(numbers[i], 202610270400 + i * 10);
      }
      expect(numbers.last, lessThan(202610270500));
    });

    test('the every-minute dispatcher is not redefined', () {
      expect(all, isNot(contains('function public.run_later_dispatch')));
      expect(all, isNot(contains('run_later_dispatch()')));
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
      expect(all, isNot(contains('circle_event_profile(uuid, uuid)')));
      expect(
        all,
        isNot(
          contains('create or replace function public.circle_event_profile'),
        ),
      );
    });

    test(
      'the functions that other migrations patched are patched in place',
      () {
        final push = sql['202610270460_events2_push_guard.sql']!;
        expect(push, contains("p.proname = 'guard_item_text'"));
        expect(push, contains('pg_get_functiondef(target.oid)'));
        expect(push, contains('events2_question_labels'));
        expect(
          all,
          isNot(contains('create or replace function public.guard_item_text')),
        );
        expect(
          all,
          isNot(
            contains(
              'create or replace function public.guard_items_after_write',
            ),
          ),
        );
        expect(
          push,
          contains('execute function public.guard_items_after_write()'),
        );
      },
    );

    test('rewritten functions say which migration they come from', () {
      expect(
        sql['202610270410_events2_chat_events.sql'],
        contains('202610170050_chat_events.sql'),
      );
      expect(
        sql['202610270420_events2_circle_events.sql'],
        contains('202610130022_circle_events.sql'),
      );
    });

    test('the old signatures are dropped so a named call is not ambiguous', () {
      final chat = sql['202610270410_events2_chat_events.sql']!;
      for (final signature in [
        'create_chat_event(\n  uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean\n)',
        'cancel_chat_event(uuid)',
        'rsvp_chat_event(uuid, text)',
      ]) {
        expect(chat, contains('drop function if exists public.$signature'));
      }
      final circle = sql['202610270420_events2_circle_events.sql']!;
      expect(
        circle,
        contains('drop function if exists public.cancel_circle_event(uuid);'),
      );
    });
  });

  group('repeating', () {
    test('the next start is worked out on the wall clock of the zone', () {
      final next = body(
        '202610270400_events2_schema.sql',
        'events2_next_start',
      );
      expect(next, contains('at time zone zone'));
      expect(next, contains("step * interval '7 days'"));
      expect(next, contains("step * interval '14 days'"));
      expect(next, contains("step * interval '1 month'"));
      // From the anchor, not from the last start.
      expect(next, contains('local_anchor'));
    });

    test('the sweep is a job of its own, every five minutes', () {
      final sweep = sql['202610270430_events2_sweep.sql']!;
      expect(sweep, contains("'wecord-events2-sweep'"));
      expect(sweep, contains("'*/5 * * * *'"));
      expect(sweep, contains("pg_extension where extname = 'pg_cron'"));
    });

    test('a suspended circle or organiser pauses a series (K1)', () {
      final spawn = body(
        '202610270430_events2_sweep.sql',
        'events2_spawn_next',
      );
      expect(spawn, contains('circle_is_suspended(circle_src.circle_id)'));
      expect(spawn, contains('is_user_suspended(chat_src.created_by)'));
    });

    test('the spawn works for the cron user, so the guard skips it', () {
      // guard_items_after_write returns early without a signed-in person.
      final spawn = body(
        '202610270430_events2_sweep.sql',
        'events2_spawn_next',
      );
      expect(spawn, isNot(contains('auth.uid()')));
    });
  });

  group('taking down (K1)', () {
    test('circle events refuse organisers and members as decided', () {
      final circle = sql['202610270420_events2_circle_events.sql']!;
      for (final fn in [
        'create_circle_event',
        'update_circle_event',
        'cancel_circle_event',
      ]) {
        expect(
          body('202610270420_events2_circle_events.sql', fn),
          contains('events2_assert_circle_open'),
          reason: fn,
        );
      }
      expect(
        circle,
        contains('events2_assert_circle_open(event_row.circle_id, false)'),
      );
      final assertFn = body(
        '202610270400_events2_schema.sql',
        'events2_assert_circle_open',
      );
      expect(assertFn, contains('is_user_suspended(auth.uid())'));
      expect(assertFn, contains('circle_is_suspended(p_circle_id)'));
      expect(assertFn, contains('c.disabled_at is not null'));
    });

    test('leaving an event stays open in a suspended circle', () {
      final unregister = body(
        '202610270420_events2_circle_events.sql',
        'unregister_circle_event',
      );
      expect(unregister, isNot(contains('events2_assert_circle_open')));
    });

    test('a suspended account writes no chat events', () {
      final check = body(
        '202610270410_events2_chat_events.sql',
        'chat_event_check_conversation',
      );
      expect(check, contains('is_user_suspended(auth.uid())'));
    });

    test('the push is not sent for a suspended circle', () {
      final push = body(
        '202610270460_events2_push_guard.sql',
        'claim_event_notice_pushes',
      );
      expect(push, contains("ci.disabled_mode is distinct from 'suspend'"));
    });
  });

  group('who may do what', () {
    test('every table is closed to clients', () {
      final schema = sql['202610270400_events2_schema.sql']!;
      for (final table in [
        'event_waitlist',
        'event_check_in_codes',
        'event_check_ins',
        'event_photos',
        'event_notices',
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
      expect(all, isNot(contains('create policy')));
    });

    test('the check-in code is stored as a hash and expires', () {
      final create = body(
        '202610270440_events2_checkin.sql',
        'create_event_check_in_code',
      );
      expect(
        create,
        contains("encode(sha256(convert_to(new_code, 'UTF8')), 'hex')"),
      );
      expect(create, contains("scope.effective_ends_at + interval '3 hours'"));
      expect(create, contains('revoked_at = now()'));
      final scan = body('202610270440_events2_checkin.sql', 'check_in_event');
      expect(scan, contains('code_row.revoked_at is not null'));
      expect(scan, contains('code_row.expires_at <= now()'));
      expect(scan, contains("interval '2 hours'"));
      expect(scan, contains('event_waitlist'));
      expect(
        sql['202610270400_events2_schema.sql'],
        contains('code_hash text not null unique'),
      );
    });

    test('the organiser\'s list needs manage mode', () {
      final list = body(
        '202610270440_events2_checkin.sql',
        'list_event_registrations',
      );
      expect(list, contains("'manage'"));
      final scope = body(
        '202610270440_events2_checkin.sql',
        'events2_event_scope',
      );
      expect(scope, contains('can_manage_chat_event'));
      expect(scope, contains("'manage_events'"));
      expect(
        scope,
        contains('circle_row.created_by is not distinct from auth.uid()'),
      );
    });

    test('photos live in the folder of the chat or the circle', () {
      final add = body('202610270450_events2_photos.sql', 'add_event_photo');
      expect(add, contains("'chat-images'"));
      expect(add, contains("'chat-media'"));
      expect(add, contains("scope.scope_id::text || '/%'"));
      expect(add, contains("p_path ~ '\\.\\.'"));
      expect(add, contains('storage.objects'));
      expect(add, contains('>= 20'));
      expect(add, contains('>= 300'));
      final list = body('202610270450_events2_photos.sql', 'list_event_photos');
      expect(list, contains('are_users_blocked'));
    });

    test('a cover must be in the same folder', () {
      final merge = body(
        '202610270400_events2_schema.sql',
        'events2_merge_options',
      );
      expect(merge, contains("p_scope_id::text || '/%'"));
      expect(merge, contains("~ '\\.\\.'"));
    });

    test('grants: members call the RPCs, only the service role the batch ones', () {
      expect(
        all,
        contains(
          'grant execute on function public.check_in_event(text) to authenticated;',
        ),
      );
      expect(
        sql['202610270430_events2_sweep.sql'],
        contains(
          'grant execute on function public.events2_sweep() to service_role;',
        ),
      );
      expect(
        sql['202610270460_events2_push_guard.sql'],
        contains(
          'grant execute on function public.claim_event_notice_pushes() to service_role;',
        ),
      );
      expect(
        sql['202610270470_events2_account.sql'],
        contains(
          'grant execute on function public.export_my_events2(uuid) to service_role;',
        ),
      );
      expect(
        all,
        isNot(contains('grant execute on function public.events2_promote')),
      );
    });
  });

  group('the push', () {
    test('is worded in both languages with a time token', () {
      final push = body(
        '202610270460_events2_push_guard.sql',
        'claim_event_notice_pushes',
      );
      expect(push, contains("s.language = 'zh'"));
      expect(push, contains('你已报名成功'));
      expect(push, contains("'You got a seat'"));
      expect(push, contains(':f>'));
      expect(push, contains("replace(replace(e.title, '<', ''), '>', '')"));
    });

    test('respects muting and takes notices only once', () {
      final push = body(
        '202610270460_events2_push_guard.sql',
        'claim_event_notice_pushes',
      );
      expect(push, contains('cm.muted_until'));
      expect(push, contains("coalesce(ns.level, 'all') <> 'none'"));
      expect(push, contains("interval '15 minutes'"));
      expect(push, contains('push_claimed_at is null'));
    });

    test('moving someone up wakes the dispatcher', () {
      final promote = body(
        '202610270400_events2_schema.sql',
        'events2_promote',
      );
      expect(promote, contains('wake_scheduled_dispatch()'));
      expect(promote, contains('circle_channel_has_permission'));
    });
  });

  group('account and export', () {
    test('deleting an account erases what Events 2.0 holds', () {
      final account = sql['202610270470_events2_account.sql']!;
      final erase = body(
        '202610270470_events2_account.sql',
        'erase_events2_of_deleted_account',
      );
      for (final table in [
        'event_waitlist',
        'event_check_ins',
        'event_photos',
        'event_check_in_codes',
        'event_notices',
      ]) {
        expect(erase, contains('delete from public.$table'), reason: table);
      }
      expect(erase, contains("set answers = '{}'::jsonb"));
      expect(
        account,
        contains('after update of deleted_at on public.profiles'),
      );
      expect(
        account,
        isNot(contains('function public.prepare_account_deletion')),
      );
    });

    test('the export holds only the person\'s own', () {
      final export = body(
        '202610270470_events2_account.sql',
        'export_my_events2',
      );
      expect(export, contains('r.user_id = target_user_id'));
      expect(export, contains('w.user_id = target_user_id'));
      expect(export, contains('ci.user_id = target_user_id'));
      expect(export, contains('ph.user_id = target_user_id'));
      expect(export, contains('e.created_by = target_user_id'));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/events2_behaviour.sql',
  );
}

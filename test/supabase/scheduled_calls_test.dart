import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Scheduled calls (E2: migrations 202610280100 to 202610280140): what the SQL
/// says, as text, plus the behaviour script that plays people through it
/// against the local database.
void main() {
  final names = [
    '202610280100_scheduled_calls_schema.sql',
    '202610280110_scheduled_calls_events.sql',
    '202610280120_scheduled_calls_push.sql',
    '202610280130_scheduled_calls_agenda.sql',
    '202610280140_scheduled_calls_account.sql',
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
        expect(numbers[i], 202610280100 + i * 10);
      }
      expect(numbers.last, lessThan(202610280200));
    });

    test('the every-minute dispatcher and the sweep are not redefined', () {
      expect(all, isNot(contains('function public.run_later_dispatch')));
      expect(all, isNot(contains('function public.events2_spawn_next')));
      expect(all, isNot(contains('function public.events2_sweep')));
      expect(all, isNot(contains('function public.wake_scheduled_dispatch')));
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('the functions other migrations rewrote are patched in place', () {
      final events = sql['202610280110_scheduled_calls_events.sql']!;
      for (final signature in [
        'chat_event_json(public.chat_events)',
        'create_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], boolean, jsonb)',
        'update_chat_event(uuid, text, timestamptz, timestamptz, text, text, text, integer[], jsonb)',
      ]) {
        expect(events, contains("'public.$signature'::regprocedure"));
      }
      expect(events, contains('pg_get_functiondef'));
      for (final function in [
        'chat_event_json',
        'create_chat_event',
        'update_chat_event',
        'create_call_link',
        'list_call_links',
        'agenda_items_core',
        'export_my_events2',
      ]) {
        expect(
          all,
          isNot(contains('create or replace function public.$function(')),
          reason: '$function is patched, not rewritten',
        );
      }
      // Every patch checks that it took, and runs once.
      expect(
        RegExp(r'raise exception .*(cannot|Could not)').allMatches(all).length,
        greaterThanOrEqualTo(6),
      );
      expect(all, contains("original not like '%scheduled_call_apply%'"));
    });

    test('the rewritten reminder claim says which migration it comes from', () {
      final push = sql['202610280120_scheduled_calls_push.sql']!;
      expect(push, contains('202610200010_push_text_language.sql'));
      expect(
        push,
        contains('drop function if exists public.claim_chat_event_reminder'),
      );
      // The permissions are put back as they were.
      expect(
        push,
        contains(
          'revoke execute on function public.claim_chat_event_reminder_pushes(integer)\n'
          '  from public, anon, authenticated;',
        ),
      );
      expect(
        push,
        contains(
          'grant execute on function public.claim_chat_event_reminder_pushes(integer)\n'
          '  to service_role;',
        ),
      );
    });

    test('the reminder keeps what it did and is worded in both languages', () {
      final claim = body(
        '202610280120_scheduled_calls_push.sql',
        'claim_chat_event_reminder_pushes',
      );
      expect(claim, contains("s.language = 'zh'"));
      for (final text in [
        '分钟后开始',
        '约 1 小时后开始',
        '现在开始',
        ' · 点按加入通话',
        ' · 附带通话',
        "'Starts in about 1 hour'",
        "'Starting now'",
        ' · Tap to join the call',
        ' · Includes a call',
      ]) {
        expect(claim, contains(text), reason: text);
      }
      expect(claim, contains("interval '30 minutes'"));
      expect(claim, contains('cm.muted_until'));
      expect(claim, contains('e.cancelled_at is null'));
      expect(claim, contains("interval '20 minutes'"));
      expect(claim, contains('scheduled_call_code(e.call_link_code)'));
    });
  });

  group('who may do what', () {
    test('the helpers are closed to clients', () {
      for (final signature in [
        'scheduled_call_ends_at(timestamptz, timestamptz)',
        'scheduled_call_expiry(timestamptz, timestamptz)',
        'scheduled_call_code(text)',
        'scheduled_call_make_link(uuid, uuid, timestamptz)',
        'scheduled_call_apply(public.chat_events, jsonb)',
        'chat_events_call_sync()',
        'chat_events_call_inherit()',
        'revoke_call_links_of_deleted_account()',
        'export_my_scheduled_calls(uuid)',
        'purge_scheduled_call_links()',
      ]) {
        expect(
          all,
          contains('revoke execute on function public.$signature'),
          reason: signature,
        );
      }
      expect(all, isNot(contains('to authenticated')));
      expect(all, isNot(contains('create policy')));
    });

    test('the data export and the purge are for the service role', () {
      final account = sql['202610280140_scheduled_calls_account.sql']!;
      expect(
        account,
        contains(
          'grant execute on function public.export_my_scheduled_calls(uuid) to service_role;',
        ),
      );
      expect(
        account,
        contains(
          'grant execute on function public.purge_scheduled_call_links() to service_role;',
        ),
      );
    });

    test('the helpers that touch data are security definer with a path', () {
      for (final function in [
        'scheduled_call_code',
        'scheduled_call_make_link',
        'scheduled_call_apply',
      ]) {
        final source = all.substring(
          all.indexOf('create or replace function public.$function('),
        );
        final header = source.substring(0, source.indexOf('as \$\$'));
        expect(header, contains('security definer'), reason: function);
        expect(header, contains('set search_path = public'), reason: function);
      }
    });

    test('attaching a call needs the right to call in the chat', () {
      final apply = body(
        '202610280110_scheduled_calls_events.sql',
        'scheduled_call_apply',
      );
      expect(
        apply,
        contains(
          'can_current_user_call_in_conversation(p_event.conversation_id)',
        ),
      );
      expect(apply, contains("errcode = '42501'"));
      expect(apply, contains('p_event.cancelled_at is not null'));
      // Not asked: untouched.
      expect(apply, contains("p_options ? 'call'"));
    });

    test(
      'the links of events are marked and kept out of the person\'s own',
      () {
        final schema = sql['202610280100_scheduled_calls_schema.sql']!;
        expect(
          schema,
          contains(
            'add column if not exists for_event boolean not null default false',
          ),
        );
        expect(schema, contains('and not cl.for_event'));
        expect(schema, contains("'where cl.created_by = current_user_id'"));
        expect(schema, contains("'and cl.created_by = auth.uid()'"));
      },
    );
  });

  group('keeping the link right', () {
    test('moving or cancelling the event moves or turns off its link', () {
      final events = sql['202610280110_scheduled_calls_events.sql']!;
      expect(
        events,
        contains('after update of starts_at, ends_at, cancelled_at'),
      );
      final sync = body(
        '202610280110_scheduled_calls_events.sql',
        'chat_events_call_sync',
      );
      expect(
        sync,
        contains('scheduled_call_expiry(new.starts_at, new.ends_at)'),
      );
      expect(sync, contains('new.cancelled_at is not null'));
      expect(sync, contains('cl.for_event'));
    });

    test(
      'the next occurrence of a series gets a call when the last had one',
      () {
        final events = sql['202610280110_scheduled_calls_events.sql']!;
        expect(events, contains('before insert on public.chat_events'));
        final inherit = body(
          '202610280110_scheduled_calls_events.sql',
          'chat_events_call_inherit',
        );
        expect(inherit, contains('x.series_id = new.series_id'));
        expect(inherit, contains('order by x.starts_at desc'));
        expect(inherit, contains('scheduled_call_make_link'));
        // It must work for the cron user: no signed-in person is needed.
        expect(inherit, isNot(contains('auth.uid()')));
      },
    );

    test('a link works until an hour after the event is over', () {
      final schema = sql['202610280100_scheduled_calls_schema.sql']!;
      expect(schema, contains("+ interval '1 hour'"));
      expect(schema, contains("p_starts_at + interval '2 hours'"));
    });
  });

  group('account, export and tidying', () {
    test('deleting an account turns the person\'s links off', () {
      final account = sql['202610280140_scheduled_calls_account.sql']!;
      expect(
        account,
        contains('after update of deleted_at on public.profiles'),
      );
      expect(account, contains('set revoked_at = now()'));
      expect(
        account,
        isNot(contains('function public.prepare_account_deletion')),
      );
    });

    test('the export holds only the person\'s own and never a code', () {
      final export = body(
        '202610280140_scheduled_calls_account.sql',
        'export_my_scheduled_calls',
      );
      expect(export, contains('e.created_by = target_user_id'));
      expect(export, isNot(contains("'code'")));
      expect(export, isNot(contains('call_link_code,')));
    });

    test('the purge is a job of its own, once a day, and leaves own links', () {
      final account = sql['202610280140_scheduled_calls_account.sql']!;
      expect(account, contains("'wecord-scheduled-call-links-purge'"));
      expect(account, contains("'41 4 * * *'"));
      expect(account, contains("pg_extension where extname = 'pg_cron'"));
      final purge = body(
        '202610280140_scheduled_calls_account.sql',
        'purge_scheduled_call_links',
      );
      expect(purge, contains('cl.for_event'));
      expect(purge, contains("interval '7 days'"));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/scheduled_calls_behaviour.sql',
  );
}

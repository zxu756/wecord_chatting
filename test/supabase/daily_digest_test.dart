import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the daily digest (migrations 202610230500 to
/// 202610230540), plus the behaviour script: following chats and the limit of
/// 10, what counts as news (the visibility rules), the schedule in each
/// person's own time zone, no model call without news, the claim's gates, what
/// the model may read, the card, the push, the sweep and the data export.
void main() {
  late String schema;
  late String rpcs;
  late String run;
  late String push;
  late String export;

  setUpAll(() {
    schema = File(
      'supabase/migrations/202610230500_ai_digest_schema.sql',
    ).readAsStringSync();
    rpcs = File(
      'supabase/migrations/202610230510_ai_digest_rpcs.sql',
    ).readAsStringSync();
    run = File(
      'supabase/migrations/202610230520_ai_digest_run.sql',
    ).readAsStringSync();
    push = File(
      'supabase/migrations/202610230530_ai_digest_push.sql',
    ).readAsStringSync();
    export = File(
      'supabase/migrations/202610230540_export_my_ai_digest.sql',
    ).readAsStringSync();
  });

  group('the tables', () {
    test('hard-code no user id', () {
      final uuid = RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      );
      for (final sql in [schema, rpcs, run, push, export]) {
        expect(uuid.hasMatch(sql), isFalse);
      }
    });

    test('are closed to the API except reading one\'s own settings', () {
      for (final table in ['ai_digest_settings', 'ai_digest_subscriptions']) {
        expect(
          schema,
          contains('alter table public.$table enable row level security'),
        );
        expect(
          schema,
          contains('revoke all on public.$table from anon, authenticated'),
        );
        expect(schema, contains('grant select on public.$table to authenticated'));
      }
      expect(
        schema,
        contains('alter table public.ai_digests enable row level security'),
      );
      expect(
        schema,
        contains('revoke all on public.ai_digests from anon, authenticated'),
      );
      expect(schema, isNot(contains('grant insert')));
      expect(schema, isNot(contains('grant update')));
      expect(schema, isNot(contains('grant delete')));
    });

    test('the limit of 10 is a trigger, so every writer is held to it', () {
      expect(schema, contains('select 10;'));
      expect(schema, contains('before insert on public.ai_digest_subscriptions'));
      expect(schema, contains('pg_advisory_xact_lock'));
      expect(schema, contains("errcode = '54000'"));
      expect(schema, contains("c.type in ('group', 'channel')"));
    });

    test('a digest happens once a day, and leaving ends the subscription', () {
      expect(schema, contains('unique (user_id, local_date)'));
      expect(
        schema,
        contains('after delete on public.conversation_members'),
      );
      expect(schema, contains('on delete cascade'));
    });
  });

  group('the schedule and the reading', () {
    test('uses the person\'s own time zone, not a stored copy', () {
      expect(run, contains('public.notification_time_zone(r.user_id)'));
      expect(run, contains('now() at time zone zone'));
      expect(schema, isNot(contains('timezone text')));
    });

    test('asks for no model when there is no news', () {
      expect(run, contains('ai_digest_news_count(r.user_id, since, now())'));
      expect(run, contains("case when news > 0 then 'queued' else 'skipped' end"));
      expect(run, contains("'no_news'"));
      expect(run, contains('if new_id is not null and news > 0 then'));
    });

    test('wakes the ai function the way the assistant does', () {
      expect(run, contains('public.ai_guard_wake('));
      expect(run, contains("'action', 'digest'"));
      expect(run, isNot(contains('create or replace function public.run_later_dispatch')));
    });

    test('reads with the visibility rules of the other AI features', () {
      expect(run, contains('current_user_readable_conversation_ids'));
      expect(run, contains('conversation_ai_assistant_allowed'));
      expect(run, contains('m.recalled_at is null'));
      expect(run, contains('m.review_state is null'));
      expect(run, contains('m.expires_at is null or m.expires_at > now()'));
      expect(run, contains("m.attachment->>'view_once'"));
      expect(run, contains('are_users_blocked'));
      expect(run, contains("m.type <> 'system'"));
      expect(run, contains('m.sender_id <> p_user_id'));
      expect(run, contains('user_ai_settings'));
    });

    test('every server function is closed to clients', () {
      for (final name in [
        'ai_digest_messages(uuid, timestamptz, timestamptz)',
        'ai_digest_news_count(uuid, timestamptz, timestamptz)',
        'ai_digest_tick()',
        'ai_digest_claim(uuid)',
        'ai_digest_context(uuid)',
        'ai_digest_finish(uuid, jsonb)',
        'ai_digest_close(uuid, text, text)',
      ]) {
        expect(
          run,
          contains(
            'revoke execute on function public.$name from public, anon, authenticated',
          ),
          reason: name,
        );
        expect(
          run,
          contains('grant execute on function public.$name to service_role'),
          reason: name,
        );
      }
      expect(
        push,
        contains(
          'revoke execute on function public.claim_digest_pushes() from public, anon, authenticated',
        ),
      );
      expect(
        export,
        contains(
          'revoke execute on function public.export_my_ai_digest(uuid) from public, anon, authenticated',
        ),
      );
    });

    test('the app\'s functions check the caller', () {
      for (final name in [
        'get_ai_digest_settings()',
        'set_ai_digest_settings(boolean, time, text)',
        'set_ai_digest_subscription(uuid, boolean, text)',
        'list_my_ai_digests()',
        'mark_ai_digests_read(uuid[])',
      ]) {
        expect(
          rpcs,
          contains('revoke execute on function public.$name from public, anon'),
          reason: name,
        );
        expect(
          rpcs,
          contains('grant execute on function public.$name to authenticated'),
          reason: name,
        );
      }
      expect('auth.uid()'.allMatches(rpcs).length, greaterThanOrEqualTo(5));
    });
  });

  behaviourTest(
    'the daily digest: following, news, schedule, claim, card, push, export',
    'test/supabase/daily_digest_behaviour.sql',
  );
}

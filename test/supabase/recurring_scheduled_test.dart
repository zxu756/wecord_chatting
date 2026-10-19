import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for repeating scheduled messages (D4: migrations
/// 202610240440 and 202610240450), plus the behaviour script that plays the
/// rule, the guard, sending and the chains.
void main() {
  late String schema;
  late String next;

  setUpAll(() {
    schema = File(
      'supabase/migrations/202610240440_scheduled_recurrence_schema.sql',
    ).readAsStringSync();
    next = File(
      'supabase/migrations/202610240450_scheduled_recurrence_next.sql',
    ).readAsStringSync();
  });

  test('the columns and the shape check', () {
    for (final column in [
      'recurrence text',
      'recurrence_day smallint',
      'recurrence_time time',
      'recurrence_tz text',
      'recurrence_until date',
      'recurrence_parent_id uuid',
    ]) {
      expect(schema, contains('add column if not exists $column'));
    }
    expect(
      schema,
      contains("recurrence in ('daily', 'weekdays', 'weekly', 'monthly')"),
    );
    expect(schema, contains('recurrence_day between 1 and 7'));
    expect(schema, contains('recurrence_day between 1 and 31'));
  });

  test('one send makes at most one next send', () {
    expect(
      schema,
      contains(
        'create unique index if not exists scheduled_messages_recurrence_parent_key',
      ),
    );
    expect(schema, contains('where recurrence_parent_id is not null'));
    expect(
      next,
      contains(
        'on conflict (recurrence_parent_id) where recurrence_parent_id is not null',
      ),
    );
  });

  test('the rule is worked out on the sender\'s wall clock', () {
    expect(next, contains('at time zone zone'));
    expect(next, contains('pg_timezone_names'));
    expect(next, contains("least("));
    expect(next, contains("interval '1 month - 1 day'"));
  });

  test('delivery is not rewritten: the row id stays the client id', () {
    expect(next, isNot(contains('function public.deliver_scheduled_message(')));
    expect(
      next,
      isNot(contains('function public.dispatch_due_scheduled_messages(')),
    );
    expect(next, isNot(contains('function public.run_later_dispatch(')));
    final original = File(
      'supabase/migrations/202610170010_scheduled_messages.sql',
    ).readAsStringSync();
    expect(original, contains('scheduled.id\n    );'));
  });

  test('a problem writing the next send never fails the send', () {
    final spawn = next.substring(
      next.indexOf('function public.scheduled_messages_spawn_next()'),
    );
    expect(spawn, contains('exception when others then'));
    expect(spawn, contains('raise warning'));
    expect(next, contains("new.status in ('sent', 'failed')"));
  });

  test('the guard still holds clients to the old rules', () {
    final guard = next.substring(
      next.indexOf('function public.scheduled_messages_guard()'),
    );
    expect(guard, contains("current_user not in ('authenticated', 'anon')"));
    expect(guard, contains("'Too many scheduled messages'"));
    expect(guard, contains("'Scheduled message was already sent'"));
    expect(guard, contains("'Scheduled time is in the past'"));
    expect(
      guard,
      contains(
        'recurrence_parent_id is distinct from old.recurrence_parent_id',
      ),
    );
  });

  behaviourTest(
    'repeating scheduled messages: the rule, daylight saving, next sends, retries',
    'test/supabase/recurring_scheduled_behaviour.sql',
  );
}

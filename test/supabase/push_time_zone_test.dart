import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the time zone of push subscriptions, plus the behaviour
/// script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610170100_push_time_zone.sql',
    ).readAsStringSync();
  });

  test('subscriptions keep an optional IANA time zone', () {
    expect(sql, contains('add column if not exists time_zone text;'));
    expect(sql, contains('time_zone is null or time_zone ~'));
  });

  test('registering takes the zone and replaces the old signature', () {
    expect(
      sql,
      contains(
        'drop function if exists public.register_push_subscription(text, text, text, text, text);',
      ),
    );
    expect(sql, contains('target_time_zone text default null'));
    expect(
      sql,
      contains(
        'grant execute on function public.register_push_subscription(text, text, text, text, text, text) to authenticated;',
      ),
    );
    expect(
      sql,
      contains('revoke execute on function public.register_push_subscription'),
    );
  });

  behaviourTest(
    'zones are saved, kept and validated',
    'test/supabase/push_time_zone_behaviour.sql',
  );
}

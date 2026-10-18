import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Quiet hours (migrations 202610210300 and 202610210310): the settings table,
/// the rule and the helper the push functions call, plus the behaviour script.
void main() {
  late String settings;
  late String rules;

  setUpAll(() {
    settings = File(
      'supabase/migrations/202610210300_notification_settings.sql',
    ).readAsStringSync();
    rules = File(
      'supabase/migrations/202610210310_quiet_hours.sql',
    ).readAsStringSync();
  });

  test('the settings table has the roadmap columns and is owner only', () {
    for (final column in [
      'user_id uuid primary key',
      'timezone text',
      'quiet_enabled boolean',
      'quiet_days integer[]',
      'quiet_start time',
      'quiet_end time',
      'allow_starred boolean',
      'allow_mentions boolean',
      'allow_calls boolean',
      'vip_user_ids uuid[]',
      'show_previews boolean',
    ]) {
      expect(settings, contains(column));
    }
    expect(
      settings,
      contains(
        'alter table public.user_notification_settings enable row level security;',
      ),
    );
    expect(settings, contains('using (user_id = auth.uid())'));
    expect(settings, contains('with check (user_id = auth.uid())'));
    expect(settings, isNot(contains('to anon')));
    expect(
      settings,
      contains(
        'grant select, insert, update on public.user_notification_settings to authenticated;',
      ),
    );
  });

  test('the rule functions are for the service role only', () {
    for (final signature in [
      'quiet_window_contains(text, integer[], time, time, timestamptz)',
      'notification_time_zone(uuid)',
      'in_quiet_hours(uuid, timestamptz)',
      'quiet_hours_recipients(uuid[], uuid)',
    ]) {
      expect(
        rules,
        contains('revoke execute on function public.$signature'),
        reason: signature,
      );
      expect(
        rules,
        contains('grant execute on function public.$signature'),
        reason: signature,
      );
    }
    expect(rules, isNot(contains('to authenticated')));
  });

  test('the claim functions are left alone', () {
    expect(rules, isNot(contains('claim_push_delivery(')));
    expect(settings, isNot(contains('claim_push_delivery(')));
    expect(rules, isNot(contains('create or replace function public.claim_')));
  });

  test('exceptions are calls, mentions of the person, stars and VIPs', () {
    expect(rules, contains("message.attachment->>'kind' = 'call'"));
    expect(rules, contains("mm.kind = 'user'"));
    expect(rules, contains('public.friend_stars fs'));
    expect(rules, contains('message.sender_id = any(n.vip_user_ids)'));
  });

  behaviourTest(
    'quiet hours: the rule, the settings and who breaks through',
    'test/supabase/quiet_hours_behaviour.sql',
  );
}

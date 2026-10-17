import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for sending a location and sharing it live (migration
/// 202610180050), plus the behaviour script for who may send, see and listen.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610180050_location.sql',
    ).readAsStringSync();
  });

  test('shares hold who and until when, never a position', () {
    const create = 'create table if not exists public.live_location_shares';
    expect(sql, contains(create));
    expect(
      sql,
      contains('alter table public.live_location_shares enable row level'),
    );
    final table = sql.substring(
      sql.indexOf(create),
      sql.indexOf('create unique index'),
    );
    for (final column in ['lat', 'lng', 'latitude', 'longitude', 'position']) {
      expect(
        RegExp('^\\s+$column\\s', multiLine: true).hasMatch(table),
        isFalse,
        reason: column,
      );
    }
    expect(table, contains("interval '8 hours'"));
  });

  test('clients can only read shares; writes go through functions', () {
    expect(
      sql,
      contains(
        'revoke all on public.live_location_shares from public, anon, authenticated',
      ),
    );
    expect(
      sql,
      contains('grant select on public.live_location_shares to authenticated'),
    );
  });

  test('positions travel on private channels guarded by policies', () {
    expect(sql, contains('on realtime.messages for select'));
    expect(sql, contains('on realtime.messages for insert'));
    expect(sql, contains("realtime.messages.extension = 'broadcast'"));
    expect(sql, contains('public.can_receive_live_location('));
    expect(sql, contains('public.can_send_live_location('));
  });

  test('blocks and the AI guard review state are respected', () {
    expect(sql, contains('public.are_users_blocked(auth.uid(), s.user_id)'));
    expect(sql, contains('m.review_state is null'));
    expect(sql, contains('m.recalled_at is null'));
  });

  test('leaving a chat ends the share', () {
    expect(sql, contains('after delete on public.conversation_members'));
  });

  behaviourTest(
    'locations and live sharing: who may send, see and listen',
    'test/supabase/location_behaviour.sql',
  );
}

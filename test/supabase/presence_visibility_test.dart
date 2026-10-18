import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Who may see that a person is online (migrations 202610190070 and
/// 202610190071): schema checks plus the behaviour script.
void main() {
  late String sql;
  late String drop;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610190070_presence_visibility.sql',
    ).readAsStringSync();
    drop = File(
      'supabase/migrations/202610190071_drop_online_users_policy.sql',
    ).readAsStringSync();
  });

  test('presence_state is closed to the app', () {
    expect(
      sql,
      contains('alter table public.presence_state enable row level security;'),
    );
    expect(
      sql,
      contains('revoke all on public.presence_state from anon, authenticated;'),
    );
  });

  test('signals go out on a private channel of the viewer only, as ids', () {
    expect(sql, contains("'presence-updates:' || recipient::text"));
    expect(sql, contains("jsonb_build_object('user_ids'"));
    expect(
      sql,
      contains(
        "(select realtime.topic()) = 'presence-updates:' || (select auth.uid())",
      ),
    );
    expect(sql, contains('on realtime.messages for select'));
    expect(sql, isNot(contains('realtime.messages for insert')));
  });

  test('only the reader and the beat are callable by the app', () {
    expect(
      sql,
      contains(
        'grant execute on function public.visible_presence(uuid[]) to authenticated;',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.touch_presence(boolean, text) to authenticated;',
      ),
    );
    for (final signature in [
      'presence_can_see(uuid, uuid)',
      'presence_contacts(uuid)',
      'presence_send(uuid, text, jsonb)',
      'presence_notify(uuid)',
      'presence_scope_changed(uuid, uuid[])',
    ]) {
      expect(
        sql,
        contains(
          'revoke execute on function public.$signature from public, anon, authenticated;',
        ),
      );
    }
  });

  test('the old one-argument beat is replaced, not overloaded', () {
    expect(
      sql,
      contains('drop function if exists public.touch_presence(boolean);'),
    );
  });

  test('the global channel is dropped last and by itself', () {
    expect(
      drop,
      contains(
        'drop policy if exists online_users_receive on realtime.messages;',
      ),
    );
    expect(
      drop,
      contains('drop policy if exists online_users_send on realtime.messages;'),
    );
    expect(sql, isNot(contains('create policy online_users_')));
  });

  behaviourTest(
    'presence visibility: friends, circle and chat mates see a person; '
        'strangers, blocks, hidden and ex-members do not',
    'test/supabase/presence_visibility_behaviour.sql',
  );
}

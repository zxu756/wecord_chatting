import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for device sessions, plus the behaviour script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610170022_device_sessions.sql',
    ).readAsStringSync();
  });

  test('a device record is keyed by its session and goes with it', () {
    expect(
      sql,
      contains('session_id uuid primary key references auth.sessions(id)'),
    );
    expect(sql, contains('on delete cascade'));
  });

  test('listing is limited to the caller\'s own sessions', () {
    expect(sql, contains('where s.user_id = auth.uid()'));
    expect(sql, contains("auth.jwt()->>'session_id'"));
  });

  test('no address or location leaves the server', () {
    final list = sql.substring(sql.indexOf('function public.list_my_sessions'));
    expect(list, isNot(contains('s.ip')));
    expect(list, isNot(contains('location')));
  });

  test('only the service role may end a session', () {
    expect(
      sql,
      contains(
        'revoke execute on function public.delete_user_session(uuid, uuid) from public, anon, authenticated;',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.delete_user_session(uuid, uuid) to service_role;',
      ),
    );
  });

  test('the sessions Edge Function checks ownership before revoking', () {
    final function = File(
      'supabase/functions/sessions/index.ts',
    ).readAsStringSync();
    expect(function, contains('list_my_sessions'));
    expect(function, contains('current_session'));
    expect(function, contains('delete_user_session'));
    expect(
      function.indexOf('list_my_sessions'),
      lessThan(function.indexOf('delete_user_session')),
    );
  });

  behaviourTest(
    'registering, listing and ending sessions work against a database',
    'test/supabase/devices_behaviour.sql',
  );
}

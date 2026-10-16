import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for disappearing messages, plus the behaviour script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610170020_disappearing_messages.sql',
    ).readAsStringSync();
  });

  test('the timer is one of three lengths or off', () {
    expect(sql, contains('add column if not exists disappear_after_seconds'));
    expect(sql, contains('in (86400, 604800, 7776000)'));
  });

  test('the server alone sets expires_at, never for system lines', () {
    expect(sql, contains('create trigger messages_set_expiry'));
    expect(sql, contains('before insert on public.messages'));
    expect(sql, contains('new.expires_at := null;'));
    expect(sql, contains("if new.type = 'system' then"));
  });

  test('readers do not see expired rows even before the purge', () {
    expect(sql, contains('create policy messages_select_member'));
    expect(sql, contains('(expires_at is null or expires_at > now())'));
  });

  test('only owners and admins change a group; the change is announced', () {
    expect(sql, contains("cm.role in ('owner', 'admin')"));
    expect(sql, contains("'kind', 'disappearing'"));
  });

  test('the purge cannot be called by readers', () {
    expect(
      sql,
      contains(
        'revoke execute on function public.purge_expired_messages(integer) from public, anon, authenticated;',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.purge_expired_messages(integer) to service_role;',
      ),
    );
  });

  test('cron is optional', () {
    expect(sql, contains("name = 'pg_cron'"));
    expect(sql, contains("raise notice 'pg_cron is not available"));
    expect(sql, contains('exception when others then'));
  });

  test('the Edge Function only answers the service role', () {
    final function = File(
      'supabase/functions/expire-messages/index.ts',
    ).readAsStringSync();
    expect(function, contains('!== serviceRoleKey'));
    expect(function, contains('claim_expired_media'));
    expect(function, contains('finish_expired_media'));
  });

  behaviourTest(
    'timers, expiry, purge and clean-up work against a database',
    'test/supabase/disappearing_messages_behaviour.sql',
  );
}

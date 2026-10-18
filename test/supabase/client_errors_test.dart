import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for crash and error reports (migration 202610190030), plus
/// the behaviour script for the RPC's limits and that clients cannot read.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610190030_client_errors.sql',
    ).readAsStringSync();
  });

  test('the table is closed to every client role', () {
    expect(
      sql,
      contains('alter table public.client_errors enable row level security'),
    );
    expect(
      sql,
      contains(
        'revoke all on public.client_errors from public, anon, authenticated',
      ),
    );
    expect(sql, isNot(contains('create policy')));
    expect(sql, isNot(contains('grant select')));
  });

  test('the RPC is security definer with a fixed search path', () {
    final rpc = sql.substring(
      sql.indexOf('create or replace function public.report_client_errors'),
      sql.indexOf('revoke execute on function public.report_client_errors'),
    );
    expect(rpc, contains('security definer'));
    expect(rpc, contains("set search_path = ''"));
    expect(
      sql,
      contains('grant execute on function public.report_client_errors(jsonb)'),
    );
    expect(sql, contains('to anon, authenticated'));
  });

  test('purge and rate helpers are not callable by clients', () {
    expect(
      sql,
      contains(
        'revoke execute on function public.purge_old_client_errors()\n'
        '  from public, anon, authenticated',
      ),
    );
    expect(sql, contains('public.client_error_take(text, integer, integer)'));
  });

  test('the table keeps what was asked for', () {
    final table = sql.substring(
      sql.indexOf('create table if not exists public.client_errors'),
      sql.indexOf('create index'),
    );
    for (final column in [
      'id uuid',
      'user_id uuid',
      'created_at',
      'platform',
      'app_version',
      'build',
      'kind',
      'message',
      'stack',
      'fingerprint',
      'count',
      'context jsonb',
    ]) {
      expect(table, contains(column), reason: column);
    }
  });

  test('purges after 30 days, scheduled only when pg_cron is installed', () {
    expect(sql, contains("interval '30 days'"));
    expect(sql, contains("extname = 'pg_cron'"));
    expect(sql, contains("'client-errors-purge'"));
  });

  behaviourTest(
    'limits, closed table and purge behave',
    'test/supabase/client_errors_behaviour.sql',
  );
}

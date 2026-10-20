import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for product statistics (K2), monitoring and alerts (K3) and
/// the error grouping (K5), plus the behaviour script.
void main() {
  String read(String name) =>
      File('supabase/migrations/$name').readAsStringSync();

  const files = [
    '202610260100_ops_metrics_schema.sql',
    '202610260110_ops_metrics_compute.sql',
    '202610260120_ops_metrics_admin.sql',
    '202610260130_error_groups.sql',
    '202610260140_ops_alerts_schema.sql',
    '202610260150_ops_health_checks.sql',
    '202610260160_ops_alerts_admin.sql',
    '202610260170_ops_alert_push.sql',
  ];
  late String all;

  setUpAll(() {
    all = files.map(read).join('\n');
  });

  test('nobody reads or writes the new tables through the API', () {
    for (final table in [
      'ops_settings',
      'ops_active_days',
      'ops_daily_metrics',
      'ops_push_stats',
      'ops_error_groups',
      'ops_checks',
      'ops_alerts',
    ]) {
      expect(all, contains('alter table public.$table enable row level'));
      expect(
        all,
        contains(
          'revoke all on public.$table from public, anon, authenticated;',
        ),
        reason: table,
      );
      expect(all, isNot(contains('grant select on public.$table')));
      expect(all, isNot(contains('create policy $table')));
    }
  });

  test('every admin function checks the caller before anything else', () {
    final matches = RegExp(
      r'create or replace function public\.(admin_\w+)\([\s\S]*?\$\$;',
    ).allMatches(all).toList();
    expect(
      matches.map((m) => m.group(1)),
      containsAll([
        'admin_ops_metrics',
        'admin_ops_error_groups',
        'admin_list_ops_checks',
        'admin_list_ops_alerts',
        'admin_ack_ops_alert',
        'admin_resolve_ops_alert',
      ]),
    );
    for (final match in matches) {
      final body = match.group(0)!;
      final begin = body.indexOf('begin');
      expect(
        body.substring(begin).replaceAll(RegExp(r'\s+'), ' '),
        startsWith('begin perform public.admin_require(array['),
        reason: match.group(1),
      );
      expect(body, contains('security definer'), reason: match.group(1));
      expect(
        body,
        contains('set search_path = public'),
        reason: match.group(1),
      );
    }
  });

  test('only platform admins and the service role can run the internals', () {
    expect(all, contains('revoke execute on function public.ops_tick()'));
    expect(
      all,
      contains(
        'grant execute on function public.ops_record_push(integer, integer, integer)\n  to service_role;',
      ),
    );
    expect(
      all,
      contains(
        'grant execute on function public.claim_ops_alert_pushes() to service_role;',
      ),
    );
    // The admin functions are granted to signed-in people and nobody else.
    for (final name in [
      'admin_ops_metrics(integer)',
      'admin_ops_error_groups(integer, integer)',
      'admin_list_ops_checks()',
      'admin_ack_ops_alert(uuid)',
    ]) {
      expect(all, contains('revoke execute on function public.$name'));
      expect(all, contains('grant execute on function public.$name'));
    }
  });

  test('the rest of the dispatcher is left alone', () {
    expect(all, isNot(contains('function public.run_later_dispatch')));
    expect(all, isNot(contains('function public.report_client_errors')));
    expect(all, isNot(contains('function public.claim_announcement_pushes')));
    expect(all, isNot(contains('.bio')));
  });

  test('the jobs have their own cron entries, each guarded on pg_cron', () {
    for (final job in [
      'wecord-ops-tick',
      'wecord-ops-daily-close',
      'wecord-ops-health-check',
    ]) {
      expect(all, contains("'$job'"));
    }
    expect(
      RegExp(r"extname = 'pg_cron'").allMatches(all).length,
      greaterThanOrEqualTo(2),
    );
  });

  test('people are kept as salted keys, never as ids', () {
    final schema = read('202610260100_ops_metrics_schema.sql');
    final table = schema.substring(
      schema.indexOf('create table if not exists public.ops_active_days'),
      schema.indexOf('create table if not exists public.ops_daily_metrics'),
    );
    expect(table, contains('user_key text not null'));
    expect(table, isNot(contains('user_id')));
    expect(table, isNot(contains('references')));
    final daily = schema.substring(
      schema.indexOf('create table if not exists public.ops_daily_metrics'),
    );
    expect(daily, isNot(contains('user_id')));
    expect(daily, isNot(contains('conversation_id')));
  });

  test(
    'alerts hold numbers and names of jobs, with a text in both languages',
    () {
      final schema = read('202610260140_ops_alerts_schema.sql');
      for (final column in ['title_en', 'title_zh', 'body_en', 'body_zh']) {
        expect(schema, contains('$column text not null'));
      }
      expect(
        schema,
        contains("kind in ('announcement', 'feedback_reply', 'ops_alert')"),
      );
    },
  );

  behaviourTest(
    'the statistics, the monitoring and the error groups behave',
    'test/supabase/ops_metrics_behaviour.sql',
  );
}

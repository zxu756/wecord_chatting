import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for circle insights and invite tracking (migrations
/// 202610230300 to 202610230320), plus the behaviour script that plays every
/// join path and the insights RPC.
void main() {
  late String tracking;
  late String data;
  late String rpc;

  setUpAll(() {
    tracking = File(
      'supabase/migrations/202610230300_circle_invite_tracking.sql',
    ).readAsStringSync();
    data = File(
      'supabase/migrations/202610230310_circle_insights_data.sql',
    ).readAsStringSync();
    rpc = File(
      'supabase/migrations/202610230320_circle_insights_rpc.sql',
    ).readAsStringSync();
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('invite tracking', () {
    test('circle_members remembers the invite and who is behind it', () {
      expect(
        tracking,
        contains('add column if not exists joined_via_invite text'),
      );
      expect(tracking, contains('add column if not exists invited_by uuid'));
      expect(
        tracking,
        contains('add column if not exists invite_code text'),
        reason: 'a request made by an invite keeps the link for the approval',
      );
    });

    test('the join paths of C1 are not rewritten', () {
      for (final name in [
        'accept_circle_invite',
        'join_public_circle',
        'invite_circle_members',
        'decide_join_request',
        'submit_circle_join_request',
        'list_circle_invites',
      ]) {
        expect(
          tracking,
          isNot(contains('function public.$name(')),
          reason: '$name keeps its definition',
        );
      }
      expect(
        tracking,
        contains('after update of use_count on public.circle_invites'),
      );
      expect(tracking, contains('before insert on public.circle_members'));
      expect(tracking, contains("when (new.action = 'member_add')"));
    });

    test('approval credits the invite, never the moderator who decides', () {
      final credit = body(tracking, 'circle_members_credit_request');
      expect(credit, contains('auth.uid() = new.user_id'));
      expect(credit, contains("r.status = 'pending'"));
      expect(credit, isNot(contains('auth.uid() into')));
    });

    test('the log is closed to clients and numbers come through an RPC', () {
      expect(
        tracking,
        contains(
          'revoke all on public.circle_invite_joins from public, anon, authenticated',
        ),
      );
      final stats = body(tracking, 'get_circle_invite_stats');
      expect(stats, contains("'manage_channels'"));
      expect(stats, contains("'create_invites'"));
      expect(stats, contains('security definer'));
      expect(stats, contains('set search_path = public'));
      expect(
        tracking,
        contains(
          'revoke execute on function public.get_circle_invite_stats(uuid) from public, anon',
        ),
      );
    });
  });

  group('the data', () {
    test('the tables hold counts and a yes/no, closed to clients', () {
      for (final table in ['circle_daily_stats', 'circle_member_daily']) {
        expect(
          data,
          contains('alter table public.$table enable row level security'),
        );
        expect(
          data,
          contains(
            'revoke all on public.$table from public, anon, authenticated',
          ),
        );
      }
      expect(data, contains('hourly integer[]'));
      expect(data, contains('top_channels jsonb'));
      expect(data, contains('left_members integer'));
      // Who was active that day, nothing else: no channel, count or content.
      final member = data.substring(
        data.indexOf('create table if not exists public.circle_member_daily'),
        data.indexOf('create index if not exists circle_member_daily_user_idx'),
      );
      expect(member, contains('primary key (circle_id, day, user_id)'));
      expect(member, isNot(contains('body')));
      expect(member, isNot(contains('count')));
    });

    test('the aggregation is private to the server and runs nightly', () {
      expect(
        data,
        contains(
          'revoke execute on function public.aggregate_circle_insights(date)\n'
          '  from public, anon, authenticated;',
        ),
      );
      expect(
        data,
        contains(
          'grant execute on function public.aggregate_circle_insights(date) to service_role',
        ),
      );
      expect(data, contains("'10 0 * * *'"));
      expect(data, contains("jobname = 'wecord-circle-insights'"));
    });

    test('the dispatcher is left as it is', () {
      expect(data, isNot(contains('function public.run_later_dispatch(')));
    });

    test('bots, webhooks, recalled and held messages are not activity', () {
      final aggregate = body(data, 'aggregate_circle_insights');
      expect(aggregate, contains('not p.is_bot'));
      expect(aggregate, contains('m.webhook_id is null'));
      expect(aggregate, contains('m.recalled_at is null'));
      expect(aggregate, contains("'held'"));
      expect(aggregate, contains("'removed'"));
    });
  });

  group('the insights RPC', () {
    test('needs manage_circle or view_audit_log', () {
      final insights = body(rpc, 'get_circle_insights');
      expect(insights, contains("'manage_circle'"));
      expect(insights, contains("'view_audit_log'"));
      expect(insights, contains('security definer'));
      expect(insights, contains('set search_path = public'));
      expect(insights, contains("errcode = '42501'"));
      expect(
        rpc,
        contains(
          'revoke execute on function public.get_circle_insights(uuid, integer, integer)\n'
          '  from public, anon;',
        ),
      );
    });

    test('counts under 5 are hidden, and everything in a small circle', () {
      final mask = body(rpc, 'insight_count');
      expect(mask, contains('n between 1 and 4'));
      expect(mask, contains('when hide then -1'));
      final insights = body(rpc, 'get_circle_insights');
      expect(insights, contains('small := members_now < 5'));
    });

    test('retention is a ratio and only with 5 people behind it', () {
      final insights = body(rpc, 'get_circle_insights');
      expect(insights, contains('joined_total < 5'));
      expect(insights, contains('prior_base < 5'));
    });

    test('no invite code and no person leaves the function', () {
      final insights = body(rpc, 'get_circle_insights');
      expect(insights, isNot(contains("'code'")));
      expect(insights, isNot(contains("'user_id'")));
      expect(insights, isNot(contains('.bio')));
    });
  });

  behaviourTest(
    'insights: every join path credited, the aggregation, masking and access',
    'test/supabase/circle_insights_behaviour.sql',
  );
}

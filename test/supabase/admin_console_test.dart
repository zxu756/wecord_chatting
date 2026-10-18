import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the admin console (migrations 202610210110 to
/// 202610210130), plus the behaviour script: the attacks that must fail
/// (every admin RPC as a normal user, as a circle owner, as a member and as
/// nobody; reading the admin tables; reading chat as an admin) and the walk
/// through reports, suspensions and both ways of taking a circle down.
void main() {
  late String foundation;
  late String takedown;
  late String rpcs;

  setUpAll(() {
    foundation = File(
      'supabase/migrations/202610210110_admin_foundation.sql',
    ).readAsStringSync();
    takedown = File(
      'supabase/migrations/202610210120_circle_takedown.sql',
    ).readAsStringSync();
    rpcs = File(
      'supabase/migrations/202610210130_admin_rpcs.sql',
    ).readAsStringSync();
  });

  group('the admin tables', () {
    test('are closed to every client role', () {
      for (final table in [
        'app_admins',
        'admin_audit_log',
        'app_user_suspensions',
      ]) {
        expect(
          foundation,
          contains('alter table public.$table enable row level security'),
        );
        expect(
          foundation,
          contains(
            'revoke all on public.$table from public, anon, authenticated',
          ),
        );
      }
      expect(foundation, isNot(contains('create policy')));
      expect(foundation, isNot(contains('grant select')));
    });

    test('the first owner is never written into a migration', () {
      for (final file
          in Directory('supabase/migrations')
              .listSync()
              .whereType<File>()
              .where((file) => file.path.endsWith('.sql'))) {
        expect(
          file.readAsStringSync(),
          isNot(contains('insert into public.app_admins')),
          reason: file.path,
        );
      }
    });

    test('roles are owner, moderator and support', () {
      expect(
        foundation,
        contains("check (role in ('owner', 'moderator', 'support'))"),
      );
    });

    test('a report keeps who handled it and a copy of what it is about', () {
      for (final column in [
        'handled_by uuid',
        'handled_at timestamptz',
        'resolution text',
        'snapshot jsonb',
      ]) {
        expect(foundation, contains('add column if not exists $column'));
      }
      expect(foundation, contains('create trigger reports_capture_snapshot'));
      expect(foundation, contains('before insert on public.reports'));
    });

    test('a circle is taken down in one of two modes', () {
      expect(foundation, contains('disabled_at timestamptz'));
      expect(foundation, contains("disabled_mode in ('delist', 'suspend')"));
    });
  });

  group('every admin RPC', () {
    final rpcNames = [
      'admin_list_reports',
      'admin_get_report',
      'admin_resolve_report',
      'admin_suspend_user',
      'admin_unsuspend_user',
      'admin_disable_circle',
      'admin_enable_circle',
      'admin_delete_circle_post',
      'admin_list_audit_log',
    ];

    String body(String name) {
      final start = rpcs.indexOf('create or replace function public.$name(');
      expect(start, isNonNegative, reason: name);
      return rpcs.substring(start, rpcs.indexOf('\n\$\$;', start));
    }

    test('is security definer with a fixed search path', () {
      for (final name in rpcNames) {
        final text = body(name);
        expect(text, contains('security definer'), reason: name);
        expect(text, contains('set search_path = public'), reason: name);
      }
    });

    test('checks the caller first', () {
      for (final name in rpcNames) {
        final text = body(name);
        final begin = text.indexOf('begin');
        expect(
          text.substring(begin),
          startsWith('begin\n  perform public.admin_require('),
          reason: name,
        );
      }
    });

    test('is closed to nobody-signed-in', () {
      for (final name in rpcNames) {
        expect(rpcs, contains('revoke execute on function public.$name('));
      }
      expect(rpcs, isNot(contains('to anon')));
    });

    test(
      'only owners and moderators sanction; support only reads and closes',
      () {
        for (final name in [
          'admin_suspend_user',
          'admin_unsuspend_user',
          'admin_disable_circle',
          'admin_enable_circle',
          'admin_delete_circle_post',
        ]) {
          expect(
            body(name),
            contains("admin_require(array['owner', 'moderator'])"),
            reason: name,
          );
        }
        for (final name in [
          'admin_list_reports',
          'admin_get_report',
          'admin_resolve_report',
          'admin_list_audit_log',
        ]) {
          expect(
            body(name),
            contains("admin_require(array['owner', 'moderator', 'support'])"),
            reason: name,
          );
        }
      },
    );

    test('writes the audit log', () {
      for (final name in [
        'admin_suspend_user',
        'admin_unsuspend_user',
        'admin_disable_circle',
        'admin_enable_circle',
        'admin_delete_circle_post',
      ]) {
        expect(body(name), contains('admin_write_audit('), reason: name);
      }
      expect(body('admin_close_report'), contains('admin_write_audit('));
    });

    test('the helpers are not callable by clients', () {
      for (final name in ['admin_close_report', 'admin_report_row']) {
        expect(rpcs, contains('revoke execute on function public.$name('));
        expect(
          rpcs,
          isNot(contains('grant execute on function public.$name(')),
        );
      }
      expect(
        foundation,
        contains(
          'revoke execute on function public.admin_write_audit(text, text, uuid, uuid, jsonb)\n'
          '  from public, anon, authenticated;',
        ),
      );
      expect(
        foundation,
        contains('delete_all_user_sessions(uuid) to service_role'),
      );
    });
  });

  group('taking a circle down', () {
    test(
      'no new member gets in on any path: one trigger on circle_members',
      () {
        expect(takedown, contains('before insert on public.circle_members'));
        expect(takedown, contains('before insert on public.circle_invites'));
        expect(takedown, contains("c.disabled_at is not null"));
      },
    );

    test('Discover leaves out delisted circles', () {
      expect(takedown, contains('and c.disabled_at is null'));
      expect(takedown, contains('function public.list_discoverable_circles('));
      expect(
        takedown,
        contains('function public.discoverable_circle_preview('),
      );
    });

    test('a suspended circle is unreadable and unwritable', () {
      expect(takedown, contains('as restrictive for select'));
      expect(takedown, contains('before insert on public.messages'));
      expect(
        takedown,
        contains('function public.current_user_readable_conversation_ids()'),
      );
      expect(
        takedown,
        contains('function public.is_current_user_conversation_member('),
      );
      expect(takedown, contains('function public.get_circle_detail('));
      expect(takedown, contains("c.disabled_mode is distinct from 'suspend'"));
    });

    test('the rewritten functions keep the rules of their older versions', () {
      // These are the newest definitions with only the take-down added; the
      // rules that are easy to overwrite stay (permission overwrites and
      // view_channel, default role).
      expect(
        takedown,
        contains('circle_channel_permissions(cc.id, auth.uid())'),
      );
      expect(takedown, contains('circle_channel_overwrites'));
      expect(takedown, contains("'current_user_permissions'"));
      expect(
        takedown,
        contains('public.circle_member_permissions(c.id, auth.uid())'),
      );
    });
  });

  behaviourTest(
    'admin console: attacks, reports, suspensions and take-downs',
    'test/supabase/admin_console_behaviour.sql',
  );
}

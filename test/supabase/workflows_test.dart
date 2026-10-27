import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Workflow automation (D9: migrations 202610281300 to 202610281340): what
/// the SQL says, as text, plus the behaviour script that plays people through
/// it against the local database.
void main() {
  final names = [
    '202610281300_workflows_schema.sql',
    '202610281310_workflows_rpcs.sql',
    '202610281320_workflows_events.sql',
    '202610281330_workflows_run.sql',
    '202610281340_workflows_account.sql',
  ];
  late Map<String, String> sql;
  late String all;

  setUpAll(() {
    sql = {
      for (final name in names)
        name: File('supabase/migrations/$name').readAsStringSync(),
    };
    all = sql.values.join('\n');
  });

  group('numbering and what is left alone', () {
    test('the migrations are in this package\'s range, ten apart', () {
      final numbers = [
        for (final name in names) int.parse(name.substring(0, 12)),
      ];
      for (var i = 0; i < numbers.length; i++) {
        expect(numbers[i], 202610281300 + i * 10);
      }
      expect(numbers.last, lessThan(202610281400));
    });

    test('the every-minute dispatcher is not redefined', () {
      expect(all, isNot(contains('function public.run_later_dispatch')));
      expect(all, isNot(contains('select public.run_later_dispatch')));
    });

    test('no function other packages own is rewritten', () {
      for (final name in [
        'set_member_roles',
        'send_text_message',
        'create_form',
        'prepare_account_deletion',
        'write_circle_audit',
        'guard_item_text',
        'recurrence_next',
        'claim_push_delivery',
      ]) {
        expect(
          all,
          isNot(contains('create or replace function public.$name(')),
          reason: name,
        );
      }
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('every function is security definer with a fixed search path', () {
      for (final MapEntry(:key, :value) in sql.entries) {
        final functions = RegExp(
          r'create or replace function public\.(\w+)\(([\s\S]*?)\n\$\$;',
        ).allMatches(value);
        for (final match in functions) {
          final text = match.group(0)!;
          final name = match.group(1)!;
          // Plain triggers and helpers that read nothing of the caller's.
          if (const {
            'workflow_limits',
            'workflow_clean_text',
            'workflow_uuid',
            'messages_flag_workflow',
          }.contains(name)) {
            continue;
          }
          expect(
            text,
            contains('security definer'),
            reason: '$name in $key is security definer',
          );
          expect(
            text,
            contains('set search_path = public'),
            reason: '$name in $key sets its search path',
          );
        }
      }
    });
  });

  group('who can do what', () {
    test('the tables are closed to clients', () {
      final schema = sql['202610281300_workflows_schema.sql']!;
      for (final table in [
        'workflows',
        'workflow_runs',
        'workflow_push_queue',
      ]) {
        expect(
          schema,
          contains('alter table public.$table enable row level security'),
        );
        expect(
          schema,
          contains('revoke all on public.$table from anon, authenticated'),
        );
      }
      expect(schema, isNot(contains('grant insert')));
      expect(schema, isNot(contains('grant update')));
    });

    test('the engine is for the service role only', () {
      final run = sql['202610281330_workflows_run.sql']!;
      expect(
        run,
        contains(
          'grant execute on function public.run_workflow_tick(integer) to service_role',
        ),
      );
      expect(
        run,
        isNot(contains('run_workflow_tick(integer) to authenticated')),
      );
      expect(
        run,
        contains(
          'grant execute on function public.claim_workflow_message_pushes() to service_role',
        ),
      );
    });

    test('only managers may make, change, pause, delete and read the log', () {
      final rpcs = sql['202610281310_workflows_rpcs.sql']!;
      expect(rpcs, contains('workflow_assert_manager'));
      expect(rpcs, contains("raise exception 'workflow_not_allowed'"));
      expect(rpcs, contains("raise exception 'workflow_limit_reached'"));
    });

    test('the permission is checked again at run time, and a loss pauses', () {
      final run = sql['202610281330_workflows_run.sql']!;
      expect(run, contains('workflow_user_can_manage'));
      expect(run, contains("'creator_lost_permission'"));
    });
  });

  group('limits and safety', () {
    test('the limits are one function', () {
      final schema = sql['202610281300_workflows_schema.sql']!;
      for (final key in [
        'max_per_circle',
        'max_per_group',
        'max_actions',
        'max_runs_per_day',
        'max_member_runs_per_day',
      ]) {
        expect(schema, contains("'$key'"));
      }
    });

    test('a workflow cannot be set off by another workflow', () {
      final events = sql['202610281320_workflows_events.sql']!;
      expect(events, contains("wecord.workflow_run"));
    });

    test('its messages are marked as automatic and never raise the guard', () {
      final events = sql['202610281320_workflows_events.sql']!;
      expect(events, contains('messages_aa_workflow_flag'));
      expect(events, contains('auto_reply'));
    });

    test('it has a job of its own', () {
      final run = sql['202610281330_workflows_run.sql']!;
      expect(run, contains("'wecord-workflows-tick'"));
      expect(run, contains('run_workflow_tick()'));
    });
  });

  group('accounts', () {
    test('deleting an account pauses what it made, the export has it', () {
      final account = sql['202610281340_workflows_account.sql']!;
      expect(account, contains('profiles_erase_workflows'));
      expect(account, contains("'creator_gone'"));
      expect(
        account,
        contains(
          'grant execute on function public.export_my_workflows(uuid) to service_role',
        ),
      );
    });
  });

  group('behaviour', () {
    behaviourTest(
      'workflow automation against the local database',
      'test/supabase/workflows_behaviour.sql',
    );
  });
}

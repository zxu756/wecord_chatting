import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for onboarding 2.0 (C2: migrations 202610230200 to
/// 202610230220), plus the behaviour script that plays the role rule, the
/// questions, the tasks and the greeting.
void main() {
  late String schema;
  late String rpcs;
  late String greeting;

  setUpAll(() {
    schema = File(
      'supabase/migrations/202610230200_onboarding_guide_schema.sql',
    ).readAsStringSync();
    rpcs = File(
      'supabase/migrations/202610230210_onboarding_guide_rpcs.sql',
    ).readAsStringSync();
    greeting = File(
      'supabase/migrations/202610230220_onboarding_greeting.sql',
    ).readAsStringSync();
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('the role rule', () {
    test('only view, send, invite and voice are plain', () {
      final safe = body(schema, 'onboarding_safe_permissions');
      for (final permission in [
        'view_channel',
        'send_messages',
        'create_invites',
        'connect_voice',
      ]) {
        expect(safe, contains("'$permission'"));
      }
      for (final permission in [
        'administrator',
        'manage_roles',
        'manage_messages',
        'mention_everyone',
        'manage_circle',
        'kick_members',
      ]) {
        expect(safe, isNot(contains("'$permission'")), reason: permission);
      }
    });

    test('a role is refused when it is @everyone, powerful or too high', () {
      final problem = body(schema, 'onboarding_role_problem');
      expect(problem, contains("return 'missing'"));
      expect(problem, contains("return 'default'"));
      expect(problem, contains("return 'permissions'"));
      expect(problem, contains("return 'rank'"));
      expect(problem, contains('~public.onboarding_safe_permissions()'));
      expect(problem, contains('other.position < role_row.position'));
    });

    test('it is asked on every link, and again when an answer is given', () {
      expect(
        schema,
        contains(
          'before insert or update on public.circle_onboarding_option_roles',
        ),
      );
      expect(
        body(schema, 'check_onboarding_option_role'),
        contains('public.onboarding_role_problem'),
      );
      final answer = body(rpcs, 'complete_onboarding_prompts');
      expect(
        answer,
        contains(
          'public.onboarding_role_problem(target_circle_id, orl.role_id) is null',
        ),
        reason: 'the role is checked now, not when it was attached',
      );
    });

    test('a role that turns powerful is unlinked and taken back', () {
      final detach = body(schema, 'detach_onboarding_role');
      expect(
        detach,
        contains('delete from public.circle_onboarding_option_roles'),
      );
      expect(detach, contains('mr.via_onboarding'));
      expect(
        schema,
        contains('after update of permissions on public.circle_roles'),
      );
    });

    test('only roles given by an answer are taken back', () {
      final answer = body(rpcs, 'complete_onboarding_prompts');
      expect(answer, contains('and mr.via_onboarding'));
      expect(
        answer,
        contains('on conflict (circle_id, user_id, role_id) do nothing'),
      );
      expect(
        schema,
        contains(
          'add column if not exists via_onboarding boolean not null default false',
        ),
      );
    });

    test('the grant is audited as a system action of the member', () {
      final answer = body(rpcs, 'complete_onboarding_prompts');
      expect(answer, contains("'onboarding_roles'"));
      expect(answer, contains("'source', 'onboarding'"));
    });
  });

  group('who may do what', () {
    test('every table is closed to clients', () {
      for (final table in [
        'circle_onboarding_prompts',
        'circle_onboarding_options',
        'circle_onboarding_option_roles',
        'circle_onboarding_option_channels',
        'circle_guide_tasks',
        'circle_guide_settings',
        'circle_member_onboarding',
        'circle_member_onboarding_answers',
        'circle_member_guide_tasks',
      ]) {
        expect(
          schema,
          contains('alter table public.$table enable row level security'),
          reason: table,
        );
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated',
          ),
          reason: table,
        );
      }
    });

    test('every function is a definer with a fixed search path', () {
      for (final name in [
        'get_circle_guide',
        'complete_onboarding_prompts',
        'complete_guide_task',
        'dismiss_circle_guide',
        'get_circle_guide_config',
        'set_circle_guide_prompts',
        'set_circle_guide_tasks',
        'set_circle_greeting',
      ]) {
        final function = body(rpcs, name);
        expect(function, contains('security definer'), reason: name);
        expect(function, contains('set search_path = public'), reason: name);
        expect(function, contains("errcode = '42501'"), reason: name);
      }
      for (final grant in [
        'get_circle_guide(uuid)',
        'complete_onboarding_prompts(uuid, uuid[])',
        'set_circle_guide_prompts(uuid, jsonb)',
      ]) {
        expect(
          rpcs,
          contains(
            'revoke execute on function public.$grant from public, anon',
          ),
        );
        expect(
          rpcs,
          contains('grant execute on function public.$grant to authenticated'),
        );
      }
    });

    test('managing needs manage_circle, attaching a role manage_roles', () {
      for (final name in [
        'get_circle_guide_config',
        'set_circle_guide_prompts',
        'set_circle_guide_tasks',
        'set_circle_greeting',
      ]) {
        expect(body(rpcs, name), contains("'manage_circle'"), reason: name);
      }
      final prompts = body(rpcs, 'set_circle_guide_prompts');
      expect(prompts, contains("'manage_roles'"));
      expect(prompts, contains('circle_member_rank'));
    });

    test('a suspended circle (K1) answers and edits nothing', () {
      for (final name in [
        'get_circle_guide',
        'complete_onboarding_prompts',
        'complete_guide_task',
        'set_circle_guide_prompts',
        'set_circle_guide_tasks',
        'set_circle_greeting',
      ]) {
        expect(
          body(rpcs, name),
          contains('public.circle_is_suspended'),
          reason: name,
        );
      }
      expect(
        body(greeting, 'announce_new_circle_member'),
        contains('public.circle_is_suspended'),
      );
    });

    test('channels a member cannot see are not named', () {
      final guide = body(rpcs, 'get_circle_guide');
      expect(guide, contains('public.circle_channel_permissions'));
      expect(guide, contains('& 1 <> 0'));
    });

    test('a task is ticked off only for a visit', () {
      final task = body(rpcs, 'complete_guide_task');
      expect(task, contains("task.action <> 'visit_channel'"));
    });

    test('messages that count for a task are visible ones the member sent', () {
      final guide = body(rpcs, 'get_circle_guide');
      expect(guide, contains('m.sender_id = current_user_id'));
      expect(guide, contains("m.type <> 'system'"));
      expect(guide, contains('m.recalled_at is null'));
      expect(guide, contains('m.webhook_id is null'));
      expect(guide, contains("m.review_state is distinct from 'held'"));
    });
  });

  group('nothing older is rewritten', () {
    test('the functions other work depends on are left alone', () {
      final all = '$schema\n$rpcs\n$greeting';
      for (final name in [
        'get_circle_onboarding',
        'accept_circle_rules',
        'set_circle_onboarding',
        'circle_member_needs_rules',
        'set_member_roles',
        'update_circle_role',
        'create_circle_role',
        'sync_circle_admin_roles',
        'circle_member_permissions',
        'accept_circle_invite',
        'join_public_circle',
        'invite_circle_members',
        'decide_join_request',
        'get_circle_detail',
        'send_sticker',
        'aggregate_circle_insights',
        'run_later_dispatch',
      ]) {
        expect(all, isNot(contains('function public.$name(')), reason: name);
      }
    });

    test('no profile bio is read bare', () {
      for (final sql in [schema, rpcs, greeting]) {
        expect(sql, isNot(contains('.bio')));
      }
    });
  });

  group('the greeting', () {
    test('it follows every way into a circle, and never blocks one', () {
      expect(greeting, contains('after insert on public.circle_members'));
      final announce = body(greeting, 'announce_new_circle_member');
      expect(announce, contains('exception when others then'));
      expect(announce, contains('p.is_bot'));
      expect(announce, contains('c.owner_id = new.user_id'));
      expect(announce, contains("interval '7 days'"));
    });

    test('it is a system message with the newcomer\'s facts', () {
      final announce = body(greeting, 'announce_new_circle_member');
      expect(announce, contains("'system'"));
      expect(announce, contains("'kind', 'newcomer'"));
      expect(announce, contains("'user_id', new.user_id"));
      expect(announce, contains("'sticker_id', settings.greeting_sticker_id"));
    });
  });

  behaviourTest(
    'onboarding: roles are plain, questions, tasks, suspended circles and the greeting',
    'test/supabase/circle_onboarding_guide_behaviour.sql',
  );
}

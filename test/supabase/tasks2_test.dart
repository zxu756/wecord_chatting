import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for Task lists 2.0 (D7: migrations 202610250100 to
/// 202610250130), plus the behaviour script that plays fields, subtasks and
/// repeating tasks through the functions.
void main() {
  late Map<String, String> sql;

  setUpAll(() {
    sql = {
      for (final name in const [
        '202610250100_task_lists2_schema',
        '202610250110_task_lists2_rpcs',
        '202610250120_task_lists2_triggers',
        '202610250130_task_lists2_export',
      ])
        name: File('supabase/migrations/$name.sql').readAsStringSync(),
    };
  });

  test('hard-codes no user id and never runs unchecked as a client', () {
    final uuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );
    for (final entry in sql.entries) {
      expect(uuid.hasMatch(entry.value), isFalse, reason: entry.key);
    }
  });

  test('the new functions check the caller and are closed to anon', () {
    final rpcs = sql['202610250110_task_lists2_rpcs']!;
    expect(rpcs, contains('uid uuid := auth.uid();'));
    expect(rpcs, contains('security definer'));
    expect(rpcs, contains('set search_path = public'));
    expect(
      rpcs,
      contains(
        'revoke execute on function public.set_task_list_fields(uuid, jsonb) from public, anon;',
      ),
    );
    expect(
      rpcs,
      contains(
        'grant execute on function public.set_task_list_fields(uuid, jsonb) to authenticated;',
      ),
    );
    final export = sql['202610250130_task_lists2_export']!;
    expect(
      export,
      contains(
        'revoke execute on function public.export_my_task_extras(uuid) from public, anon, authenticated;',
      ),
    );
    expect(
      export,
      contains(
        'grant execute on function public.export_my_task_extras(uuid) to service_role;',
      ),
    );
  });

  test('the rewritten upsert keeps what the first version checked', () {
    final rpcs = sql['202610250110_task_lists2_rpcs']!;
    for (final needle in const [
      "raise exception 'You cannot edit this list'",
      'can_current_user_edit_task_list',
      'is_current_user_conversation_member',
      "'view_channel'",
      "raise exception 'This list is full'",
      "raise exception 'Only people in this conversation can be assigned'",
      "raise exception 'Message does not belong to this conversation'",
      "raise exception 'Unknown status'",
    ]) {
      expect(rpcs, contains(needle), reason: needle);
    }
  });

  test('the triggers do not rewrite run_later_dispatch', () {
    for (final entry in sql.entries) {
      expect(entry.value, isNot(contains('run_later_dispatch')));
    }
  });

  test('nothing in the schema asks for a new cron job or secret', () {
    for (final entry in sql.entries) {
      expect(entry.value, isNot(contains('cron.schedule')));
      expect(entry.value, isNot(contains('vault.')));
    }
  });

  behaviourTest(
    'task lists 2.0: fields, subtasks, repeating tasks, account closing, export',
    'test/supabase/tasks2_behaviour.sql',
  );
}

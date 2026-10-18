import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for forms and collection sheets, plus the behaviour script.
void main() {
  late String schema;
  late String rpcs;
  late String results;

  setUpAll(() {
    schema = File(
      'supabase/migrations/202610230100_forms_schema.sql',
    ).readAsStringSync();
    rpcs = File(
      'supabase/migrations/202610230110_forms_rpcs.sql',
    ).readAsStringSync();
    results = File(
      'supabase/migrations/202610230120_forms_results.sql',
    ).readAsStringSync();
  });

  test('clients can read forms but never write the tables', () {
    for (final table in ['forms', 'form_responses']) {
      expect(schema, contains('alter table public.$table enable row level'));
      expect(
        schema,
        contains('revoke all on public.$table from anon, authenticated;'),
      );
      expect(schema, contains('grant select on public.$table to authenticated;'));
    }
    expect(results, contains('alter table public.form_reminders enable row'));
    expect(
      results,
      contains('revoke all on public.form_reminders from anon, authenticated;'),
    );
  });

  test('a person reads only their own answer rows', () {
    expect(schema, contains('create policy form_responses_select_own'));
    expect(schema, contains('user_id = auth.uid()'));
  });

  test('every change goes through a function for signed-in people', () {
    final sql = '$rpcs\n$results';
    for (final signature in [
      'create_form(uuid, text, text, jsonb, jsonb)',
      'get_form(uuid)',
      'get_forms(uuid[])',
      'submit_form_response(uuid, jsonb)',
      'get_form_results(uuid)',
      'set_form_closed(uuid, boolean)',
      'remind_form_unfilled(uuid)',
    ]) {
      expect(
        sql,
        contains(
          'revoke execute on function public.$signature from public, anon;',
        ),
        reason: signature,
      );
      expect(
        sql,
        contains(
          'grant execute on function public.$signature to authenticated;',
        ),
        reason: signature,
      );
    }
  });

  test('forms are live over Realtime and refused in direct chats', () {
    expect(
      schema,
      contains('alter publication supabase_realtime add table public.forms'),
    );
    expect(rpcs, contains('chain_conversation_allowed'));
    expect(rpcs, contains("raise exception 'form_not_allowed'"));
  });

  test('the answers of an anonymous form never carry the user', () {
    // The anonymous branch builds its objects from the id and the answers.
    expect(
      results,
      contains("jsonb_build_object('id', r.id, 'answers', r.answers)"),
    );
  });

  behaviourTest(
    'forms validate answers, hide anonymous users, follow RLS and the deadline',
    'test/supabase/forms_behaviour.sql',
  );
}

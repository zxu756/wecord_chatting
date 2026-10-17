import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the polls upgrade, plus the behaviour script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610170023_poll_upgrade.sql',
    ).readAsStringSync();
  });

  test('quiz answers live where clients cannot read them', () {
    expect(sql, contains('create table if not exists public.poll_quiz_answers'));
    expect(sql, contains('revoke all on public.poll_quiz_answers from anon, authenticated;'));
    expect(sql, contains('enable row level security'));
  });

  test('the answer shows after voting, to the author and once closed', () {
    expect(sql, contains('reveal := is_closed'));
    expect(sql, contains('or poll.sender_id = auth.uid()'));
    expect(sql, contains('or jsonb_array_length(mine) > 0'));
  });

  test('quiz answers are final and single', () {
    expect(sql, contains("'A quiz answer cannot be changed'"));
    expect(sql, contains("'A quiz has one right answer'"));
    expect(sql, contains("'Nobody can add answers to a quiz'"));
  });

  test('anonymous polls hide who voted in the list and the table', () {
    expect(sql, contains("coalesce(m.attachment->>'anonymous', 'false') <> 'true'"));
    expect(sql, contains("m.attachment->>'anonymous' = 'true'"));
    expect(sql, contains('user_id = auth.uid()'));
  });

  test('the old five-argument call keeps working', () {
    expect(
      sql,
      contains(
        'drop function if exists public.create_poll(uuid, text, text[], boolean, integer);',
      ),
    );
    expect(sql, contains('quiz_correct_option integer default null'));
    expect(sql, contains('closes_at timestamptz default null'));
  });

  test('members add at most ten options, only when the poll allows it', () {
    expect(sql, contains("'This poll does not take new options'"));
    expect(sql, contains('if option_count >= 10 then'));
  });

  behaviourTest(
    'quizzes, anonymous votes, added options and deadlines work against a database',
    'test/supabase/poll_upgrade_behaviour.sql',
  );
}

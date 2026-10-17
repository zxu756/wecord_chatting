import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for profile visibility, plus the behaviour script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610170024_profile_visibility.sql',
    ).readAsStringSync();
  });

  test('three choices, everyone by default', () {
    expect(
      sql,
      contains("profile_visibility text not null default 'everyone'"),
    );
    expect(
      sql,
      contains(
        "profile_visibility in ('everyone', 'friends_and_circles', 'friends')",
      ),
    );
  });

  test('get_profile_summary hides the details, not the basics', () {
    final summary = sql.substring(
      sql.indexOf('create or replace function public.get_profile_summary'),
    );
    expect(summary, contains('not (select allowed from access)'));
    expect(summary, contains('as profile_hidden'));
    expect(summary, contains('target_user_id = auth.uid()'));
    // Names, avatars and the relationship are not behind the check.
    expect(summary, contains('p.display_name,'));
    expect(
      summary,
      isNot(
        contains(
          'not (select allowed from access) then null\n      else p.avatar_url',
        ),
      ),
    );
  });

  test('a friend or (for the middle setting) a shared circle gets in', () {
    expect(sql, contains('exists (select 1 from friendship)'));
    expect(sql, contains("v.setting = 'friends_and_circles'"));
    expect(sql, contains('join public.circle_members theirs'));
  });

  test('people can only change their own setting', () {
    expect(
      sql,
      contains('values (auth.uid(), set_profile_visibility.visibility)'),
    );
  });

  behaviourTest(
    'each setting shows the right people the right details',
    'test/supabase/profile_visibility_behaviour.sql',
  );
}

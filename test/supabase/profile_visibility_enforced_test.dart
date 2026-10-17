import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the profile visibility rule on every read path, plus the
/// behaviour script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610170101_profile_visibility_enforced.sql',
    ).readAsStringSync();
  });

  test('the profile-only columns are not granted to signed-in users', () {
    expect(
      sql,
      contains('revoke select on public.profiles from anon, authenticated;'),
    );
    final grant = RegExp(
      r'grant select \(([^)]*)\) on public\.profiles to authenticated;',
    ).firstMatch(sql);
    expect(grant, isNotNull);
    final columns = grant!.group(1)!;
    for (final hidden in ['bio', 'banner_url', 'pronouns']) {
      expect(columns, isNot(contains(hidden)));
    }
    for (final needed in ['id', 'username', 'display_name', 'avatar_url']) {
      expect(columns, contains(needed));
    }
  });

  test('every function that returns other people\'s bio is patched', () {
    for (final name in [
      'circle_event_profile',
      'forum_post_payload',
      'get_circle_detail',
      'list_message_reactors',
      'list_pinned_messages',
      'list_poll_voters',
    ]) {
      expect(sql, contains("'$name'"));
    }
  });

  test('the banner files follow the rule', () {
    expect(sql, contains('public.can_view_profile_details('));
    expect(sql, contains("bucket_id = 'profile-banners'"));
  });

  behaviourTest(
    'bio, pronouns and banner follow the setting on every path',
    'test/supabase/profile_visibility_enforced_behaviour.sql',
  );
}

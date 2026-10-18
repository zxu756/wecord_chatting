import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for feature flags and the minimum version (K4), official
/// notices (K6) and feedback (K7), plus the behaviour script.
void main() {
  String read(String name) =>
      File('supabase/migrations/$name').readAsStringSync();

  late String flags;
  late String flagsAdmin;
  late String notices;
  late String noticesAdmin;
  late String feedback;
  late String feedbackAdmin;

  setUpAll(() {
    flags = read('202610240600_feature_flags.sql');
    flagsAdmin = read('202610240610_feature_flags_admin.sql');
    notices = read('202610240620_announcements.sql');
    noticesAdmin = read('202610240630_announcements_admin.sql');
    feedback = read('202610240640_user_feedback.sql');
    feedbackAdmin = read('202610240650_feedback_admin.sql');
  });

  test('nobody reads or writes the new tables through the API', () {
    final all = '$flags\n$notices\n$feedback';
    for (final table in [
      'app_config',
      'feature_flags',
      'announcements',
      'announcement_states',
      'user_feedback',
    ]) {
      expect(all, contains('alter table public.$table enable row level'));
      expect(
        all,
        contains('revoke all on public.$table from public, anon, authenticated;'),
        reason: table,
      );
      expect(
        all,
        isNot(contains('grant select on public.$table')),
        reason: table,
      );
      expect(all, isNot(contains('create policy $table')), reason: table);
    }
  });

  test('every admin function checks the caller before anything else', () {
    final sql = '$flagsAdmin\n$noticesAdmin\n$feedbackAdmin';
    final functions = RegExp(
      r'create or replace function public\.(admin_\w+)\(',
    ).allMatches(sql).map((m) => m.group(1)!).toList();
    expect(functions, hasLength(greaterThanOrEqualTo(12)));
    for (final name in functions) {
      final start = sql.indexOf('function public.$name(');
      final body = sql.substring(start, sql.indexOf(r'$$;', start));
      expect(
        body,
        contains('perform public.admin_require('),
        reason: '$name must check the role',
      );
    }
  });

  test('only owners change flags and the minimum version', () {
    for (final name in [
      'admin_set_feature_flag',
      'admin_delete_feature_flag',
      'admin_set_min_version',
    ]) {
      final start = flagsAdmin.indexOf('function public.$name(');
      final body = flagsAdmin.substring(
        start,
        flagsAdmin.indexOf(r'$$;', start),
      );
      expect(body, contains("admin_require(array['owner'])"), reason: name);
    }
  });

  test('the push is limited: once per notice, one a day, never a reply', () {
    expect(noticesAdmin, contains("interval '24 hours'"));
    expect(noticesAdmin, contains("errcode = '53400'"));
    expect(notices, contains('announcements_push_only_for_everybody'));
    expect(
      noticesAdmin,
      contains(
        'grant execute on function public.claim_announcement_pushes(integer) '
        'to service_role;',
      ),
    );
    expect(
      noticesAdmin,
      contains(
        'revoke execute on function public.claim_announcement_pushes(integer)\n'
        '  from public, anon, authenticated;',
      ),
    );
  });

  test('screenshots are private and live in the sender folder', () {
    expect(feedback, contains("'feedback-screenshots',\n  'feedback-screenshots',\n  false,"));
    expect(feedback, contains('(storage.foldername(name))[1] = auth.uid()::text'));
    expect(feedback, contains('public.is_app_admin()'));
    expect(feedback, contains("errcode = 'PB429'"));
  });

  test('migrations stay in the numbers of this package and create no user', () {
    for (final entry in {
      '202610240600_feature_flags.sql': flags,
      '202610240610_feature_flags_admin.sql': flagsAdmin,
      '202610240620_announcements.sql': notices,
      '202610240630_announcements_admin.sql': noticesAdmin,
      '202610240640_user_feedback.sql': feedback,
      '202610240650_feedback_admin.sql': feedbackAdmin,
    }.entries) {
      expect(entry.value, isNot(contains('insert into auth.users')));
      // (The all-zero uuid is the start of a cursor, not a user.)
      final named = entry.value.replaceAll(
        "'00000000-0000-0000-0000-000000000000'",
        '',
      );
      expect(
        named,
        isNot(
          matches(
            RegExp(
              r"'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'",
            ),
          ),
        ),
        reason: '${entry.key} names no user id',
      );
    }
  });

  behaviourTest(
    'flags, notices and feedback follow the roles, the buckets and the limits',
    'test/supabase/admin_ops_behaviour.sql',
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs the behaviour checks for the group clean-up list (migration 202610170052): groups of different ages, what leaving can do and who sees what against the local Supabase
/// database when there is one (`supabase start`), inside a transaction that
/// is rolled back. Skipped when psql or the database is not there.
void main() {
  const databaseUrl = String.fromEnvironment(
    'WECORD_TEST_DATABASE_URL',
    defaultValue: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres',
  );

  Future<String?> unavailable() async {
    try {
      final probe = await Process.run('psql', [
        databaseUrl,
        '-Atc',
        "select to_regclass('public.messages') is not null "
            "and to_regclass('public.conversation_members') is not null "
            "and to_regproc('public.current_user_readable_conversation_ids') is not null",
      ]).timeout(const Duration(seconds: 10));
      if (probe.exitCode != 0 || '${probe.stdout}'.trim() != 't') {
        return 'no local database with the chat tables';
      }
      return null;
    } catch (_) {
      return 'psql is not available';
    }
  }

  test('inactive groups: listed by age, with what leaving can do', () async {
    final reason = await unavailable();
    if (reason != null) {
      markTestSkipped(reason);
      return;
    }
    final result = await Process.run('psql', [
      databaseUrl,
      '-v',
      'ON_ERROR_STOP=1',
      '-q',
      '-f',
      'test/supabase/inactive_groups_behaviour.sql',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

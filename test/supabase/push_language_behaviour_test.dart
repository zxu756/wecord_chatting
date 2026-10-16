import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs push_language_behaviour.sql against the local Supabase database
/// when there is one (`supabase start`): it applies the album and push
/// migrations in a transaction, claims pushes for a recipient on English and
/// one on Chinese, checks each gets its own text and rolls back. Skipped
/// when psql or the database is not there.
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
        "select to_regclass('public.push_subscriptions') is not null "
            "and exists (select 1 from information_schema.columns "
            "where table_name = 'messages' and column_name = 'attachment_group_id')",
      ]).timeout(const Duration(seconds: 10));
      if (probe.exitCode != 0 || '${probe.stdout}'.trim() != 't') {
        return 'no local database with the album migration';
      }
      return null;
    } catch (_) {
      return 'psql is not available';
    }
  }

  test('pushes are written in the language of the subscription', () async {
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
      'test/supabase/push_language_behaviour.sql',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 2)));
}

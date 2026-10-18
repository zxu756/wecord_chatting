import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs a behaviour script against the local Supabase database (`supabase
/// start`) when there is one. The scripts apply the migrations under test
/// inside a transaction and roll back, so the database is left as it was.
/// Skipped when psql or the database is not there.
const _databaseUrl = String.fromEnvironment(
  'WECORD_TEST_DATABASE_URL',
  defaultValue: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres',
);

Future<String?> _unavailable({bool rebuildsSchema = false}) async {
  try {
    final probe = await Process.run('psql', [
      _databaseUrl,
      '-Atc',
      // A script that rebuilds the schema from every migration needs a
      // database, not a particular migration state.
      rebuildsSchema
          ? 'select true'
          : "select to_regclass('public.messages') is not null "
                "and exists (select 1 from information_schema.columns "
                "where table_name = 'messages' and column_name = 'attachment_group_id')",
    ]).timeout(const Duration(seconds: 10));
    if (probe.exitCode != 0 || '${probe.stdout}'.trim() != 't') {
      return rebuildsSchema
          ? 'no local database'
          : 'no local database with the album migration';
    }
    return null;
  } catch (_) {
    return 'psql is not available';
  }
}

/// A test that runs [script] (a path from the repository root) with psql
/// and fails with its output when the script raises. A script that drops and
/// rebuilds the whole `public` schema itself passes [rebuildsSchema], so a
/// database at any migration state will do.
void behaviourTest(String name, String script, {bool rebuildsSchema = false}) {
  test(name, () async {
    final reason = await _unavailable(rebuildsSchema: rebuildsSchema);
    if (reason != null) {
      markTestSkipped(reason);
      return;
    }
    final result = await Process.run('psql', [
      _databaseUrl,
      '-v',
      'ON_ERROR_STOP=1',
      '-q',
      '-f',
      script,
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 6)));
}

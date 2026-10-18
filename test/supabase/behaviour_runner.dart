import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs a behaviour script against the local Supabase database (`supabase
/// start`) when there is one. The scripts apply the migrations under test
/// inside a transaction and roll back, so the database is left as it was.
/// Skipped only when psql or the database is not there.
///
/// Baseline: the local database is reset to migration 202610170001
/// (`supabase db reset --version 202610170001`). A script `\i`-includes, in
/// order, every migration from 202610170002 up to the newest one it tests,
/// or rebuilds the schema itself as security_audit_behaviour.sql does.
const _databaseUrl = String.fromEnvironment(
  'WECORD_TEST_DATABASE_URL',
  defaultValue: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres',
);

Future<String?> _unavailable() async {
  try {
    final probe = await Process.run('psql', [
      _databaseUrl,
      '-Atc',
      "select to_regclass('public.messages') is not null",
    ]).timeout(const Duration(seconds: 10));
    if (probe.exitCode != 0 || '${probe.stdout}'.trim() != 't') {
      return 'no local database';
    }
    return null;
  } catch (_) {
    return 'psql is not available';
  }
}

/// A test that runs [script] (a path from the repository root) with psql
/// and fails with its output when the script raises.
void behaviourTest(String name, String script) {
  test(name, () async {
    final reason = await _unavailable();
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

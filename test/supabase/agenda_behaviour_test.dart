import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Runs agenda_behaviour.sql against the local Supabase database when there
/// is one (`supabase start`): it applies the agenda and calendar feed
/// migrations (and the chat migrations they read) in a transaction, plays
/// people through My agenda (leaving a group, a circle, blocking, expired and
/// held messages) and the calendar subscription token (hashing, reset, rate
/// limit), and rolls back. Skipped when psql or the database is not there.
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
            "and to_regclass('public.circle_events') is not null "
            "and to_regclass('public.circle_event_rsvps') is not null "
            "and to_regproc('public.current_user_readable_conversation_ids') is not null "
            "and to_regproc('public.circle_event_ends_at') is not null",
      ]).timeout(const Duration(seconds: 10));
      if (probe.exitCode != 0 || '${probe.stdout}'.trim() != 't') {
        return 'no local database with the chat and circle tables';
      }
      return null;
    } catch (_) {
      return 'psql is not available';
    }
  }

  test('my agenda honours visibility and the feed token behaves', () async {
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
      'test/supabase/agenda_behaviour.sql',
    ]);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  }, timeout: const Timeout(Duration(minutes: 4)));
}

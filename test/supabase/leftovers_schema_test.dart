import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for the leftovers of the 2026-10-16 batch.
void main() {
  String migration(String prefix) {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere(
          (file) => file.uri.pathSegments.last.startsWith(prefix),
          orElse: () => throw StateError('Missing migration $prefix'),
        );
    return file.readAsStringSync();
  }

  test('circle emoji changes reach open clients through realtime', () {
    final sql = migration('202610160014');

    expect(
      sql,
      contains('alter table public.circle_emojis replica identity full'),
    );
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.circle_emojis',
      ),
    );
    expect(sql, contains("tablename = 'circle_emojis'"));
  });
}

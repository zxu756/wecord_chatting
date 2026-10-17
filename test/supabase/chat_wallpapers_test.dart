import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for chat wallpapers (migration 202610170110), plus the
/// behaviour script for row level security and the private bucket.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610170110_chat_wallpapers.sql',
    ).readAsStringSync();
  });

  test('wallpapers are owner-only rows', () {
    expect(sql, contains('create table if not exists public.chat_wallpapers'));
    expect(
      sql,
      contains('alter table public.chat_wallpapers enable row level'),
    );
    for (final policy in ['select', 'insert', 'update', 'delete']) {
      expect(sql, contains('chat_wallpapers_${policy}_own'));
    }
    expect(sql, isNot(contains('to anon')));
    expect(sql, contains('from anon, authenticated'));
  });

  test('the photos bucket is private, small and image only', () {
    expect(sql, contains("'wallpapers'"));
    expect(sql, contains('false,\n  3145728'));
    expect(sql, contains("array['image/jpeg', 'image/png', 'image/webp']"));
    for (final policy in ['select', 'insert', 'update', 'delete']) {
      expect(sql, contains('wallpapers_${policy}_owner'));
    }
  });

  behaviourTest(
    'wallpapers: own rows only, private photos, plain names',
    'test/supabase/chat_wallpapers_behaviour.sql',
  );
}

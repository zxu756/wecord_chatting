import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for chat folders (migration 202610210200), plus the
/// behaviour script for row level security and the 20-folder cap.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610210200_chat_folders.sql',
    ).readAsStringSync();
  });

  test('folders are owner-only rows', () {
    expect(sql, contains('create table if not exists public.chat_folders'));
    expect(sql, contains('alter table public.chat_folders enable row level'));
    for (final policy in ['select', 'insert', 'update', 'delete']) {
      expect(sql, contains('chat_folders_${policy}_own'));
    }
    expect(sql, isNot(contains('to anon')));
    expect(sql, contains('from anon, authenticated'));
  });

  test('a folder stores rules only, never chats', () {
    for (final column in [
      'include_types',
      'include_ids',
      'exclude_ids',
      'only_unread',
      'exclude_muted',
    ]) {
      expect(sql, contains(column));
    }
    expect(sql, isNot(contains('references public.conversations')));
    expect(sql, isNot(contains('public.messages')));
  });

  test('the cap of 20 is a trigger that takes a lock per person', () {
    expect(sql, contains('>= 20'));
    expect(sql, contains('pg_advisory_xact_lock'));
    expect(sql, contains('before insert on public.chat_folders'));
  });

  test('changes reach the other devices', () {
    expect(sql, contains('alter publication supabase_realtime add table'));
    expect(sql, contains('replica identity full'));
  });

  behaviourTest(
    'folders: own rows only, shape rules, 20 per person, reorder',
    'test/supabase/chat_folders_behaviour.sql',
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for picture descriptions (L8: migration 202610250510), plus
/// the behaviour script that plays what a merged forward keeps.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610250510_merged_forward_alt_text.sql',
    ).readAsStringSync();
  });

  test('stores nothing and hard-codes no user id', () {
    final uuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );
    expect(uuid.hasMatch(sql), isFalse);
    expect(sql, isNot(contains('create table')));
    expect(sql, isNot(contains('alter table')));
    expect(sql, isNot(contains('insert into')));
    expect(sql, isNot(contains('update public.')));
  });

  test('redefines only the key whitelist, and keeps the earlier rules', () {
    // The only function it touches.
    expect(RegExp(r'create or replace function').allMatches(sql).length, 1);
    expect(
      sql,
      contains('function public.merged_forward_attachment(att jsonb)'),
    );
    // From the first version: only these buckets, and the same keys.
    expect(
      sql,
      contains(
        "att->>'bucket' not in ('chat-images', 'voice-messages', 'chat-files')",
      ),
    );
    for (final key in [
      'kind',
      'bucket',
      'path',
      'name',
      'mime_type',
      'size',
      'width',
      'height',
      'blurhash',
      'duration_ms',
    ]) {
      expect(sql, contains("'$key'"), reason: key);
    }
    // View-once is not among them.
    expect(sql, isNot(contains("'view_once'")));
  });

  test('the description is text and at most 1000 characters', () {
    expect(sql, contains("'alt'"));
    expect(sql, contains("jsonb_typeof(e.value) = 'string'"));
    expect(sql, contains('left(e.value #>> \'{}\', 1000)'));
  });

  test('stays closed to the app\'s roles', () {
    expect(
      sql,
      contains(
        'revoke execute on function public.merged_forward_attachment(jsonb)',
      ),
    );
  });

  behaviourTest(
    'a merged forward keeps the description',
    'test/supabase/image_alt_text_behaviour.sql',
  );
}

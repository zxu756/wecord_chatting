import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for QR codes, pat-pat and the note to self (migrations
/// 202610180030 to 202610180034), plus the behaviour script that plays
/// people through them on the local database.
void main() {
  String migration(String prefix) => Directory('supabase/migrations')
      .listSync()
      .whereType<File>()
      .singleWhere((file) => file.uri.pathSegments.last.startsWith(prefix))
      .readAsStringSync();

  test('QR codes are opaque, closed tables reached through functions', () {
    final user = migration('202610180030');
    expect(user, contains('create table if not exists public.user_qr_codes'));
    expect(user, contains('code text not null unique'));
    expect(user, contains('revoke all on public.user_qr_codes'));
    expect(user, contains('extensions.gen_random_bytes(16)'));
    expect(user, isNot(contains('to anon')));

    final group = migration('202610180031');
    expect(group, contains("now() + interval '7 days'"));
    expect(group, contains("cm.role in ('owner', 'admin')"));
    expect(group, contains('revoke all on public.group_qr_codes'));
  });

  test('pats are rate limited and never pushed or unread', () {
    final pat = migration('202610180032');
    expect(pat, contains("interval '10 seconds'"));
    expect(pat, contains('>= 20'));
    expect(pat, contains("interval '2 minutes'"));
    expect(pat, contains("conversation_type not in ('direct', 'group')"));
    final list = migration('202610180034');
    expect(list, contains("attachment->>'kind' = 'pat'"));
    expect(list, contains('is_note_to_self'));
  });

  test('the note to self takes one member and is made once', () {
    final note = migration('202610180033');
    expect(note, contains('user_id uuid primary key'));
    expect(note, contains('conversation_id uuid not null unique'));
    expect(note, contains('note_to_self_only_owner'));
  });

  behaviourTest(
    'QR codes, pat-pat and the note to self behave on the database',
    'test/supabase/qr_pat_note_behaviour.sql',
  );
}

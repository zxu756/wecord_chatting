import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for call links (migration 202610170040).
void main() {
  late String sql;

  setUpAll(() {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere(
          (file) => file.uri.pathSegments.last.startsWith('202610170040'),
        );
    sql = file.readAsStringSync();
  });

  test('a link points at exactly one chat or voice channel', () {
    expect(sql, contains('create table if not exists public.call_links'));
    expect(sql, contains('(conversation_id is null) <> (channel_id is null)'));
    expect(sql, contains('code text not null unique'));
    expect(sql, contains('references public.circle_channels(id)'));
  });

  test('links expire after a day, a week or never, and can be revoked', () {
    expect(sql, contains("interval '24 hours'"));
    expect(sql, contains("interval '7 days'"));
    expect(sql, contains("when 'never' then null"));
    expect(sql, contains('revoked_at'));
    expect(sql, contains('function public.revoke_call_link'));
  });

  test('links belong to their creator', () {
    expect(sql, contains('using (created_by = auth.uid())'));
    expect(sql, contains('revoke insert, update, delete on public.call_links'));
    // Revoking and listing only look at the caller's own links.
    expect(sql, contains('and cl.created_by = auth.uid()'));
  });

  test('making and opening a link check the same access as joining', () {
    expect(sql, contains('can_current_user_call_in_conversation'));
    expect(sql, contains('can_current_user_connect_voice'));
    // Someone who could not join learns nothing about the target.
    expect(sql, contains("jsonb_build_object('status', 'no_access')"));
    final access = sql.indexOf("'no_access'");
    final name = sql.indexOf("'name', call_name");
    expect(access, lessThan(name));
  });

  test('only signed-in users can use the functions', () {
    for (final signature in [
      'create_call_link(uuid, uuid, text)',
      'list_call_links(uuid, uuid)',
      'revoke_call_link(text)',
      'resolve_call_link(text)',
    ]) {
      expect(
        sql,
        contains(
          'revoke execute on function public.$signature from public, anon',
        ),
      );
      expect(
        sql,
        contains(
          'grant execute on function public.$signature to authenticated',
        ),
      );
    }
  });
}

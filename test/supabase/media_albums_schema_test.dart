import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for albums: pictures, videos and files sent together.
void main() {
  late String sql;

  setUpAll(() {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere(
          (file) => file.uri.pathSegments.last.startsWith('202610170001'),
        );
    sql = file.readAsStringSync();
  });

  test('messages get an album id, limited to pictures and files', () {
    expect(sql, contains('add column if not exists attachment_group_id uuid'));
    expect(sql, contains('messages_attachment_group_type'));
    expect(
      sql,
      contains(
        "check (attachment_group_id is null or type in ('image', 'file'))",
      ),
    );
    expect(
      sql,
      contains('on public.messages (conversation_id, attachment_group_id)'),
    );
    expect(sql, contains('where attachment_group_id is not null'));
  });

  test('an album holds at most ten messages', () {
    expect(sql, contains('album_size >= 10'));
    expect(sql, contains("'An album can hold up to 10 items'"));
  });

  test('slowmode counts an album as one send, for two minutes', () {
    expect(sql, contains("interval '2 minutes'"));
    // The album rule comes after the permission and forum checks and before
    // slowmode itself, so it never lets anything past them.
    final permission = sql.indexOf("'send_messages'");
    final forum = sql.indexOf("channel.kind = 'forum'");
    final album = sql.indexOf('new.attachment_group_id is not null');
    final slowmode = sql.indexOf('pg_advisory_xact_lock');
    expect(permission, lessThan(forum));
    expect(forum, lessThan(album));
    expect(album, lessThan(slowmode));
  });

  test('the send trigger stays locked down', () {
    for (final role in ['public', 'anon', 'authenticated']) {
      expect(
        sql,
        contains(
          'revoke execute on function public.check_channel_message_send() from $role',
        ),
      );
    }
    expect(sql, contains('security definer'));
    expect(sql, contains('set search_path = public'));
  });
}

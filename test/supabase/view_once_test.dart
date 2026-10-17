import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for view-once media, plus the behaviour script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610170021_view_once_media.sql',
    ).readAsStringSync();
  });

  test('the only way in is open_view_once, once per person', () {
    expect(sql, contains('create or replace function public.open_view_once'));
    expect(sql, contains("'view_once_already_opened'"));
    expect(sql, contains('on conflict do nothing'));
    expect(sql, contains('primary key (message_id, user_id)'));
  });

  test('Storage stays closed to everyone but the sender and the opener', () {
    expect(sql, contains('as restrictive for select'));
    expect(sql, contains("bucket_id not in ('chat-images', 'chat-files')"));
    expect(sql, contains("o.opened_at > now() - interval '2 minutes'"));
    expect(sql, contains("m.attachment->>'view_once' = 'true'"));
    // Found through a partial index, not a scan of every message.
    expect(sql, contains('messages_view_once_path_idx'));
    expect(sql, contains("where attachment->>'view_once' = 'true'"));
  });

  test(
    'clients cannot write opens and see only their own or their media\'s',
    () {
      expect(sql, contains('revoke all on public.message_view_once_opens'));
      expect(sql, contains('grant select on public.message_view_once_opens'));
      expect(sql, contains('user_id = auth.uid()'));
      expect(sql, contains('m.sender_id = auth.uid()'));
    },
  );

  test('view-once is refused where it makes no sense and never forwarded', () {
    expect(sql, contains("conversation_kind not in ('direct', 'group')"));
    expect(sql, contains('new.attachment_group_id is not null'));
    expect(sql, contains('cannot be forwarded'));
    expect(sql, contains("new.body := '';"));
  });

  test('the shared media list leaves it out', () {
    expect(
      sql,
      contains("coalesce(m.attachment->>'view_once', 'false') <> 'true'"),
    );
  });

  behaviourTest(
    'sending, opening once, Storage access and the media list work against a database',
    'test/supabase/view_once_behaviour.sql',
  );
}

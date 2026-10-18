import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for personal stickers (A11), plus the behaviour script.
void main() {
  late String library;
  late String sending;

  setUpAll(() {
    library = File(
      'supabase/migrations/202610220500_user_stickers.sql',
    ).readAsStringSync();
    sending = File(
      'supabase/migrations/202610220510_send_personal_sticker.sql',
    ).readAsStringSync();
  });

  test('the table is owner only, with a cap of 300', () {
    expect(library, contains('alter table public.user_stickers enable row'));
    expect(library, contains('revoke all on public.user_stickers from anon;'));
    for (final policy in ['select', 'insert', 'update', 'delete']) {
      expect(library, contains('create policy user_stickers_${policy}_owner'));
    }
    expect(library, contains('owner_id = auth.uid()'));
    // Only the order can change by hand.
    expect(
      library,
      contains('grant update (sort_key) on public.user_stickers'),
    );
    expect(library, contains(">= 300"));
    expect(library, contains("errcode = '54000'"));
    expect(library, contains('create trigger user_stickers_check_insert'));
  });

  test('the bucket is private, 1 MB and images only', () {
    expect(library, contains("'user-stickers'"));
    expect(library, contains('false,\n  1048576,'));
    expect(library, contains("array['image/png', 'image/gif', 'image/webp']"));
    for (final policy in ['select', 'insert', 'delete']) {
      expect(
        library,
        contains('create policy user_stickers_storage_${policy}_owner'),
      );
    }
    // Every storage policy is the owner's own folder; none opens the bucket
    // to members of a chat or a circle.
    expect(
      RegExp(
        r'\(storage\.foldername\(name\)\)\[1\] = auth\.uid\(\)::text',
      ).allMatches(library).length,
      3,
    );
    expect(library, isNot(contains('is_current_user_conversation_member')));
    expect(library, isNot(contains('is_current_user_circle_member')));
  });

  test('sending names a copy in the conversation folder, not the library', () {
    expect(
      sending,
      contains('create or replace function public.send_personal_sticker'),
    );
    expect(sending, contains("'bucket', 'chat-images'"));
    expect(sending, contains("'personal', true"));
    expect(sending, contains("'sticker'"));
    expect(sending, contains('target_conversation_id::text'));
    expect(sending, contains('is_current_user_conversation_member'));
    expect(sending, contains('is_current_user_blocked_in_conversation'));
    expect(sending, contains("set_config('wecord.automod_soft', 'on', true)"));
    expect(
      sending,
      contains(
        'revoke execute on function public.send_personal_sticker(uuid, uuid, text) from public, anon;',
      ),
    );
    // The library's path never goes into a message.
    expect(sending, isNot(contains("'path', library_sticker.path")));
    // Existing functions are not rewritten.
    expect(sending, isNot(contains('function public.send_sticker(')));
    expect(
      library,
      isNot(contains('function public.messages_check_attachment_path')),
    );
  });

  behaviourTest(
    'RLS, the cap, the private bucket and sending into chats',
    'test/supabase/user_stickers_behaviour.sql',
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for paged chat history and outbox sends.
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

  test('history pages have a keyset index and page reactions', () {
    final sql = migration('202610160046');

    expect(
      sql,
      contains(
        'on public.messages (conversation_id, created_at desc, id desc)',
      ),
    );
    expect(
      sql,
      contains('drop index if exists public.messages_conversation_created_idx'),
    );
    expect(
      sql,
      contains(
        'create or replace function public.list_conversation_reactions(\n'
        '  target_conversation_id uuid,\n'
        '  target_message_ids uuid[]\n'
        ')',
      ),
    );
    expect(sql, contains('mr.message_id = any(target_message_ids)'));
    // Membership is checked, and the page size bounded.
    expect(sql, contains('is_current_user_conversation_member'));
    expect(sql, contains('cardinality(target_message_ids) > 500'));
    expect(
      sql,
      contains(
        'grant execute on function public.list_conversation_reactions(uuid, uuid[]) to authenticated',
      ),
    );
    expect(
      sql,
      contains(
        'revoke execute on function public.list_conversation_reactions(uuid, uuid[]) from anon',
      ),
    );
  });

  test('messages keep one copy per sender and client id', () {
    final sql = migration('202610160047');

    expect(sql, contains('add column if not exists client_id uuid'));
    expect(
      sql,
      contains(
        'add constraint messages_sender_client_id_key unique (sender_id, client_id)',
      ),
    );
    expect(
      sql,
      contains(
        'drop function if exists public.send_text_message(uuid, text, uuid, jsonb, jsonb)',
      ),
    );
    expect(sql, contains('client_id uuid default null'));
    // A repeated send answers with the stored message.
    expect(sql, contains('and m.client_id = send_text_message.client_id'));
    expect(sql, contains('exception when unique_violation'));
    // AutoMod keeps refusing quietly.
    expect(sql, contains("set_config('wecord.automod_soft', 'on', true)"));
    expect(
      sql,
      contains(
        'grant execute on function public.send_text_message(uuid, text, uuid, jsonb, jsonb, uuid) to authenticated',
      ),
    );
  });
}

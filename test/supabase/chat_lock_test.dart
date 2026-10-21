import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// The app lock and chat lock (migration 202610260300): the list of locked
/// chats in the notification settings, the functions the push functions and
/// the AI features call, and the behaviour script.
void main() {
  late String migration;

  setUpAll(() {
    migration = File(
      'supabase/migrations/202610260300_chat_lock.sql',
    ).readAsStringSync();
  });

  test('the list is a column of the notification settings, capped', () {
    expect(
      migration,
      contains(
        'add column if not exists locked_conversation_ids uuid[] not null default',
      ),
    );
    expect(migration, contains('cardinality(locked_conversation_ids) <= 200'));
    // It lives in the owner-only table; no new table, no new policy.
    expect(migration, isNot(contains('create table')));
    expect(migration, isNot(contains('create policy')));
    expect(migration, isNot(contains('to anon')));
  });

  test('only a person\'s own direct and group chats can be locked', () {
    expect(migration, contains("cv.type in ('direct', 'group')"));
    expect(migration, contains('conversation_members'));
  });

  test('the internal functions are for the service role only', () {
    for (final signature in [
      'is_conversation_locked(uuid, uuid)',
      'locked_chat_push_text(jsonb)',
    ]) {
      expect(
        migration,
        contains('revoke execute on function public.$signature'),
        reason: signature,
      );
      expect(
        migration,
        contains('grant execute on function public.$signature'),
        reason: signature,
      );
    }
    expect(
      migration,
      contains(
        'grant execute on function public.set_conversation_locked(uuid, boolean) to authenticated;',
      ),
    );
    expect(
      migration,
      isNot(contains('is_conversation_locked(uuid, uuid) to authenticated')),
    );
  });

  test('the push text is worded in both languages and names nothing', () {
    expect(migration, contains("s.language = 'zh'"));
    expect(migration, contains('你收到一条新消息'));
    expect(migration, contains('You have a new message'));
    final start = migration.indexOf(
      'create or replace function public.locked_chat_push_text',
    );
    final end = migration.indexOf(
      'revoke execute on function public.locked_chat_push_text',
    );
    final body = migration.substring(start, end);
    expect(body, isNot(contains('display_name')));
    expect(body, isNot(contains('public.messages')));
    expect(body, isNot(contains('public.profiles')));
    expect(body, isNot(contains('public.conversations')));
  });

  test('the claim functions are left alone', () {
    expect(
      migration,
      isNot(contains('create or replace function public.claim_')),
    );
    expect(migration, isNot(contains('run_later_dispatch')));
  });

  test('the readers of chat content are patched in place, not rewritten', () {
    for (final name in [
      'ai_digest_messages(uuid, timestamptz, timestamptz)',
      'list_my_ai_digests()',
      'ai_ask_conversations(uuid, jsonb)',
    ]) {
      expect(
        migration,
        contains("pg_get_functiondef('public.$name'::regprocedure)"),
      );
    }
    expect(
      migration,
      isNot(contains('create or replace function public.ai_digest_messages')),
    );
    expect(
      migration,
      isNot(contains('create or replace function public.ai_ask_conversations')),
    );
    expect(
      migration,
      isNot(contains('create or replace function public.list_my_ai_digests')),
    );
    // A patch that finds nothing to change stops the migration.
    expect('patch it by hand'.allMatches(migration).length, 3);
  });

  behaviourTest(
    'chat lock: locking, the push text, and what the AI features leave out',
    'test/supabase/chat_lock_behaviour.sql',
  );
}

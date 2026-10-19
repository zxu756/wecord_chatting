import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for Ask AI (migration 202610250300, roadmap F1 stage 1), plus
/// the behaviour script: the scope check, the keyword search, the visibility
/// rules and the second check of the sources.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610250300_ai_ask.sql',
    ).readAsStringSync();
  });

  test('hard-codes no user id', () {
    final uuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );
    expect(uuid.hasMatch(sql), isFalse);
  });

  test('reads with the visibility rules of the other AI features', () {
    expect(sql, contains('current_user_readable_conversation_ids'));
    expect(sql, contains('search_scope_conversation_ids'));
    expect(sql, contains('conversation_ai_assistant_allowed'));
    expect(sql, contains('user_ai_settings'));
    expect(sql, contains('m.recalled_at is null'));
    expect(sql, contains('m.review_state is null'));
    expect(sql, contains('m.expires_at is null or m.expires_at > now()'));
    expect(sql, contains("m.attachment->>'view_once'"));
    expect(sql, contains('are_users_blocked'));
    expect(sql, contains('m.ai_reply is null'));
    expect(sql, contains('message_search_entries'));
  });

  test('puts words in the query as literals, never as SQL', () {
    expect(sql, contains('%L'));
    expect(sql, contains('search_like_pattern'));
    expect(sql, contains('limit 6'));
    expect(sql, contains('group_count >= 3'));
    expect(sql, contains('least(greatest(coalesce(p_limit, 50), 1), 50)'));
  });

  test('every function is for the service role only', () {
    for (final name in [
      'ai_ask_conversations(uuid, jsonb)',
      'ai_ask_scope(uuid, jsonb)',
      'ai_ask_search(uuid, text[], jsonb, integer)',
      'ai_ask_visible(uuid, uuid[])',
    ]) {
      expect(
        sql,
        contains(
          'revoke execute on function public.$name\n  from public, anon, authenticated',
        ),
        reason: name,
      );
      expect(
        sql,
        contains('grant execute on function public.$name to service_role'),
        reason: name,
      );
    }
    expect(sql, isNot(contains('to authenticated')));
  });

  test('is security definer with a fixed search path', () {
    expect('security definer'.allMatches(sql).length, 4);
    expect('set search_path = public'.allMatches(sql).length, 4);
  });

  behaviourTest(
    'ask AI: scope, search, visibility and the sources check',
    'test/supabase/ai_ask_behaviour.sql',
  );
}

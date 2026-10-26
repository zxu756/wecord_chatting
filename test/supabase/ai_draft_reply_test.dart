import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for AI reply suggestions (migration 202610280800, roadmap
/// F6), plus the behaviour script: what the `draft_reply` action may read.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610280800_ai_draft_reply.sql',
    ).readAsStringSync();
  });

  test('hard-codes no user id and stores nothing', () {
    final uuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );
    expect(uuid.hasMatch(sql), isFalse);
    expect(sql, isNot(contains('create table')));
    expect(sql, isNot(contains('create policy')));
  });

  test('reads with the visibility rules of the other AI features', () {
    expect(sql, contains('current_user_readable_conversation_ids'));
    expect(sql, contains('conversation_ai_assistant_allowed'));
    expect(sql, contains('is_conversation_locked'));
    expect(sql, contains('user_ai_settings'));
    expect(sql, contains('m.recalled_at is null'));
    expect(sql, contains('m.review_state is null'));
    expect(sql, contains('m.expires_at is null or m.expires_at > now()'));
    expect(sql, contains("m.attachment->>'view_once'"));
    expect(sql, contains('are_users_blocked'));
    expect(sql, contains('m.ai_reply is null'));
    expect(sql, contains("m.type <> 'system'"));
    expect(sql, contains('least(greatest(coalesce(p_limit, 20), 1), 30)'));
  });

  test('is for the service role only, security definer, fixed search path', () {
    const name = 'public.ai_draft_context(uuid, uuid, integer)';
    expect(
      sql,
      contains(
        'revoke execute on function $name\n  from public, anon, authenticated',
      ),
    );
    expect(sql, contains('grant execute on function $name to service_role'));
    expect(sql, isNot(contains('to authenticated')));
    expect('security definer'.allMatches(sql).length, 1);
    expect('set search_path = public'.allMatches(sql).length, 1);
  });

  test('does not touch older functions', () {
    expect(
      RegExp(
        r'create or replace function (\S+)',
      ).allMatches(sql).map((m) => m.group(1)).toList(),
      ['public.ai_draft_context('],
    );
    expect(sql, isNot(contains('.bio')));
  });

  behaviourTest(
    'draft reply: what may be read, the AI switches and the chat lock',
    'test/supabase/ai_draft_reply_behaviour.sql',
  );
}

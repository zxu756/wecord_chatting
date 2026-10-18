import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the AI guard, plus the behaviour script.
void main() {
  late String core;
  late String hidden;

  setUpAll(() {
    core = File(
      'supabase/migrations/202610170090_ai_guard.sql',
    ).readAsStringSync();
    hidden = File(
      'supabase/migrations/202610170091_ai_guard_hidden.sql',
    ).readAsStringSync();
  });

  test('the guard is off by default and clients cannot touch its tables', () {
    expect(core, contains('enabled boolean not null default false'));
    for (final table in [
      'circle_ai_guard',
      'message_reviews',
      'ai_circle_usage',
    ]) {
      expect(core, contains('alter table public.$table enable row level'));
      expect(
        core,
        contains('revoke all on public.$table from anon, authenticated;'),
      );
    }
  });

  test('only the server decides, and only the service role answers', () {
    expect(core, contains('new.review_state := null;'));
    for (final function in [
      'finish_message_review(uuid, text, text, text)',
      'ai_guard_claim(uuid)',
      'ai_consume_circle_request(uuid, integer)',
      'claim_released_message_pushes()',
      'run_ai_guard_sweep()',
    ]) {
      expect(
        core,
        contains(
          'revoke execute on function public.$function from public, anon, authenticated;',
        ),
      );
      expect(
        core,
        contains('grant execute on function public.$function to service_role;'),
      );
    }
  });

  test('the database wakes the function through Vault and pg_net', () {
    expect(core, contains("d.name = 'wecord_functions_url'"));
    expect(core, contains("d.name = 'wecord_dispatch_secret'"));
    expect(core, contains('net.http_post('));
    expect(core, contains("'Bearer ' || dispatch_secret"));
    expect(core, contains("'action', 'guard'"));
    // Fails open: no way to wake it releases the message.
    expect(core, contains("'not_checked', null, 'unavailable'"));
    // A sweep releases checks that never came back.
    expect(core, contains("'not_checked', null, 'timeout'"));
    expect(core, contains("'wecord-ai-guard-sweep'"));
  });

  test('every decision is audited', () {
    for (final action in [
      'guard_update',
      'guard_hold',
      'guard_flag',
      'guard_approve',
      'guard_remove',
    ]) {
      expect(core, contains(action));
    }
  });

  test('the readers of messages leave out a message under review', () {
    expect(hidden, contains('review_state is null'));
    expect(hidden, contains('create policy messages_select_member'));
    for (final function in [
      'touch_conversation_from_message',
      'touch_thread_from_message',
      'sync_message_search_entry',
      'claim_push_delivery',
      'list_conversation_summaries',
      'list_circle_summaries',
      'thread_payload',
      'forum_post_payload',
      'search_message_context',
      'list_pinned_messages',
      'bot_api_list_messages',
      'forward_message',
    ]) {
      expect(
        hidden,
        contains('create or replace function public.$function('),
        reason: function,
      );
    }
    expect(hidden, contains('or message.review_state is not null'));
  });

  test('the Chinese reason has its own column and reaches the queue', () {
    final zh = File(
      'supabase/migrations/202610200020_ai_guard_reason_zh.sql',
    ).readAsStringSync();
    expect(zh, contains('add column if not exists reason_zh text;'));
    expect(
      zh,
      contains(
        'drop function if exists public.finish_message_review(uuid, text, text, text);',
      ),
    );
    expect(zh, contains('p_reason_zh text default null'));
    expect(zh, contains('reason_zh text\n)'));
    expect(
      zh,
      contains(
        'revoke execute on function public.finish_message_review(uuid, text, text, text, text) from public, anon, authenticated;',
      ),
    );
    expect(
      zh,
      contains(
        'grant execute on function public.finish_message_review(uuid, text, text, text, text) to service_role;',
      ),
    );
  });

  behaviourTest(
    'holding, visibility, release, fail-open and no push before release',
    'test/supabase/ai_guard_behaviour.sql',
  );
}

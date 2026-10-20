import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for AI guard 2.0 (migrations 202610260200 and 202610260210,
/// roadmap F7) and the link-preview column (202610260220, G5), plus the
/// behaviour script.
void main() {
  late String scope;
  late String items;
  late String link;

  setUpAll(() {
    scope = File(
      'supabase/migrations/202610260200_guard2_scope.sql',
    ).readAsStringSync();
    items = File(
      'supabase/migrations/202610260210_guard2_items.sql',
    ).readAsStringSync();
    link = File(
      'supabase/migrations/202610260220_link_preview_final_url.sql',
    ).readAsStringSync();
  });

  test('hard-codes no user id', () {
    final uuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );
    for (final sql in [scope, items, link]) {
      expect(uuid.hasMatch(sql), isFalse);
    }
  });

  test('clients cannot touch the new tables', () {
    for (final table in [
      'circle_ai_guard_scope',
      'ai_runtime_flags',
      'ai_circle_vision_usage',
    ]) {
      expect(scope, contains('alter table public.$table enable row level'));
      expect(
        scope,
        contains('revoke all on public.$table from anon, authenticated;'),
      );
    }
    expect(
      items,
      contains('alter table public.guard_item_reviews enable row level'),
    );
    expect(
      items,
      contains(
        'revoke all on public.guard_item_reviews from anon, authenticated;',
      ),
    );
  });

  test('pictures are only held when the server can read them', () {
    expect(scope, contains("public.ai_runtime_flag('vision')"));
    expect(scope, contains('check_images boolean not null default false'));
    // A picture is checked only as the guard decides: the same rule as text.
    expect(scope, contains('public.ai_guard_applies_to(channel_circle_id'));
    expect(scope, contains("'view_once'"));
  });

  test('the new trigger sorts after the guard and the raid trigger', () {
    // BEFORE INSERT triggers run in name order; messages_review_guard resets
    // review_state first.
    final names = [
      'messages_review_guard',
      'messages_review_raid',
      'messages_review_scope',
    ]..sort();
    expect(names.first, 'messages_review_guard');
    expect(names.last, 'messages_review_scope');
    expect(scope, contains('create trigger messages_review_scope'));
  });

  test('no earlier function of the guard is redefined', () {
    for (final name in [
      'messages_review_guard',
      'messages_review_open',
      'finish_message_review',
      'ai_guard_claim',
      'run_ai_guard_sweep',
      'run_later_dispatch',
      'decide_message_review',
      'list_message_reviews',
    ]) {
      expect(scope, isNot(contains('function public.$name(')), reason: name);
      expect(items, isNot(contains('function public.$name(')), reason: name);
    }
  });

  test('the service functions are for the service role only', () {
    for (final function in [
      'ai_set_runtime_flag(text, boolean)',
      'ai_consume_circle_vision_request(uuid, integer)',
      'ai_guard_message_info(uuid)',
      'ai_guard_applies_to(uuid, uuid)',
    ]) {
      expect(
        scope,
        contains(
          'revoke execute on function public.$function from public, anon, authenticated;',
        ),
        reason: function,
      );
    }
    for (final function in [
      'ai_guard_item_claim(uuid)',
      'finish_guard_item_review(uuid, text, text, text, text)',
      'run_ai_guard_item_sweep()',
    ]) {
      expect(
        items,
        contains(
          'revoke execute on function public.$function from public, anon, authenticated;',
        ),
        reason: function,
      );
      expect(
        items,
        contains('grant execute on function public.$function to service_role;'),
        reason: function,
      );
    }
  });

  test('the item sweep has its own cron job', () {
    expect(items, contains("'wecord-ai-guard-item-sweep'"));
    expect(items, isNot(contains('cron.unschedule')));
    expect(items, isNot(contains('function public.run_later_dispatch(')));
  });

  test('every decision about an item is audited', () {
    expect(items, contains("'guard_item_flag'"));
    expect(items, contains("'guard_item_dismiss'"));
  });

  test('the link preview keeps where a link ended', () {
    expect(link, contains('add column if not exists final_url text'));
  });

  behaviourTest(
    'polls, pictures, items, the queue, the sweep and the scope',
    'test/supabase/guard2_behaviour.sql',
  );
}

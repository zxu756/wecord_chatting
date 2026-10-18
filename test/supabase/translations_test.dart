import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the translation cache and the translation choices
/// (roadmap A5), plus the behaviour script.
void main() {
  late String cache;
  late String prefs;

  setUpAll(() {
    cache = File(
      'supabase/migrations/202610220400_message_translations.sql',
    ).readAsStringSync();
    prefs = File(
      'supabase/migrations/202610220410_translation_prefs.sql',
    ).readAsStringSync();
  });

  test('the cache is read-only for clients and follows the message', () {
    expect(cache, contains('alter table public.message_translations enable'));
    expect(
      cache,
      contains(
        'revoke all on public.message_translations from anon, authenticated;',
      ),
    );
    expect(
      cache,
      contains('grant select on public.message_translations to authenticated;'),
    );
    expect(cache, contains('primary key (message_id, target_lang)'));
    expect(cache, contains('references public.messages(id) on delete cascade'));
    // Read through the messages table's own policy as the caller.
    expect(
      cache,
      contains(
        'select 1 from public.messages m where m.id = message_translations.',
      ),
    );
    expect(cache, isNot(contains('message_visible_to_current_user(')));
  });

  test('every change that takes a message away clears it, by trigger', () {
    expect(cache, contains('create trigger messages_clear_translations'));
    expect(
      cache,
      contains('after update of body, recalled_at, review_state, expires_at'),
    );
    for (final condition in [
      'new.recalled_at is not null',
      'new.body is distinct from old.body',
      'new.review_state is not null',
      'new.expires_at <= now()',
    ]) {
      expect(cache, contains(condition), reason: condition);
    }
    // The old functions are left alone.
    for (final function in [
      'edit_message',
      'recall_message',
      'purge_expired_messages',
      'finish_message_review',
    ]) {
      expect(
        cache,
        isNot(contains('create or replace function public.$function(')),
        reason: function,
      );
    }
  });

  test('only the service role stores translations, and only fresh text', () {
    expect(
      cache,
      contains(
        'revoke execute on function public.store_message_translations(jsonb) from public, anon, authenticated;',
      ),
    );
    expect(
      cache,
      contains(
        'grant execute on function public.store_message_translations(jsonb) to service_role;',
      ),
    );
    expect(cache, contains('m.body is not distinct from w.source_text'));
    expect(cache, contains('for share of m'));
  });

  test('the choices are owner-only', () {
    for (final table in [
      'conversation_translation_prefs',
      'user_ai_settings',
    ]) {
      expect(prefs, contains('alter table public.$table enable row'));
      expect(
        prefs,
        contains('revoke all on public.$table from anon, authenticated;'),
      );
    }
    expect(prefs, isNot(contains('to anon')));
    expect(prefs, contains('using (user_id = auth.uid())'));
    expect(prefs, contains('public.current_user_readable_conversation_ids()'));
    // A user-level table of its own, not columns on the push function's.
    expect(
      prefs,
      isNot(contains('alter table public.user_notification_settings')),
    );
  });

  behaviourTest(
    'cache visibility, no client writes, every cleanup path, and the choices',
    'test/supabase/translations_behaviour.sql',
  );
}

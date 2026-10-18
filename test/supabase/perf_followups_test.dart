import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// The database side of the performance follow-ups (migrations 202610190060
/// to 202610190062): schema checks of what each function builds on and who
/// may call it, plus the behaviour script, which rebuilds the schema from
/// every migration, plays signed-in people and compares every new function
/// with the ones it stands in for.
void main() {
  late String chains;
  late String capabilities;
  late String summary;

  setUpAll(() {
    chains = File(
      'supabase/migrations/202610190060_get_chains.sql',
    ).readAsStringSync();
    capabilities = File(
      'supabase/migrations/202610190061_conversation_capabilities.sql',
    ).readAsStringSync();
    summary = File(
      'supabase/migrations/202610190062_conversation_summary.sql',
    ).readAsStringSync();
  });

  group('get_chains', () {
    test(
      'asks get_chain, so the rules of reading a chain stay in one place',
      () {
        expect(chains, contains('public.get_chain(chain_id)'));
        expect(chains, contains("sqlstate 'P0002'"));
      },
    );

    test('is limited to 50 chains and to signed-in people', () {
      expect(chains, contains('> 50'));
      expect(chains, contains('auth.uid() is null'));
      expect(
        chains,
        contains(
          'revoke execute on function public.get_chains(uuid[]) from public, anon',
        ),
      );
      expect(
        chains,
        contains(
          'grant execute on function public.get_chains(uuid[]) to authenticated',
        ),
      );
    });
  });

  group('get_conversation_capabilities', () {
    test('calls the existing permission helpers, not copies of them', () {
      for (final helper in [
        'can_current_user_pin_messages',
        'can_current_user_moderate_polls',
        'can_current_user_moderate_messages',
        'can_current_user_manage_thread',
      ]) {
        expect(capabilities, contains('public.$helper('), reason: helper);
      }
    });

    test('is closed to anonymous callers', () {
      expect(capabilities, contains('auth.uid() is null'));
      expect(
        capabilities,
        contains(
          'revoke execute on function public.get_conversation_capabilities(uuid) from public, anon',
        ),
      );
    });
  });

  group('get_conversation_summary', () {
    test('is the list query for one conversation', () {
      // Every step of the query is narrowed to the conversation.
      expect(
        RegExp('target_conversation_id').allMatches(summary).length,
        greaterThanOrEqualTo(6),
      );
      expect(summary, contains('where c.id = target_conversation_id'));
      // The list's rules that hide things are all still there.
      expect(summary, contains('message_visible_to_current_user'));
      expect(
        summary,
        contains('expires_at is null or last_message.expires_at > now()'),
      );
      expect(summary, contains('hidden_at is null'));
      expect(summary, contains("'view_channel'"));
    });

    test('is closed to anonymous callers and takes no other identity', () {
      expect(summary, contains('auth.uid()'));
      expect(
        summary,
        contains(
          'revoke execute on function public.get_conversation_summary(uuid) from public, anon',
        ),
      );
    });
  });

  behaviourTest(
    'get_chains, capabilities and the single summary agree with the functions '
        'they stand in for, for members, admins and outsiders',
    'test/supabase/perf_followups_behaviour.sql',
  );
}

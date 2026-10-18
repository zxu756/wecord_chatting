import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// The security audit of the database changes of 2026-10-17 and 2026-10-18
/// (fixes in migrations 202610190010 to 202610190013): schema checks of the
/// fixes, plus the attack script, which signs in as people who must not see
/// or do something (outsiders, a person who left a group, a blocked person,
/// members reading messages that are held or expired, anonymous callers) and
/// asserts that every attack fails. Run with `-v apply_fixes=0` the script
/// lists the attacks the fixes close.
void main() {
  late String paths;
  late String hidden;
  late String chains;
  late String deleted;

  setUpAll(() {
    paths = File(
      'supabase/migrations/202610190010_security_attachment_paths.sql',
    ).readAsStringSync();
    hidden = File(
      'supabase/migrations/202610190011_security_hidden_messages.sql',
    ).readAsStringSync();
    chains = File(
      'supabase/migrations/202610190012_security_chains.sql',
    ).readAsStringSync();
    deleted = File(
      'supabase/migrations/202610190013_security_deleted_content.sql',
    ).readAsStringSync();
  });

  group('attachment paths', () {
    test('a file path must lie under a chat the sender is in', () {
      expect(paths, contains('before insert on public.messages'));
      expect(
        paths,
        contains('is_current_user_conversation_member(folder::uuid)'),
      );
      expect(paths, contains("current_user not in ('authenticated', 'anon')"));
    });

    test('view-once media needs a file of its own', () {
      expect(paths, contains('chat_file_in_use'));
      expect(paths, contains('retry_client_id'));
    });

    test('the trigger is not security definer (it reads current_user)', () {
      final trigger = paths.substring(
        paths.indexOf(
          'create or replace function public.messages_check_attachment_path()',
        ),
      );
      expect(trigger, isNot(contains('security definer')));
    });
  });

  group('hidden messages', () {
    test('every function that reads a message by id skips expired ones', () {
      for (final fn in [
        'forward_message',
        'create_task_from_message',
        'save_message',
        'set_message_reminder',
        'toggle_message_reaction',
        'claim_local_reminders',
        'list_conversation_summaries',
        'search_messages',
        'search_message_context',
        'can_see_live_location_share',
      ]) {
        expect(
          hidden,
          contains('CREATE OR REPLACE FUNCTION public.$fn('),
          reason: fn,
        );
      }
      expect(
        RegExp('expires_at is null or').allMatches(hidden).length,
        greaterThanOrEqualTo(12),
      );
    });

    test('held messages are not copied into tasks', () {
      expect(hidden, contains('message_visible_to_current_user(review_state'));
    });
  });

  group('chains', () {
    test('a chain follows its card', () {
      expect(chains, contains('chain_card_visible(message_id)'));
      expect(chains, contains('create policy chains_select'));
      expect(chains, contains('create policy chain_entries_select'));
      expect(
        RegExp(
          'chain_card_visible\\(c.message_id\\)',
        ).allMatches(chains).length,
        greaterThanOrEqualTo(7),
      );
    });

    test('the text a new member adds is held like the note of a line', () {
      expect(
        chains,
        contains('chain_note_needs_review(target_conversation_id'),
      );
      expect(chains, contains("'text_held'"));
    });
  });

  group('deleted content', () {
    test('notes, blocks, tasks and lists are scrubbed when deleted', () {
      for (final trigger in [
        'notes_scrub_deleted',
        'note_blocks_scrub_deleted',
        'task_items_scrub_deleted',
        'task_lists_scrub_deleted',
      ]) {
        expect(deleted, contains(trigger));
      }
      expect(deleted, contains('delete from public.note_versions'));
    });

    test('picture paths survive for delete_note', () {
      expect(deleted, isNot(contains("props = '{}'")));
    });
  });

  behaviourTest(
    'attacks: outsiders, ex-members, blocked, held and expired, storage, '
        'realtime, grants, rate limits, overrides',
    'test/supabase/security_audit_behaviour.sql',
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for merged forwards and contact cards, plus the behaviour
/// script.
void main() {
  late String forward;
  late String cards;

  setUpAll(() {
    forward = File(
      'supabase/migrations/202610180070_merged_forward.sql',
    ).readAsStringSync();
    cards = File(
      'supabase/migrations/202610180071_contact_cards.sql',
    ).readAsStringSync();
  });

  test('refuses what forward_message refuses and what a reader cannot see', () {
    expect(
      forward,
      contains('create or replace function public.forward_messages_merged'),
    );
    expect(forward, contains("m.type in ('system', 'poll', 'sticker')"));
    expect(forward, contains('m.review_state is not null'));
    expect(forward, contains('m.expires_at <= now()'));
    expect(forward, contains("m.attachment->>'view_once'"));
    expect(forward, contains('m.recalled_at is not null'));
    expect(forward, contains('current_user_readable_conversation_ids'));
    expect(forward, contains('is_current_user_blocked_in_conversation'));
    expect(forward, contains('between 1 and 100'));
  });

  test('sends only to direct chats and groups, through AutoMod', () {
    expect(forward, contains("target_type not in ('direct', 'group')"));
    expect(forward, contains("set_config('wecord.automod_soft', 'on', true)"));
  });

  test('snapshots the content and re-references files with access rules', () {
    expect(
      forward,
      contains('create table if not exists public.message_bundles'),
    );
    expect(
      forward,
      contains('create table if not exists public.message_bundle_files'),
    );
    for (final policy in [
      'chat_images_select_member',
      'voice_messages_select_member',
      'chat_files_select_member',
    ]) {
      expect(forward, contains('create policy $policy'));
    }
    expect(
      forward,
      contains('public.can_current_user_read_bundled_object(bucket_id, name)'),
    );
    // Clients cannot write bundles.
    expect(
      forward,
      contains('revoke all on public.message_bundles from anon, authenticated'),
    );
    expect(
      forward,
      contains('grant select on public.message_bundles to authenticated'),
    );
  });

  test('a file a chat history shows is not deleted from under it', () {
    expect(
      forward,
      contains(
        'create or replace function public.can_current_user_delete_recalled_media',
      ),
    );
    expect(
      forward,
      contains('create or replace function public.claim_expired_media'),
    );
    expect(forward, contains('create trigger message_bundle_files_release'));
    expect(forward, contains('create trigger messages_release_bundle'));
  });

  test('contact cards follow profile visibility, blocks and invite rights', () {
    expect(cards, contains('can_view_profile_details(card_target_id)'));
    expect(
      cards,
      contains('are_users_blocked(current_user_id, card_target_id)'),
    );
    expect(cards, contains("'create_invites'"));
    expect(cards, contains('create_circle_invite(card_target_id, 168, null)'));
    expect(cards, contains('is_current_user_blocked_in_conversation'));
  });

  behaviourTest(
    'merging, snapshots, file access, refusals and cards work against a database',
    'test/supabase/merged_forward_behaviour.sql',
  );
}

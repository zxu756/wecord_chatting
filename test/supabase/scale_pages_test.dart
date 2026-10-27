import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the L6 scale migrations (202610281200 hot queries,
/// 202610281210 member pages, 202610281220 push batches), plus the behaviour
/// script: pages put together are the whole list, and the same people hear a
/// push as before.
void main() {
  late String hot;
  late String members;
  late String push;

  setUpAll(() {
    hot = File(
      'supabase/migrations/202610281200_l6_hot_queries.sql',
    ).readAsStringSync();
    members = File(
      'supabase/migrations/202610281210_l6_member_pages.sql',
    ).readAsStringSync();
    push = File(
      'supabase/migrations/202610281220_l6_push_pages.sql',
    ).readAsStringSync();
  });

  test('the migrations patch the live functions instead of copying them', () {
    // A copy of an older definition would drop what other packages added to
    // the function since; a patch fails loudly when its text is not found.
    for (final sql in [hot, members, push]) {
      expect(sql, contains('pg_get_functiondef'));
      expect(sql, contains('raise exception'));
    }
    for (final name in [
      'list_conversation_summaries',
      'get_conversation_summary',
      'list_circle_summaries',
      'search_messages',
      'get_circle_detail',
      'claim_push_delivery',
    ]) {
      for (final sql in [hot, members, push]) {
        expect(
          RegExp('create or replace function public\\.$name\\(').hasMatch(sql),
          isFalse,
          reason: '$name is patched, not redefined',
        );
      }
    }
    expect(hot, isNot(contains('.bio')));
    expect(members, contains('visible_profile_bio(p.id, p.bio)'));
    expect(members, isNot(contains("'bio', p.bio")));
  });

  test('the new functions are for signed-in people, not anon', () {
    for (final signature in [
      'public.get_circle_detail(uuid, integer)',
      'public.list_circle_members_page(uuid, integer, integer, text, uuid, text)',
      'public.list_conversation_members_page(uuid, integer, timestamptz, uuid, text)',
    ]) {
      expect(members, contains('revoke execute on function $signature'));
      expect(
        RegExp(
          'grant execute on function ${RegExp.escape(signature)}\\s+to authenticated',
        ).hasMatch(members),
        isTrue,
        reason: signature,
      );
    }
    expect('security definer'.allMatches(members).length, 2);
    expect('set search_path = public'.allMatches(members).length, 2);
  });

  test('the push claim stays for the service role only', () {
    const signature = 'public.claim_push_delivery(uuid, uuid, uuid, integer)';
    expect(push, contains('revoke execute on function $signature'));
    expect(push, contains('from public, anon, authenticated'));
    expect(
      push,
      contains('grant execute on function $signature\n  to service_role'),
    );
    expect(push, isNot(contains('to authenticated')));
    // The 2-argument function is replaced, not kept beside the new one.
    expect(
      push,
      contains('drop function public.claim_push_delivery(uuid, uuid)'),
    );
  });

  test('hot-path indexes exist', () {
    expect(members, contains('conversation_members_page_idx'));
  });

  behaviourTest(
    'scale pages: member pages, member_limit and push batches',
    'test/supabase/scale_pages_behaviour.sql',
  );
}

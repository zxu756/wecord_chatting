import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File('supabase/migrations/202605180001_private_chat.sql');

  String functionBody(String sql, String functionName) {
    final match = RegExp(
      'create or replace function public\\.$functionName[\\s\\S]*?\\n\\\$\\\$;',
    ).firstMatch(sql);
    expect(match, isNotNull, reason: 'Missing function $functionName');
    return match!.group(0)!;
  }

  Iterable<String> policyBodiesFor(String sql, String tableName) {
    return RegExp('create policy [\\s\\S]*?;', caseSensitive: false)
        .allMatches(sql)
        .map((match) => match.group(0)!)
        .where((policy) => policy.contains('on public.$tableName'));
  }

  test('private chat migration declares required tables', () {
    final sql = migration.readAsStringSync();

    for (final table in [
      'profiles',
      'friend_requests',
      'friendships',
      'conversations',
      'conversation_members',
      'messages',
      'blocks',
    ]) {
      expect(sql, contains('create table public.$table'));
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
    }
  });

  test('private chat migration declares direct conversation RPCs', () {
    final sql = migration.readAsStringSync();

    expect(
      sql,
      contains('create or replace function public.accept_friend_request'),
    );
    expect(
      sql,
      contains('create or replace function public.reject_friend_request'),
    );
    expect(
      sql,
      contains('create or replace function public.cancel_friend_request'),
    );
    expect(
      sql,
      contains(
        'create or replace function public.get_or_create_direct_conversation',
      ),
    );
    expect(
      sql,
      contains(
        'create or replace function public.touch_conversation_from_message',
      ),
    );
    expect(sql, contains('create trigger messages_touch_conversation'));
    expect(
      sql,
      contains('execute function public.touch_conversation_from_message()'),
    );
  });

  test('friend request status changes are protected by narrow RPCs', () {
    final sql = migration.readAsStringSync();
    final acceptBody = functionBody(sql, 'accept_friend_request');
    final rejectBody = functionBody(sql, 'reject_friend_request');
    final cancelBody = functionBody(sql, 'cancel_friend_request');

    expect(
      sql,
      isNot(
        matches(
          RegExp(
            r'create policy \w+\s+on public\.friend_requests\s+for update',
          ),
        ),
      ),
    );
    expect(acceptBody, contains('receiver_id = auth.uid()'));
    expect(acceptBody, contains("status = 'pending'"));
    expect(acceptBody, contains("set status = 'accepted'"));
    expect(rejectBody, contains('receiver_id = auth.uid()'));
    expect(rejectBody, contains("status = 'pending'"));
    expect(rejectBody, contains("set status = 'rejected'"));
    expect(cancelBody, contains('requester_id = auth.uid()'));
    expect(cancelBody, contains("status = 'pending'"));
    expect(cancelBody, contains("set status = 'cancelled'"));
  });

  test('friendship rows cannot be directly updated by broad policies', () {
    final sql = migration.readAsStringSync();
    final friendshipPolicies = policyBodiesFor(sql, 'friendships');

    expect(sql, isNot(contains('friendships_update_participants')));
    expect(
      friendshipPolicies,
      everyElement(
        isNot(matches(RegExp(r'\bfor\s+update\b', caseSensitive: false))),
      ),
    );
  });

  test('conversation rows cannot be directly updated by broad policies', () {
    final sql = migration.readAsStringSync();
    final conversationPolicies = policyBodiesFor(sql, 'conversations');

    expect(sql, isNot(contains('conversations_update_members')));
    expect(sql, isNot(contains('conversations_update_member')));
    expect(
      conversationPolicies,
      everyElement(
        isNot(matches(RegExp(r'\bfor\s+update\b', caseSensitive: false))),
      ),
    );
  });

  test('conversation read state changes cannot update member roles', () {
    final sql = migration.readAsStringSync();
    final markReadBody = functionBody(sql, 'mark_conversation_read');

    expect(sql, isNot(contains('conversation_members_update_self')));
    expect(
      markReadBody,
      contains('public.is_current_user_conversation_member'),
    );
    expect(markReadBody, contains('target_conversation_id'));
    expect(markReadBody, contains('auth.uid()'));
    expect(markReadBody, contains('update public.conversation_members'));
    expect(
      markReadBody,
      contains('set last_read_message_id = target_message_id'),
    );
    expect(markReadBody, isNot(contains('set role')));
  });

  test('private chat migration protects message access by membership', () {
    final sql = migration.readAsStringSync();
    final insertPolicy = RegExp(
      r'create policy messages_insert_member[\s\S]*?;',
    ).firstMatch(sql);

    expect(sql, contains('messages_select_member'));
    expect(sql, contains('messages_insert_member'));
    expect(sql, contains('conversation_members'));
    expect(sql, contains('auth.uid()'));
    expect(insertPolicy, isNotNull);
    expect(insertPolicy!.group(0), contains('sender_id = auth.uid()'));
    expect(
      insertPolicy.group(0),
      contains('public.is_current_user_conversation_member'),
    );
  });

  test('membership helper cannot probe arbitrary users', () {
    final sql = migration.readAsStringSync();
    final helperBody = functionBody(sql, 'is_current_user_conversation_member');

    expect(sql, isNot(contains('check_user_id')));
    expect(
      sql,
      isNot(
        matches(
          RegExp(
            r'create or replace function public\.is_conversation_member\s*\(\s*check_conversation_id\s+uuid\s*,\s*check_user_id\s+uuid\s*\)',
            caseSensitive: false,
          ),
        ),
      ),
    );
    expect(
      sql,
      matches(
        RegExp(
          r'create or replace function public\.is_current_user_conversation_member\s*\(\s*check_conversation_id\s+uuid\s*\)',
          caseSensitive: false,
        ),
      ),
    );
    expect(helperBody, contains('auth.uid()'));
  });
}

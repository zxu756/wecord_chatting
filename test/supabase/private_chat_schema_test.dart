import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final migration = File('supabase/migrations/202605180001_private_chat.sql');

  String allMigrationSql() {
    final files =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((file) => file.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    return files.map((file) => file.readAsStringSync()).join('\n');
  }

  String effectiveMigrationSql() {
    var sql = allMigrationSql();
    final droppedPolicies = RegExp(
      r'drop policy if exists (\w+) on public\.(\w+);',
      caseSensitive: false,
    ).allMatches(sql);

    for (final policy in droppedPolicies) {
      final policyName = policy.group(1)!;
      final tableName = policy.group(2)!;
      sql = sql.replaceAll(
        RegExp(
          'create policy $policyName[\\s\\S]*?on public\\.$tableName[\\s\\S]*?;',
          caseSensitive: false,
        ),
        '',
      );
    }

    return sql;
  }

  String functionBody(String sql, String functionName) {
    final matches = RegExp(
      'create or replace function public\\.$functionName[\\s\\S]*?\\n\\\$\\\$;',
    ).allMatches(sql);
    expect(matches, isNotEmpty, reason: 'Missing function $functionName');
    return matches.last.group(0)!;
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
      contains('create or replace function public.list_conversation_summaries'),
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

  test('conversation summaries are scoped and compute unread counts', () {
    final sql = effectiveMigrationSql();
    final summariesBody = functionBody(sql, 'list_conversation_summaries');

    expect(summariesBody, contains('security definer'));
    expect(summariesBody, contains('auth.uid()'));
    expect(summariesBody, contains('conversation_members'));
    expect(summariesBody, contains('last_read_message_id'));
    expect(summariesBody, contains('unread_count'));
    expect(summariesBody, contains('last_message_body'));
    expect(summariesBody, contains('last_message.recalled_at'));
    expect(summariesBody, contains("'Message deleted'"));
  });

  test(
    'conversation summaries include latest message sender for notifications',
    () {
      final sql = allMigrationSql();
      final summariesBody = functionBody(sql, 'list_conversation_summaries');

      expect(summariesBody, contains('last_message_sender_id'));
      expect(
        summariesBody,
        contains('last_message.sender_id as last_message_sender_id'),
      );
    },
  );

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

  test('message recall is scoped to the sender through a narrow RPC', () {
    final sql = allMigrationSql();
    final recallBody = functionBody(sql, 'recall_message');

    expect(sql, contains('create or replace function public.recall_message'));
    expect(recallBody, contains('target_message_id uuid'));
    expect(recallBody, contains('sender_id = auth.uid()'));
    expect(recallBody, contains('recalled_at = now()'));
    expect(recallBody, contains('public.is_current_user_conversation_member'));
    expect(
      sql,
      isNot(
        matches(
          RegExp(
            r'create policy messages_\w+\s+on public\.messages\s+for update',
            caseSensitive: false,
          ),
        ),
      ),
    );
  });

  test('chat tables are included in the realtime publication', () {
    final sql = allMigrationSql();

    for (final table in [
      'public.conversations',
      'public.conversation_members',
      'public.messages',
    ]) {
      expect(
        sql,
        contains('alter publication supabase_realtime add table $table'),
      );
    }
  });

  test('image message storage bucket is private and scoped by membership', () {
    final sql = allMigrationSql();

    expect(sql, contains("insert into storage.buckets"));
    expect(sql, contains("'chat-images'"));
    expect(sql, contains('public = false'));
    expect(sql, contains('chat_images_select_member'));
    expect(sql, contains('chat_images_insert_member'));
    expect(sql, contains("bucket_id = 'chat-images'"));
    expect(sql, contains('storage.foldername(name)'));
    expect(sql, contains('public.is_current_user_conversation_member'));
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

  test('social chat v2 RPCs are narrow and role scoped', () {
    final sql = allMigrationSql();

    expect(
      sql,
      contains('create or replace function public.create_group_conversation'),
    );
    expect(
      sql,
      contains('create or replace function public.rename_group_conversation'),
    );
    expect(
      sql,
      contains('create or replace function public.add_group_members'),
    );
    expect(
      sql,
      contains('create or replace function public.update_current_user_profile'),
    );
    expect(sql, contains('create or replace function public.edit_message'));

    final createGroupBody = functionBody(sql, 'create_group_conversation');
    expect(createGroupBody, contains('auth.uid()'));
    expect(createGroupBody, contains('friendships'));
    expect(createGroupBody, contains("role, 'owner'"));
    expect(createGroupBody, contains("role, 'member'"));

    final renameBody = functionBody(sql, 'rename_group_conversation');
    expect(renameBody, contains("role in ('owner', 'admin')"));

    final addMembersBody = functionBody(sql, 'add_group_members');
    expect(addMembersBody, contains("role in ('owner', 'admin')"));

    final editBody = functionBody(sql, 'edit_message');
    expect(editBody, contains('sender_id = auth.uid()'));
    expect(editBody, contains("type = 'text'"));
    expect(editBody, contains('recalled_at is null'));

    final profileBody = functionBody(sql, 'update_current_user_profile');
    expect(profileBody, contains('id = auth.uid()'));
  });

  test('social chat v2 avoids broad sensitive update policies', () {
    final sql = effectiveMigrationSql();

    expect(
      sql,
      isNot(
        contains(
          RegExp(r'create policy \w+\s+on public\.messages\s+for update'),
        ),
      ),
    );
    expect(
      sql,
      isNot(
        contains(
          RegExp(r'create policy \w+\s+on public\.profiles\s+for update'),
        ),
      ),
    );
  });

  test('profile avatar storage is owner scoped', () {
    final sql = allMigrationSql();

    expect(sql, contains("insert into storage.buckets (id, name, public)"));
    expect(sql, contains("'profile-avatars'"));
    expect(
      sql,
      contains(
        'drop policy if exists profile_avatars_select_authenticated on storage.objects',
      ),
    );
    expect(
      sql,
      contains(
        'drop policy if exists profile_avatars_insert_owner on storage.objects',
      ),
    );
    expect(sql, contains("bucket_id = 'profile-avatars'"));
    expect(sql, contains("(storage.foldername(name))[1] = auth.uid()::text"));
  });
}

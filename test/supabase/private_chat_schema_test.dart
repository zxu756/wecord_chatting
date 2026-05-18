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
      'create or replace function public\\.$functionName\\s*\\([\\s\\S]*?\\n\\\$\\\$;',
    ).allMatches(sql);
    expect(matches, isNotEmpty, reason: 'Missing function $functionName');
    return matches.last.group(0)!;
  }

  String policyBody(String sql, String policyName) {
    final matches = RegExp(
      'create policy $policyName[\\s\\S]*?;',
      caseSensitive: false,
    ).allMatches(sql);
    expect(matches, isNotEmpty, reason: 'Missing policy $policyName');
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
    expect(summariesBody, contains('last_message_type'));
    expect(summariesBody, contains('pinned_at'));
    expect(summariesBody, contains('muted_until'));
    expect(summariesBody, contains('is_marked_unread'));
    expect(summariesBody, contains('member_count'));
    expect(summariesBody, contains('last_message_mentions'));
    expect(summariesBody, contains("'[Image]'"));
    expect(summariesBody, contains('hidden_at is null'));
    expect(summariesBody, contains('c.last_message_at > cm.hidden_at'));
    expect(summariesBody, contains('last_message.recalled_at'));
    expect(summariesBody, contains("'Message deleted'"));
  });

  test('conversation management uses narrow member-scoped RPCs', () {
    final sql = allMigrationSql();

    for (final functionName in [
      'set_conversation_pinned',
      'set_conversation_muted',
      'mark_conversation_unread',
      'hide_conversation',
    ]) {
      final body = functionBody(sql, functionName);
      expect(body, contains('auth.uid()'));
      expect(body, contains('target_conversation_id'));
      expect(body, contains('update public.conversation_members'));
    }
  });

  test('group management uses narrow role-scoped RPCs and storage', () {
    final sql = allMigrationSql();

    expect(sql, contains('alter table public.conversations'));
    expect(sql, contains('add column if not exists announcement'));
    expect(sql, contains("'group-avatars'"));
    expect(sql, contains('group_avatars_select_member'));
    expect(sql, contains('group_avatars_insert_admin'));

    final updateBody = functionBody(sql, 'update_group_profile');
    expect(updateBody, contains("role in ('owner', 'admin')"));
    expect(updateBody, contains('announcement'));

    final leaveBody = functionBody(sql, 'leave_group_conversation');
    expect(leaveBody, contains("role = 'owner'"));
    expect(leaveBody, contains('delete from public.conversation_members'));

    final removeBody = functionBody(sql, 'remove_group_member');
    expect(removeBody, contains("actor.role = 'owner'"));
    expect(removeBody, contains("actor.role = 'admin'"));
    expect(removeBody, contains('delete from public.conversation_members'));
  });

  test('mentions are stored and sent through a validating RPC', () {
    final sql = allMigrationSql();

    expect(sql, contains('add column if not exists mentions jsonb'));
    expect(sql, contains('message_mentions_is_array'));
    expect(sql, contains('message_mentions_have_valid_shape'));
    expect(sql, contains('create table if not exists public.message_mentions'));
    expect(sql, contains('message_mentions_select_member'));

    final sendBody = functionBody(sql, 'send_text_message');
    expect(sendBody, contains('public.is_current_user_conversation_member'));
    expect(sendBody, contains('message_mentions'));
    expect(sendBody, contains('mentioned users must be conversation members'));
  });

  test('daily chat polish adds narrow alias forward and search contracts', () {
    final sql = allMigrationSql();

    expect(sql, contains('create table if not exists public.contact_aliases'));
    expect(
      sql,
      contains('create or replace function public.set_contact_alias'),
    );
    expect(
      sql,
      contains('create or replace function public.list_friends_with_aliases'),
    );
    expect(sql, contains('create or replace function public.forward_message'));
    expect(sql, contains('create or replace function public.search_messages'));

    final aliasBody = functionBody(sql, 'set_contact_alias');
    expect(aliasBody, contains('auth.uid()'));
    expect(aliasBody, contains('friendships'));
    expect(
      aliasBody.indexOf('from public.friendships'),
      lessThan(aliasBody.indexOf('delete from public.contact_aliases')),
    );

    final forwardBody = functionBody(sql, 'forward_message');
    expect(forwardBody, contains('public.is_current_user_conversation_member'));
    expect(forwardBody, contains('forwarded_from'));
    expect(forwardBody, contains("'sender_name'"));
    expect(forwardBody, contains("'source_attachment_bucket'"));
    expect(forwardBody, contains("'source_attachment_path'"));

    final searchBody = functionBody(sql, 'search_messages');
    expect(searchBody, contains('websearch_to_tsquery'));
    expect(searchBody, contains('public.is_current_user_conversation_member'));
  });

  test('daily chat polish scopes voice storage to conversation members', () {
    final sql = allMigrationSql();

    expect(sql, contains("'voice-messages'"));
    expect(sql, contains('voice_messages_select_member'));
    expect(sql, contains('voice_messages_insert_member'));
  });

  test('identity safety v4 adds narrow profile safety RPCs', () {
    final sql = allMigrationSql();

    expect(
      sql,
      contains('create table if not exists public.user_privacy_settings'),
    );
    expect(sql, contains('create table if not exists public.reports'));
    expect(
      sql,
      contains('create or replace function public.get_profile_summary'),
    );
    expect(sql, contains('create or replace function public.block_user'));
    expect(sql, contains('create or replace function public.unblock_user'));
    expect(sql, contains('create or replace function public.report_user'));

    final blockBody = functionBody(sql, 'block_user');
    expect(blockBody, contains('auth.uid()'));
    expect(blockBody, contains('blocked_id <> auth.uid()'));
    expect(blockBody, contains('delete from public.friend_requests'));

    final reportBody = functionBody(sql, 'report_user');
    expect(reportBody, contains('target_user_id <> auth.uid()'));
    expect(reportBody, contains('insert into public.reports'));
  });

  test('identity safety v4 enforces blocks before social writes', () {
    final sql = allMigrationSql();

    expect(sql, isNot(contains('public.create_or_get_direct_conversation')));

    final friendBody = functionBody(sql, 'send_friend_request');
    expect(friendBody, contains('public.are_users_blocked'));

    final directBody = functionBody(sql, 'get_or_create_direct_conversation');
    expect(directBody, contains('public.are_users_blocked'));

    final profileBody = functionBody(sql, 'get_profile_summary');
    expect(profileBody, contains('relationship_status'));
    expect(profileBody, contains('is_blocked_by_me'));
    expect(profileBody, contains('has_blocked_me'));
  });

  test('identity safety v4 blocks writes into blocked direct conversations', () {
    final sql = allMigrationSql();

    expect(
      sql,
      contains(
        'create or replace function public.is_current_user_blocked_in_conversation',
      ),
    );
    expect(
      sql,
      contains(
        'revoke execute on function public.are_users_blocked(uuid, uuid) from public',
      ),
    );
    expect(
      sql,
      contains(
        'revoke execute on function public.are_users_blocked(uuid, uuid) from authenticated',
      ),
    );

    final sendBody = functionBody(sql, 'send_text_message');
    expect(
      sendBody,
      contains('public.is_current_user_blocked_in_conversation'),
    );

    final forwardBody = functionBody(sql, 'forward_message');
    expect(
      forwardBody,
      contains('public.is_current_user_blocked_in_conversation'),
    );

    final messageInsertPolicy = policyBody(sql, 'messages_insert_member');
    expect(
      messageInsertPolicy,
      contains('not public.is_current_user_blocked_in_conversation'),
    );
  });

  test('identity safety v4 enforces friend request privacy policy', () {
    final sql = allMigrationSql();

    final friendBody = functionBody(sql, 'send_friend_request');
    expect(friendBody, contains('friend_request_policy'));
    expect(friendBody, contains("'none'"));
    expect(friendBody, contains("'friends_of_friends'"));
  });

  test('direct conversation summaries prefer contact aliases for titles', () {
    final sql = allMigrationSql();
    final summariesBody = functionBody(sql, 'list_conversation_summaries');

    expect(summariesBody, contains('public.contact_aliases'));
    expect(summariesBody, contains('ca.owner_id = auth.uid()'));
    expect(summariesBody, contains('ca.friend_id = p.id'));
    expect(
      summariesBody,
      contains('coalesce(ca.alias, p.display_name) as display_name'),
    );
    expect(summariesBody, contains('coalesce(c.title, dp.display_name)'));
  });

  test('community discovery v1 declares circle tables and policies', () {
    final sql = effectiveMigrationSql();
    for (final table in [
      'circles',
      'circle_members',
      'circle_channels',
      'circle_posts',
      'circle_post_likes',
      'circle_post_comments',
    ]) {
      expect(sql, contains('create table if not exists public.$table'));
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
    }
    expect(sql, contains('circle_members_role_check'));
    expect(sql, contains("role in ('owner', 'admin', 'member')"));
    expect(sql, contains('circle_channels_conversation_unique'));
  });

  test('community discovery v1 exposes narrow circle RPCs', () {
    final sql = effectiveMigrationSql();
    for (final functionName in [
      'create_circle',
      'list_circle_summaries',
      'get_circle_detail',
      'create_circle_channel',
      'invite_circle_members',
      'create_circle_post',
      'toggle_circle_post_like',
      'create_circle_post_comment',
      'delete_circle_post',
      'report_circle_post',
    ]) {
      expect(
        sql,
        contains('create or replace function public.$functionName'),
        reason: 'Missing $functionName',
      );
    }
    expect(functionBody(sql, 'create_circle'), contains("values ('channel'"));
    expect(functionBody(sql, 'create_circle'), contains("'general'"));
    expect(functionBody(sql, 'invite_circle_members'), contains('friendships'));
    expect(
      functionBody(sql, 'invite_circle_members'),
      contains('are_users_blocked'),
    );
  });

  test('community discovery v1 extends group announcements and discovery', () {
    final sql = effectiveMigrationSql();
    expect(sql, contains('add column if not exists announcement_updated_at'));
    expect(sql, contains('add column if not exists announcement_updated_by'));
    expect(
      functionBody(sql, 'update_group_profile'),
      contains('announcement_updated_at'),
    );
    expect(functionBody(sql, 'search_discovery'), contains('circle_channels'));
    expect(
      functionBody(sql, 'list_conversation_media'),
      contains("m.type in ('image', 'voice', 'file')"),
    );
  });

  test('community discovery v1 provisions realtime and media storage', () {
    final sql = allMigrationSql();

    for (final table in [
      'public.circles',
      'public.circle_members',
      'public.circle_channels',
      'public.circle_posts',
      'public.circle_post_likes',
      'public.circle_post_comments',
    ]) {
      expect(
        sql,
        contains('alter publication supabase_realtime add table $table'),
      );
    }

    expect(sql, contains("values ('chat-media', 'chat-media', false)"));
    expect(sql, contains('chat_media_select_authenticated'));
    expect(sql, contains('chat_media_insert_authenticated'));
    expect(sql, contains("bucket_id = 'chat-media'"));
    expect(sql, contains('public.is_current_user_circle_member'));
  });

  test('community discovery v1 preserves reports and validates invites', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();
    final createCircleBody = functionBody(sql, 'create_circle');
    final inviteBody = functionBody(sql, 'invite_circle_members');
    final postSelectPolicy = policyBody(rawSql, 'circle_posts_select_member');
    final commentSelectPolicy = policyBody(
      rawSql,
      'circle_post_comments_select_member',
    );

    expect(sql, contains('target_post_id uuid references public.circle_posts(id) on delete set null'));
    expect(createCircleBody, contains('Invalid circle invite members'));
    expect(inviteBody, contains('Invalid circle invite members'));
    expect(inviteBody, contains('already a circle member'));
    expect(postSelectPolicy, contains('deleted_at is null'));
    expect(commentSelectPolicy, contains('circle_post_comments.deleted_at is null'));
  });

  test('community discovery v1 returns rich circle detail payloads', () {
    final sql = effectiveMigrationSql();
    final detailBody = functionBody(sql, 'get_circle_detail');

    expect(detailBody, contains("'profile',"));
    expect(detailBody, contains("'username', p.username"));
    expect(detailBody, contains("'circle_id', cc.circle_id"));
    expect(detailBody, contains("'circle_id', cp.circle_id"));
    expect(detailBody, contains("'author',"));
    expect(detailBody, contains("'comments',"));
    expect(detailBody, contains("'is_own_post'"));
    expect(detailBody, contains("'can_manage_post'"));
    expect(detailBody, contains('cp.deleted_at is null'));
  });

  test('forwarded media stays readable through trusted provenance', () {
    final sql = allMigrationSql();
    final imageReadBody = policyBody(sql, 'chat_images_select_member');
    final voiceReadBody = policyBody(sql, 'voice_messages_select_member');
    final imageInsertBody = policyBody(sql, 'chat_images_insert_member');
    final voiceInsertBody = policyBody(sql, 'voice_messages_insert_member');

    for (final body in [imageReadBody, voiceReadBody]) {
      expect(body, contains('from public.messages m'));
      expect(
        body,
        contains("m.forwarded_from->>'source_attachment_path' = name"),
      );
      expect(
        body,
        contains("m.forwarded_from->>'source_attachment_bucket' = bucket_id"),
      );
      expect(body, isNot(contains("m.attachment->>'path' = name")));
      expect(body, isNot(contains("m.attachment->>'bucket' = bucket_id")));
      expect(
        body,
        contains(
          'public.is_current_user_conversation_member(m.conversation_id)',
        ),
      );
    }

    for (final body in [imageInsertBody, voiceInsertBody]) {
      expect(body, isNot(contains('from public.messages m')));
      expect(body, isNot(contains("m.attachment->>'path' = name")));
    }
  });

  test('forwarded provenance is only writable through forward_message', () {
    final sql = allMigrationSql();
    final insertBody = policyBody(sql, 'messages_insert_member');
    final forwardBody = functionBody(sql, 'forward_message');

    expect(insertBody, contains('forwarded_from is null'));
    expect(forwardBody, contains('security definer'));
    expect(forwardBody, contains('forwarded_from'));
  });

  test('send_text_message disambiguates the reply parameter', () {
    final sql = allMigrationSql();
    final sendBody = functionBody(sql, 'send_text_message');

    expect(sendBody, contains('send_text_message.reply_to_message_id'));
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

  test('conversation summary mentions describe the latest message only', () {
    final sql = allMigrationSql();
    final summariesBody = functionBody(sql, 'list_conversation_summaries');

    expect(summariesBody, contains('last_message_mentions'));
    expect(
      summariesBody,
      contains(
        'coalesce(lmm.mentioned_user_ids, array[]::uuid[]) as mentioned_user_ids',
      ),
    );
    expect(
      summariesBody,
      isNot(
        contains(
          'coalesce(um.mentioned_user_ids, lmm.mentioned_user_ids, array[]::uuid[])',
        ),
      ),
    );
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

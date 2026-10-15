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
    expect(
      functionBody(sql, 'list_conversation_summaries'),
      contains('c.announcement_updated_at'),
    );
    expect(
      functionBody(sql, 'list_conversation_summaries'),
      contains('c.announcement_updated_by'),
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

    expect(
      sql,
      contains(
        'target_post_id uuid references public.circle_posts(id) on delete set null',
      ),
    );
    expect(createCircleBody, contains('Invalid circle invite members'));
    expect(inviteBody, contains('Invalid circle invite members'));
    expect(inviteBody, contains('already a circle member'));
    expect(postSelectPolicy, contains('deleted_at is null'));
    expect(
      commentSelectPolicy,
      contains('circle_post_comments.deleted_at is null'),
    );
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
    expect(
      recallBody,
      contains('is_own := coalesce(target.sender_id = current_user_id, false)'),
    );
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

  test('message reactions table is member scoped and realtime enabled', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();
    final selectPolicy = policyBody(rawSql, 'message_reactions_select_member');

    expect(
      sql,
      contains('create table if not exists public.message_reactions'),
    );
    expect(sql, contains('primary key (message_id, user_id, emoji)'));
    expect(sql, contains('check (char_length(emoji) between 1 and 64)'));
    expect(
      sql,
      contains(
        'alter table public.message_reactions enable row level security',
      ),
    );
    expect(
      sql,
      contains('alter table public.message_reactions replica identity full'),
    );
    expect(selectPolicy, contains('for select'));
    expect(
      selectPolicy,
      contains(
        'conversation_id in (select public.current_user_readable_conversation_ids())',
      ),
    );
    expect(
      policyBodiesFor(rawSql, 'message_reactions').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );
    expect(
      rawSql,
      contains(
        'alter publication supabase_realtime add table public.message_reactions',
      ),
    );
  });

  test('message reactions are toggled and listed through narrow RPCs', () {
    final sql = effectiveMigrationSql();
    final toggleBody = functionBody(sql, 'toggle_message_reaction');
    final reactorsBody = functionBody(sql, 'list_message_reactors');
    final summaryBody = functionBody(sql, 'reactions');

    expect(toggleBody, contains('target_message_id uuid'));
    expect(toggleBody, contains('target_emoji text'));
    expect(toggleBody, contains('security definer'));
    expect(toggleBody, contains('set search_path = public'));
    expect(toggleBody, contains('auth.uid()'));
    expect(toggleBody, contains('recalled_at is null'));
    expect(toggleBody, contains('public.is_current_user_conversation_member'));
    expect(
      toggleBody,
      contains('public.is_current_user_blocked_in_conversation'),
    );
    expect(toggleBody, contains('delete from public.message_reactions'));
    expect(toggleBody, contains('insert into public.message_reactions'));

    expect(reactorsBody, contains('security definer'));
    expect(
      reactorsBody,
      contains('public.is_current_user_conversation_member'),
    );
    expect(reactorsBody, contains('p.display_name'));
    expect(reactorsBody, contains('contact_aliases'));

    expect(summaryBody, contains('message_row public.messages'));
    expect(summaryBody, contains("'reacted_by_me'"));
    expect(summaryBody, contains("'count'"));
    expect(summaryBody, contains('public.is_current_user_conversation_member'));

    for (final signature in [
      'public.reactions(public.messages)',
      'public.toggle_message_reaction(uuid, text)',
      'public.list_message_reactors(uuid, text)',
    ]) {
      expect(
        sql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('pinned messages table is member scoped and realtime enabled', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();
    final selectPolicy = policyBody(rawSql, 'pinned_messages_select_member');

    expect(sql, contains('create table if not exists public.pinned_messages'));
    expect(sql, contains('primary key (conversation_id, message_id)'));
    expect(sql, contains('pinned_by uuid references public.profiles(id)'));
    expect(
      sql,
      contains('alter table public.pinned_messages enable row level security'),
    );
    expect(
      sql,
      contains('alter table public.pinned_messages replica identity full'),
    );
    expect(selectPolicy, contains('for select'));
    expect(
      selectPolicy,
      contains(
        'conversation_id in (select public.current_user_readable_conversation_ids())',
      ),
    );
    expect(
      policyBodiesFor(rawSql, 'pinned_messages').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );
    expect(
      rawSql,
      contains(
        'alter publication supabase_realtime add table public.pinned_messages',
      ),
    );
  });

  test('system messages are allowed but only written by RPCs', () {
    final sql = allMigrationSql();
    final insertPolicy = policyBody(sql, 'messages_insert_member');
    final forwardBody = functionBody(sql, 'forward_message');
    final searchBody = functionBody(sql, 'search_messages');

    expect(sql, contains('drop constraint if exists messages_type_check'));
    expect(
      sql,
      contains("check (type in ('text', 'image', 'file', 'voice', 'system'))"),
    );
    expect(insertPolicy, contains("type <> 'system'"));
    expect(insertPolicy, contains('sender_id = auth.uid()'));
    expect(insertPolicy, contains('forwarded_from is null'));
    expect(
      insertPolicy,
      contains('not public.is_current_user_blocked_in_conversation'),
    );
    expect(forwardBody, contains("type <> 'system'"));
    expect(searchBody, contains("m.type <> 'system'"));
  });

  test('pin RPCs check membership, role and the pin limit', () {
    final sql = effectiveMigrationSql();
    final permissionBody = functionBody(sql, 'can_current_user_pin_messages');
    final pinBody = functionBody(sql, 'pin_message');
    final unpinBody = functionBody(sql, 'unpin_message');
    final listBody = functionBody(sql, 'list_pinned_messages');
    final computedBody = functionBody(sql, 'is_pinned');

    expect(permissionBody, contains('security definer'));
    expect(permissionBody, contains("when 'direct'"));
    expect(permissionBody, contains("cm.role in ('owner', 'admin')"));
    expect(permissionBody, contains('public.circle_channels'));
    expect(
      permissionBody,
      contains('public.current_user_has_channel_permission('),
    );
    expect(permissionBody, contains("'manage_messages'"));

    for (final body in [pinBody, unpinBody, listBody]) {
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
      expect(body, contains('auth.uid()'));
      expect(body, contains('public.is_current_user_conversation_member'));
    }
    for (final body in [pinBody, unpinBody]) {
      expect(body, contains('public.can_current_user_pin_messages'));
    }

    expect(pinBody, contains('recalled_at is null'));
    expect(pinBody, contains('public.is_current_user_blocked_in_conversation'));
    expect(pinBody, contains('active_pin_count >= 50'));
    expect(pinBody, contains("errcode = '54000'"));
    expect(pinBody, contains('for update'));
    expect(pinBody, contains('insert into public.pinned_messages'));
    expect(pinBody, contains("'system'"));
    expect(pinBody, contains("' pinned a message.'"));
    expect(pinBody, contains("jsonb_build_object('kind', 'pin'"));
    expect(unpinBody, contains('delete from public.pinned_messages'));

    expect(listBody, contains("'display_name'"));
    expect(listBody, contains('pinned_by_name'));
    expect(listBody, contains('order by pm.pinned_at desc'));
    expect(computedBody, contains('message_row public.messages'));

    for (final signature in [
      'public.can_current_user_pin_messages(uuid)',
      'public.is_pinned(public.messages)',
      'public.pin_message(uuid)',
      'public.unpin_message(uuid)',
      'public.list_pinned_messages(uuid)',
    ]) {
      expect(
        sql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('circle invites table is manager scoped and RPC written', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();
    final selectPolicy = policyBody(rawSql, 'circle_invites_select_manager');

    expect(sql, contains('create table if not exists public.circle_invites'));
    expect(sql, contains('code text primary key'));
    expect(sql, contains('use_count integer not null default 0'));
    expect(sql, contains('revoked_at timestamptz'));
    expect(sql, contains("check (code ~ '^[a-z2-9]{10}\$')"));
    expect(
      sql,
      contains('alter table public.circle_invites enable row level security'),
    );
    expect(selectPolicy, contains('for select'));
    expect(
      selectPolicy,
      contains(
        "public.current_user_has_circle_permission(circle_id, 'manage_channels')",
      ),
    );
    expect(selectPolicy, contains('created_by = auth.uid()'));
    expect(
      selectPolicy,
      contains(
        "public.current_user_has_circle_permission(circle_id, 'create_invites')",
      ),
    );
    expect(
      policyBodiesFor(rawSql, 'circle_invites').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );
  });

  test('circle invite RPCs check roles, validity and blocking', () {
    final sql = effectiveMigrationSql();
    final codeBody = functionBody(sql, 'generate_circle_invite_code');
    final reasonBody = functionBody(sql, 'circle_invite_invalid_reason');
    final createBody = functionBody(sql, 'create_circle_invite');
    final listBody = functionBody(sql, 'list_circle_invites');
    final revokeBody = functionBody(sql, 'revoke_circle_invite');
    final previewBody = functionBody(sql, 'get_circle_invite_preview');
    final acceptBody = functionBody(sql, 'accept_circle_invite');

    expect(codeBody, contains('extensions.gen_random_bytes(10)'));
    expect(reasonBody, contains("then 'revoked'"));
    expect(reasonBody, contains("then 'expired'"));
    expect(reasonBody, contains("then 'exhausted'"));

    for (final body in [
      createBody,
      listBody,
      revokeBody,
      previewBody,
      acceptBody,
    ]) {
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
      expect(body, contains('auth.uid()'));
    }
    for (final body in [createBody, listBody, revokeBody]) {
      expect(body, contains('public.current_user_has_circle_permission('));
      expect(body, contains("'create_invites'"));
    }
    for (final body in [listBody, revokeBody]) {
      expect(body, contains("'manage_channels'"));
    }

    expect(createBody, contains('make_interval(hours => expires_in_hours)'));
    expect(createBody, contains('when unique_violation'));
    expect(
      listBody,
      contains('public.circle_invite_invalid_reason(ci) is null'),
    );
    expect(revokeBody, contains('for update'));
    expect(revokeBody, contains('set revoked_at = now()'));

    expect(previewBody, contains('public.are_users_blocked'));
    expect(previewBody, contains("'invalid_reason', 'not_found'"));
    expect(previewBody, contains("'already_member'"));
    expect(previewBody, contains("'member_count'"));

    expect(acceptBody, contains('for update'));
    expect(acceptBody, contains('public.are_users_blocked'));
    expect(acceptBody, contains('public.circle_invite_invalid_reason'));
    expect(acceptBody, contains('insert into public.circle_members'));
    expect(acceptBody, contains('insert into public.conversation_members'));
    expect(acceptBody, contains('from public.circle_channels cc'));
    expect(acceptBody, contains('on conflict do nothing'));
    expect(acceptBody, contains('set use_count = use_count + 1'));
    expect(
      acceptBody.indexOf('return target_invite.circle_id'),
      lessThan(acceptBody.indexOf('set use_count = use_count + 1')),
      reason: 'existing members return before a use is spent',
    );

    for (final signature in [
      'public.generate_circle_invite_code()',
      'public.circle_invite_invalid_reason(public.circle_invites)',
    ]) {
      expect(
        sql,
        contains('revoke execute on function $signature from authenticated'),
      );
    }
    for (final signature in [
      'public.create_circle_invite(uuid, integer, integer)',
      'public.list_circle_invites(uuid)',
      'public.revoke_circle_invite(text)',
      'public.get_circle_invite_preview(text)',
      'public.accept_circle_invite(text)',
    ]) {
      expect(
        sql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('circle nicknames are validated and permission checked', () {
    final sql = effectiveMigrationSql();
    final helperBody = functionBody(sql, 'circle_channel_nickname');
    final senderBody = functionBody(sql, 'sender_nickname');
    final memberBody = functionBody(sql, 'circle_nickname');
    final setBody = functionBody(sql, 'set_circle_nickname');
    final detailBody = functionBody(sql, 'get_circle_detail');

    expect(
      sql,
      contains(
        'alter table public.circle_members\n  add column if not exists nickname text',
      ),
    );
    expect(sql, contains('constraint circle_members_nickname_length'));
    expect(sql, contains('char_length(nickname) between 1 and 32'));

    expect(helperBody, contains('from public.circle_channels cc'));
    expect(helperBody, contains('viewer.user_id = auth.uid()'));
    expect(senderBody, contains('message_row public.messages'));
    expect(senderBody, contains('public.circle_channel_nickname('));
    expect(memberBody, contains('member_row public.conversation_members'));
    expect(memberBody, contains('public.circle_channel_nickname('));

    for (final body in [helperBody, senderBody, memberBody, setBody]) {
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
    }
    expect(setBody, contains('auth.uid()'));
    expect(setBody, contains("nullif(btrim(coalesce(nickname, '')), '')"));
    expect(setBody, contains('> 32'));
    expect(setBody, contains('public.is_current_user_circle_member'));
    expect(setBody, contains("'manage_nicknames'"));
    expect(
      setBody,
      contains(
        'public.circle_member_rank(target_circle_id, target_user_id)\n'
        '      >= public.circle_member_rank(target_circle_id, current_user_id)',
      ),
    );
    expect(setBody, contains('update public.circle_members'));

    expect(detailBody, contains("'nickname', cm.nickname"));
    expect(detailBody, contains("'is_current_user', cm.user_id = auth.uid()"));

    expect(
      sql,
      contains(
        'revoke execute on function public.circle_channel_nickname(uuid, uuid) from authenticated',
      ),
    );
    for (final signature in [
      'public.sender_nickname(public.messages)',
      'public.circle_nickname(public.conversation_members)',
      'public.set_circle_nickname(uuid, uuid, text)',
      'public.get_circle_detail(uuid)',
    ]) {
      expect(
        sql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('circle notification settings are own-row scoped and RPC backed', () {
    final sql = effectiveMigrationSql();
    final getBody = functionBody(sql, 'get_circle_notification_settings');
    final setBody = functionBody(sql, 'set_circle_notification_settings');
    final summariesBody = functionBody(sql, 'list_conversation_summaries');

    expect(
      sql,
      contains(
        'create table if not exists public.circle_notification_settings',
      ),
    );
    expect(sql, contains("check (level in ('all', 'mentions', 'none'))"));
    expect(
      sql,
      contains('references public.circle_members(circle_id, user_id)'),
    );
    expect(
      sql,
      contains(
        'alter table public.circle_notification_settings enable row level security',
      ),
    );
    final policies = policyBodiesFor(
      allMigrationSql(),
      'circle_notification_settings',
    );
    expect(policies, hasLength(4));
    for (final policy in policies) {
      expect(policy, contains('user_id = auth.uid()'));
    }

    for (final body in [getBody, setBody]) {
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
      expect(body, contains('auth.uid()'));
      expect(body, contains('public.is_current_user_circle_member'));
    }
    expect(getBody, contains("coalesce(stored_level, 'all')"));
    expect(setBody, contains("not in ('all', 'mentions', 'none')"));
    expect(setBody, contains('muted_until > now()'));
    expect(setBody, contains('on conflict (circle_id, user_id) do update'));

    // The summaries keep every earlier column and add the circle settings.
    for (final column in [
      'last_message_sender_id uuid',
      'unread_count bigint',
      'is_muted boolean',
      'member_count bigint',
      'mentioned_user_ids uuid[]',
      'announcement_updated_by uuid',
      'circle_id uuid',
      'circle_notification_level text',
      'circle_muted_until timestamptz',
    ]) {
      expect(summariesBody, contains(column));
    }
    expect(
      summariesBody,
      // Threads use their parent channel's circle.
      contains(
        'on cc.conversation_id = coalesce(ct.parent_conversation_id, c.id)',
      ),
    );
    expect(summariesBody, contains("else coalesce(cns.level, 'all')"));
    expect(summariesBody, contains('cns.user_id = auth.uid()'));

    for (final signature in [
      'public.get_circle_notification_settings(uuid)',
      'public.set_circle_notification_settings(uuid, text, timestamptz)',
      'public.list_conversation_summaries()',
    ]) {
      expect(
        sql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('circle summaries count unread channel messages and mentions', () {
    final sql = allMigrationSql();
    final body = functionBody(sql, 'list_circle_summaries');

    // Earlier columns stay, the counts and mute state are added.
    for (final column in [
      'member_count bigint',
      'channel_count bigint',
      'latest_activity_at timestamptz',
      'current_user_role text',
      'unread_count bigint',
      'mention_count bigint',
      'is_muted boolean',
    ]) {
      expect(body, contains(column));
    }
    expect(body, contains('security definer'));
    expect(body, contains('set search_path = public'));
    expect(body, contains('conv_member.user_id = auth.uid()'));
    expect(body, contains('unread_message.sender_id <> auth.uid()'));
    expect(body, contains('unread_message.created_at > cr.last_read_at'));
    expect(body, contains('cr.manual_unread_at is null'));
    expect(body, contains('mm.user_id = auth.uid()'));
    expect(body, contains("mentioned_message.type <> 'system'"));
    expect(body, contains("cns.level = 'none'"));
    expect(body, contains('cns.muted_until > now()'));
    expect(
      sql,
      contains(
        'grant execute on function public.list_circle_summaries() to authenticated',
      ),
    );
  });
  test('channel categories are member scoped, RPC written and realtime', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();
    final selectPolicy = policyBody(
      rawSql,
      'circle_channel_categories_select_member',
    );
    final createBody = functionBody(sql, 'create_channel_category');
    final renameBody = functionBody(sql, 'rename_channel_category');
    final deleteBody = functionBody(sql, 'delete_channel_category');
    final reorderBody = functionBody(sql, 'reorder_circle_channels');
    final channelBody = functionBody(sql, 'create_circle_channel');
    final detailBody = functionBody(sql, 'get_circle_detail');

    expect(
      sql,
      contains('create table if not exists public.circle_channel_categories'),
    );
    expect(sql, contains('char_length(trim(name)) between 1 and 32'));
    expect(
      sql,
      contains(
        'references public.circle_channel_categories(id) on delete set null',
      ),
    );
    expect(
      sql,
      contains(
        'alter table public.circle_channel_categories enable row level security',
      ),
    );
    expect(
      sql,
      contains(
        'alter table public.circle_channel_categories replica identity full',
      ),
    );
    expect(selectPolicy, contains('for select'));
    expect(
      selectPolicy,
      contains('public.is_current_user_circle_member(circle_id)'),
    );
    expect(
      policyBodiesFor(rawSql, 'circle_channel_categories').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );
    expect(
      rawSql,
      contains(
        'alter publication supabase_realtime add table public.circle_channel_categories',
      ),
    );

    for (final body in [
      createBody,
      renameBody,
      deleteBody,
      reorderBody,
      channelBody,
    ]) {
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
      expect(body, contains('auth.uid()'));
      expect(body, contains('public.current_user_has_circle_permission('));
      expect(body, contains("'manage_channels'"));
      expect(body, isNot(contains('caller_role')));
    }
    expect(createBody, contains('> 32'));
    expect(renameBody, contains('> 32'));
    expect(deleteBody, contains('set category_id = null'));
    expect(reorderBody, contains('Layout must list every category'));
    expect(reorderBody, contains('Layout must list every channel'));
    expect(reorderBody, contains('ids.category_id = any(category_ids)'));
    expect(reorderBody, contains('for no key update'));
    expect(channelBody, contains('target_category_id uuid default null'));
    expect(channelBody, contains('Category does not belong to this circle'));
    expect(
      sql,
      contains(
        'drop function if exists public.create_circle_channel(uuid, text)',
      ),
    );

    // The detail keeps nicknames and adds categories.
    expect(detailBody, contains("'nickname', cm.nickname"));
    expect(detailBody, contains("'category_id', cc.category_id"));
    expect(detailBody, contains("'categories',"));
    expect(detailBody, contains('from public.circle_channel_categories ccc'));

    for (final signature in [
      'public.create_channel_category(uuid, text)',
      'public.rename_channel_category(uuid, text)',
      'public.delete_channel_category(uuid)',
      'public.reorder_circle_channels(uuid, jsonb)',
      'public.create_circle_channel(uuid, text, uuid)',
      'public.get_circle_detail(uuid)',
    ]) {
      expect(
        sql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('link previews are read-only cache rows and embeds are sender-only', () {
    final sql = allMigrationSql();
    final selectPolicy = policyBody(sql, 'link_previews_select_authenticated');
    final suppressBody = functionBody(sql, 'set_message_suppress_embeds');

    expect(sql, contains('create table if not exists public.link_previews'));
    expect(sql, contains('url text primary key'));
    for (final column in [
      'title text',
      'description text',
      'image_url text',
      'site_name text',
      'fetched_at timestamptz not null default now()',
    ]) {
      expect(sql, contains(column));
    }
    expect(
      sql,
      contains("check (status in ('ok', 'error', 'blocked', 'unsupported'))"),
    );
    expect(
      sql,
      contains('alter table public.link_previews enable row level security'),
    );
    expect(selectPolicy, contains('for select'));
    expect(selectPolicy, contains('to authenticated'));
    expect(
      policyBodiesFor(sql, 'link_previews').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );
    expect(
      sql,
      contains(
        'revoke insert, update, delete, truncate on public.link_previews '
        'from authenticated',
      ),
    );

    expect(
      sql,
      contains(
        'add column if not exists suppress_embeds boolean not null default false',
      ),
    );
    expect(suppressBody, contains('security definer'));
    expect(suppressBody, contains('set search_path = public'));
    expect(suppressBody, contains('auth.uid() is null'));
    expect(suppressBody, contains('m.sender_id = auth.uid()'));
    expect(suppressBody, contains("m.type = 'text'"));
    expect(suppressBody, contains('m.recalled_at is null'));
    expect(
      suppressBody,
      contains('public.is_current_user_conversation_member(m.conversation_id)'),
    );
    expect(
      sql,
      contains(
        'grant execute on function '
        'public.set_message_suppress_embeds(uuid, boolean) to authenticated',
      ),
    );
  });

  test('link-preview function requires a user and guards fetches', () {
    final config = File('supabase/config.toml').readAsStringSync();
    final source = File(
      'supabase/functions/link-preview/index.ts',
    ).readAsStringSync();

    expect(
      RegExp(
        r'\[functions\.link-preview\][^\[]*verify_jwt = true',
      ).hasMatch(config),
      isTrue,
    );
    expect(source, contains('auth.getUser('));
    expect(source, contains('SUPABASE_SERVICE_ROLE_KEY'));
    expect(source, contains('redirect: "manual"'));
    expect(source, contains('MAX_REDIRECTS = 3'));
    expect(source, contains('FETCH_TIMEOUT_MS = 5_000'));
    expect(source, contains('MAX_BODY_BYTES = 512 * 1024'));
    expect(source, contains('Deno.resolveDns(host, "A")'));
    expect(source, contains('Deno.resolveDns(host, "AAAA")'));
    expect(source, contains('isBlockedAddress'));
    expect(source, contains('isHtmlContentType'));
  });

  test('circle manager checks reject non-members', () {
    final sql = allMigrationSql();

    for (final (functionName, permission) in [
      ('invite_circle_members', 'create_invites'),
      ('delete_circle_post', 'manage_messages'),
    ]) {
      final body = functionBody(sql, functionName);
      expect(body, contains('not public.current_user_has_circle_permission('));
      expect(body, contains("'$permission'"));
      expect(body, isNot(contains('caller_role')));
    }
  });

  test('custom statuses are validated, RPC set and hidden once expired', () {
    final sql = allMigrationSql();
    final statusBody = functionBody(sql, 'custom_status');
    final setBody = functionBody(sql, 'set_custom_status');

    for (final column in [
      'add column if not exists status_emoji text',
      'add column if not exists status_text text',
      'add column if not exists status_expires_at timestamptz',
    ]) {
      expect(sql, contains(column));
    }
    expect(sql, contains('char_length(status_text) between 1 and 64'));
    expect(sql, contains('char_length(status_emoji) between 1 and 32'));

    expect(statusBody, contains('profile_row public.profiles'));
    expect(statusBody, contains('profile_row.status_expires_at <= now()'));
    expect(statusBody, contains('then null'));

    expect(setBody, contains('security definer'));
    expect(setBody, contains('set search_path = public'));
    expect(setBody, contains('current_user_id is null'));
    expect(setBody, contains('where p.id = current_user_id'));
    expect(setBody, contains('char_length(normalized_text) > 64'));
    expect(setBody, contains('normalized_expires_at <= now()'));
    expect(setBody, contains('normalized_expires_at := null'));

    expect(
      functionBody(sql, 'get_circle_detail'),
      contains("'custom_status', public.custom_status(p)"),
    );
    final profileBody = functionBody(sql, 'get_profile_summary');
    expect(profileBody, contains('custom_status jsonb'));
    expect(profileBody, contains('when bs.has_blocked_me then null'));
    final summariesBody = functionBody(sql, 'list_conversation_summaries');
    expect(summariesBody, contains('direct_custom_status jsonb'));
    expect(summariesBody, contains('public.custom_status(p)'));
    expect(summariesBody, contains('b.blocked_id = auth.uid()'));

    for (final grant in [
      'public.custom_status(public.profiles) to authenticated',
      'public.set_custom_status(text, text, timestamptz) to authenticated',
    ]) {
      expect(sql, contains('grant execute on function $grant'));
    }
  });

  test('threads are member scoped, synced with the parent and RPC backed', () {
    final sql = allMigrationSql();

    expect(
      sql,
      contains("check (type in ('direct', 'group', 'channel', 'thread'))"),
    );
    expect(
      sql,
      contains('create table if not exists public.conversation_threads'),
    );
    for (final column in [
      'parent_conversation_id uuid not null',
      'root_message_id uuid references public.messages(id) on delete set null',
      'conversation_id uuid not null unique',
      'archived_at timestamptz',
      'last_message_at timestamptz',
    ]) {
      expect(sql, contains(column));
    }
    expect(sql, contains('conversation_threads_root_message_idx'));
    expect(sql, contains('where root_message_id is not null'));
    expect(
      sql,
      contains(
        'alter table public.conversation_threads enable row level security',
      ),
    );
    final selectPolicy = policyBody(
      allMigrationSql(),
      'conversation_threads_select_member',
    );
    expect(
      selectPolicy,
      contains(
        'parent_conversation_id in (\n'
        '      select public.current_user_readable_conversation_ids()',
      ),
    );
    expect(
      policyBodiesFor(sql, 'conversation_threads').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );
    expect(sql, contains("tablename = 'conversation_threads'"));
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.conversation_threads',
      ),
    );

    // Parent membership changes reach every thread.
    expect(
      functionBody(sql, 'sync_thread_members_on_join'),
      contains('ct.parent_conversation_id = new.conversation_id'),
    );
    expect(
      functionBody(sql, 'sync_thread_members_on_leave'),
      contains('ct.parent_conversation_id = old.conversation_id'),
    );
    expect(sql, contains('after insert on public.conversation_members'));
    expect(sql, contains('after delete on public.conversation_members'));

    final createBody = functionBody(sql, 'create_thread');
    expect(createBody, contains('security definer'));
    expect(createBody, contains('set search_path = public'));
    expect(createBody, contains('current_user_id is null'));
    expect(createBody, contains('public.is_current_user_conversation_member('));
    expect(createBody, contains("parent_type not in ('channel', 'group')"));
    expect(createBody, contains('for update'));
    expect(
      createBody,
      contains('return public.thread_payload(existing_thread)'),
    );
    expect(createBody, contains("values ('thread', normalized_title)"));

    expect(
      functionBody(sql, 'list_threads'),
      contains('public.is_current_user_conversation_member('),
    );
    final manageBody = functionBody(sql, 'can_current_user_manage_thread');
    expect(manageBody, contains('ct.created_by = auth.uid()'));
    expect(manageBody, contains('public.current_user_has_channel_permission('));
    expect(manageBody, contains("'manage_messages'"));
    expect(manageBody, contains("cm.role in ('owner', 'admin')"));
    expect(
      functionBody(sql, 'set_thread_archived'),
      contains('not public.can_current_user_manage_thread(target_thread_id)'),
    );
    expect(
      functionBody(sql, 'thread_summary'),
      contains(
        'public.is_current_user_conversation_member(ct.conversation_id)',
      ),
    );
    expect(
      functionBody(sql, 'circle_channel_nickname'),
      contains('select ct.parent_conversation_id'),
    );
    expect(
      functionBody(sql, 'can_current_user_pin_messages'),
      contains("when 'thread' then"),
    );
    expect(
      functionBody(sql, 'list_circle_summaries'),
      contains('join public.conversation_threads ct'),
    );
    final summariesBody = functionBody(sql, 'list_conversation_summaries');
    for (final column in [
      'parent_conversation_id uuid',
      'parent_title text',
      'thread_id uuid',
      'thread_archived_at timestamptz',
      'thread_last_activity_at timestamptz',
    ]) {
      expect(summariesBody, contains(column));
    }

    for (final grant in [
      'public.create_thread(uuid, uuid, text) to authenticated',
      'public.list_threads(uuid) to authenticated',
      'public.archive_thread(uuid) to authenticated',
      'public.unarchive_thread(uuid) to authenticated',
      'public.can_current_user_manage_thread(uuid) to authenticated',
      'public.thread_summary(public.messages) to authenticated',
    ]) {
      expect(sql, contains('grant execute on function $grant'));
    }
    expect(
      sql,
      contains(
        'revoke execute on function '
        'public.set_thread_archived(uuid, boolean) from authenticated',
      ),
    );
  });

  test('circle roles are member scoped, RPC written and realtime', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();
    final bitBody = functionBody(sql, 'circle_permission_bit');
    final permissionsBody = functionBody(sql, 'circle_member_permissions');
    final hasBody = functionBody(sql, 'circle_member_has_permission');
    final rankBody = functionBody(sql, 'circle_member_rank');
    final createCircleBody = functionBody(sql, 'create_circle');
    final detailBody = functionBody(sql, 'get_circle_detail');
    final colorBody = functionBody(sql, 'circle_channel_role_color');

    expect(sql, contains('create table if not exists public.circle_roles'));
    expect(
      sql,
      contains('create table if not exists public.circle_member_roles'),
    );
    expect(
      sql,
      contains('references public.circle_members(circle_id, user_id)'),
    );
    expect(sql, contains('references public.circle_roles(id, circle_id)'));
    expect(sql, contains('circle_roles_one_default_idx'));
    expect(sql, contains('deferrable initially immediate'));
    for (final table in ['circle_roles', 'circle_member_roles']) {
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(
        rawSql,
        contains('alter publication supabase_realtime add table public.$table'),
      );
      expect(
        policyBodiesFor(rawSql, table).where(
          (policy) => RegExp(
            r'for (insert|update|delete|all)',
            caseSensitive: false,
          ).hasMatch(policy),
        ),
        isEmpty,
      );
    }

    // Bits mirror lib/shared/models/circle_role.dart.
    for (final (name, bit) in [
      ('view_channel', 1),
      ('send_messages', 2),
      ('manage_messages', 4),
      ('manage_channels', 8),
      ('manage_roles', 16),
      ('kick_members', 32),
      ('create_invites', 64),
      ('manage_nicknames', 128),
      ('mention_everyone', 256),
      ('manage_events', 512),
      ('manage_emojis', 1024),
      ('manage_webhooks', 2048),
      ('view_audit_log', 4096),
      ('connect_voice', 8192),
      ('administrator', 16384),
    ]) {
      expect(bitBody, contains("when '$name' then $bit::bigint"));
    }
    expect(permissionsBody, contains('c.owner_id = cm.user_id'));
    expect(permissionsBody, contains("circle_permission_bit('administrator')"));
    expect(permissionsBody, contains('r.is_default'));
    expect(hasBody, contains('public.circle_member_permissions('));
    expect(rankBody, contains('2147483647'));
    expect(createCircleBody, contains("'@everyone'"));
    expect(
      createCircleBody,
      contains('public.circle_default_role_permissions()'),
    );
    expect(detailBody, contains("'current_user_permissions'"));
    expect(detailBody, contains("'roles'"));
    expect(detailBody, contains("'role_ids'"));
    expect(colorBody, contains('viewer.user_id = auth.uid()'));

    for (final name in [
      'create_circle_role',
      'update_circle_role',
      'delete_circle_role',
      'reorder_circle_roles',
      'set_member_roles',
    ]) {
      final body = functionBody(sql, name);
      expect(body, contains('security definer'));
      expect(body, contains('set search_path = public'));
      expect(body, contains('auth.uid()'));
      expect(body, contains("'manage_roles'"));
    }
    for (final name in [
      'update_circle_role',
      'delete_circle_role',
      'reorder_circle_roles',
      'set_member_roles',
    ]) {
      expect(functionBody(sql, name), contains('public.circle_member_rank('));
    }

    for (final signature in [
      'public.circle_member_permissions(uuid, uuid)',
      'public.circle_member_has_permission(uuid, uuid, text)',
      'public.circle_member_rank(uuid, uuid)',
      'public.sync_circle_admin_roles(uuid)',
      'public.circle_channel_role_color(uuid, uuid)',
    ]) {
      expect(
        sql,
        contains('revoke execute on function $signature from authenticated'),
      );
    }
    for (final signature in [
      'public.current_user_has_circle_permission(uuid, text)',
      'public.sender_role_color(public.messages)',
      'public.create_circle_role(uuid, text, integer, bigint, boolean)',
      'public.update_circle_role(uuid, text, integer, bigint, boolean)',
      'public.delete_circle_role(uuid)',
      'public.reorder_circle_roles(uuid, uuid[])',
      'public.set_member_roles(uuid, uuid, uuid[])',
    ]) {
      expect(
        sql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('circle manager checks use role permissions', () {
    final sql = allMigrationSql();
    for (final (name, permission) in [
      ('create_circle_channel', 'manage_channels'),
      ('create_channel_category', 'manage_channels'),
      ('rename_channel_category', 'manage_channels'),
      ('delete_channel_category', 'manage_channels'),
      ('reorder_circle_channels', 'manage_channels'),
      ('invite_circle_members', 'create_invites'),
      ('create_circle_invite', 'create_invites'),
      ('list_circle_invites', 'create_invites'),
      ('revoke_circle_invite', 'create_invites'),
      ('set_circle_nickname', 'manage_nicknames'),
      ('delete_circle_post', 'manage_messages'),
      ('can_current_user_pin_messages', 'manage_messages'),
      ('can_current_user_manage_thread', 'manage_messages'),
    ]) {
      final body = functionBody(sql, name);
      expect(body, contains("'$permission'"), reason: name);
      expect(body, isNot(contains('current_user_circle_role')), reason: name);
      expect(body, isNot(contains('circle_member.role')), reason: name);
    }
  });

  test('kicking circle members is permission and rank checked', () {
    final sql = allMigrationSql();
    final body = functionBody(sql, 'kick_circle_member');

    expect(body, contains('security definer'));
    expect(body, contains('set search_path = public'));
    expect(body, contains('auth.uid()'));
    expect(body, contains("'kick_members'"));
    expect(body, contains('target_user_id = current_user_id'));
    expect(body, contains('c.owner_id = target_user_id'));
    expect(
      body,
      contains(
        'public.circle_member_rank(target_circle_id, target_user_id)\n'
        '    >= public.circle_member_rank(target_circle_id, current_user_id)',
      ),
    );
    expect(body, contains('using public.conversation_threads ct'));
    expect(body, contains('using public.circle_channels cc'));
    expect(body, contains('delete from public.circle_members cm'));
    expect(
      sql,
      contains(
        'grant execute on function '
        'public.kick_circle_member(uuid, uuid) to authenticated',
      ),
    );
  });

  test('channel overwrites are member scoped, RPC written and realtime', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    expect(
      sql,
      contains('create table if not exists public.circle_channel_overwrites'),
    );
    expect(sql, contains('(role_id is null) <> (user_id is null)'));
    expect(sql, contains('unique (channel_id, role_id)'));
    expect(sql, contains('unique (channel_id, user_id)'));
    expect(sql, contains('references public.circle_channels(id, circle_id)'));
    expect(sql, contains('references public.circle_roles(id, circle_id)'));
    expect(
      sql,
      contains('references public.circle_members(circle_id, user_id)'),
    );
    expect(sql, contains('allow & deny = 0'));
    expect(
      sql,
      contains(
        'alter table public.circle_channel_overwrites enable row level security',
      ),
    );
    expect(
      rawSql,
      contains(
        'alter publication supabase_realtime add table '
        'public.circle_channel_overwrites',
      ),
    );
    expect(
      policyBodiesFor(rawSql, 'circle_channel_overwrites').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );

    // Bits mirror CirclePermission.channelPermissions.
    final maskBody = functionBody(sql, 'circle_channel_overwrite_permissions');
    for (final name in [
      'view_channel',
      'send_messages',
      'manage_messages',
      'create_invites',
      'mention_everyone',
      'connect_voice',
    ]) {
      expect(maskBody, contains("'$name'"));
    }

    final permissionsBody = functionBody(sql, 'circle_channel_permissions');
    expect(permissionsBody, contains('security definer'));
    expect(permissionsBody, contains('set search_path = public'));
    expect(permissionsBody, contains('permissions & 16384 <> 0'));
    expect(permissionsBody, contains('filter (where r.is_default)'));
    expect(permissionsBody, contains('filter (where mr.role_id is not null)'));
    expect(
      permissionsBody,
      contains('filter (where o.user_id = target_user_id)'),
    );
    // Deny then allow: @everyone, then roles, then the member.
    expect(
      permissionsBody.indexOf('everyone_deny) | everyone_allow'),
      lessThan(permissionsBody.indexOf('roles_deny) | roles_allow')),
    );
    expect(
      permissionsBody.indexOf('roles_deny) | roles_allow'),
      lessThan(permissionsBody.indexOf('member_deny) | member_allow')),
    );

    for (final helper in [
      'circle_channel_permissions(uuid, uuid)',
      'circle_channel_has_permission(uuid, uuid, text)',
      'conversation_circle_channel_id(uuid)',
      'user_has_conversation_channel_permission(uuid, uuid, text)',
    ]) {
      expect(
        rawSql,
        contains(
          'revoke execute on function public.$helper from authenticated',
        ),
      );
    }
    for (final rpc in [
      'current_user_channel_permissions(uuid)',
      'current_user_has_channel_permission(uuid, text)',
      'set_channel_overwrite(uuid, uuid, uuid, bigint, bigint)',
      'list_channel_overwrites(uuid)',
      'set_channel_privacy(uuid, boolean, boolean)',
    ]) {
      expect(
        rawSql,
        contains('grant execute on function public.$rpc to authenticated'),
      );
    }

    final editBody = functionBody(sql, 'check_channel_overwrite_edit');
    expect(editBody, contains("'manage_roles'"));
    expect(editBody, contains("'view_channel'"));
    expect(editBody, contains('target_role.position >= caller_rank'));
    expect(editBody, contains('target_user_id <> current_user_id'));
    expect(editBody, contains('changed_bits & ~caller_permissions <> 0'));

    final setBody = functionBody(sql, 'set_channel_overwrite');
    expect(setBody, contains('auth.uid()'));
    expect(setBody, contains('allow_bits & deny_bits <> 0'));
    expect(setBody, contains('check_channel_overwrite_edit'));
    expect(setBody, contains('allow_bits = 0 and deny_bits = 0'));

    final privacyBody = functionBody(sql, 'set_channel_privacy');
    expect(privacyBody, contains('check_channel_overwrite_edit'));
    expect(privacyBody, contains('r.is_default'));
    expect(privacyBody, contains('highest_role_id'));
  });

  test('channel view and send permissions gate every message path', () {
    final sql = effectiveMigrationSql();

    final memberBody = functionBody(sql, 'is_current_user_conversation_member');
    expect(memberBody, contains('public.circle_channel_overwrites o'));
    expect(memberBody, contains('public.conversation_threads ct'));
    expect(
      memberBody,
      contains('circle_channel_permissions(cc.id, auth.uid())'),
    );

    // Every read path still asks the membership helper.
    for (final name in [
      'reactions',
      'thread_summary',
      'list_pinned_messages',
      'list_threads',
      'list_conversation_media',
      'search_messages',
    ]) {
      expect(
        functionBody(sql, name),
        contains('is_current_user_conversation_member'),
        reason: name,
      );
    }
    expect(
      policyBody(allMigrationSql(), 'messages_select_member'),
      contains(
        'conversation_id in (select public.current_user_readable_conversation_ids())',
      ),
    );
    expect(
      policyBody(allMigrationSql(), 'circle_channels_select_member'),
      contains("current_user_has_channel_permission(id, 'view_channel')"),
    );

    final detailBody = functionBody(sql, 'get_circle_detail');
    expect(detailBody, contains("'current_user_permissions', channel_access"));
    expect(detailBody, contains("'is_private'"));
    expect(detailBody, contains("'is_read_only'"));
    expect(
      functionBody(sql, 'list_conversation_summaries'),
      contains('can_send_messages'),
    );
    expect(
      functionBody(sql, 'list_conversation_summaries'),
      contains("'view_channel'"),
    );
    expect(
      functionBody(sql, 'list_circle_summaries'),
      contains('visible_channels'),
    );
    expect(
      functionBody(sql, 'search_discovery'),
      contains(
        "circle_channel_has_permission(cc.id, auth.uid(), 'view_channel')",
      ),
    );
    expect(
      functionBody(sql, 'reorder_circle_channels'),
      contains('visible_channel_ids'),
    );

    final sendBody = functionBody(sql, 'check_channel_message_send');
    // System notices are written by RPCs that check their own permission.
    expect(sendBody, contains("new.type = 'system'"));
    expect(sendBody, contains("'send_messages'"));
    expect(
      sql,
      contains(
        'create trigger messages_check_channel_send\n'
        '  before insert on public.messages',
      ),
    );
    expect(functionBody(sql, 'create_thread'), contains("'send_messages'"));
  });

  test('channel slowmode is validated, exempts managers and spares threads', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    expect(
      sql,
      contains(
        'add column if not exists slowmode_seconds integer not null default 0',
      ),
    );
    expect(sql, contains('check (slowmode_seconds between 0 and 21600)'));
    expect(sql, contains('messages_conversation_sender_created_idx'));

    final sendBody = functionBody(sql, 'check_channel_message_send');
    expect(sendBody, contains("'send_messages'"));
    // Only the channel itself: threads have their own conversation id.
    expect(
      sendBody,
      contains('where cc.conversation_id = new.conversation_id'),
    );
    expect(sendBody, contains("'manage_messages'"));
    expect(sendBody, contains('pg_advisory_xact_lock'));
    expect(sendBody, contains("m.type <> 'system'"));
    expect(sendBody, contains("errcode = 'P0001'"));
    expect(sendBody, contains('slowmode_remaining_seconds=%s'));

    final setBody = functionBody(sql, 'set_channel_slowmode');
    expect(setBody, contains('security definer'));
    expect(setBody, contains('auth.uid()'));
    expect(setBody, contains("'manage_channels'"));
    expect(setBody, contains('seconds > 21600'));
    expect(
      rawSql,
      contains(
        'grant execute on function '
        'public.set_channel_slowmode(uuid, integer) to authenticated',
      ),
    );

    expect(
      functionBody(sql, 'get_circle_detail'),
      contains("'slowmode_seconds', cc.slowmode_seconds"),
    );
    final summariesBody = functionBody(sql, 'list_conversation_summaries');
    expect(summariesBody, contains('slowmode_seconds integer'));
    expect(summariesBody, contains('when ct.id is null'));
    expect(summariesBody, contains("'manage_messages'"));
    expect(summariesBody, contains('can_send_messages'));
  });

  test('channel permission leftovers: edits, uploads, mentions, reads', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    final readableBody = functionBody(
      sql,
      'current_user_readable_conversation_ids',
    );
    expect(readableBody, contains('returns setof uuid'));
    expect(readableBody, contains('security definer'));
    expect(readableBody, contains('cm.user_id = auth.uid()'));
    expect(
      readableBody,
      contains('circle_channel_permissions(cc.id, auth.uid()) & 1 <> 0'),
    );
    for (final policy in [
      'messages_select_member',
      'message_reactions_select_member',
      'message_mentions_select_member',
      'pinned_messages_select_member',
    ]) {
      expect(
        policyBody(rawSql, policy),
        contains(
          'conversation_id in (select public.current_user_readable_conversation_ids())',
        ),
        reason: policy,
      );
    }

    final membersPolicy = policyBody(
      rawSql,
      'conversation_members_select_member',
    );
    expect(membersPolicy, contains('user_id = auth.uid()'));
    expect(
      membersPolicy,
      contains('public.conversation_member_can_view(conversation_id, user_id)'),
    );
    final canViewBody = functionBody(sql, 'conversation_member_can_view');
    expect(canViewBody, contains('cm.user_id = auth.uid()'));
    expect(canViewBody, contains("'view_channel'"));

    final canSendBody = functionBody(
      sql,
      'can_current_user_send_in_conversation',
    );
    expect(canSendBody, contains('is_current_user_conversation_member'));
    expect(canSendBody, contains("'send_messages'"));
    for (final policy in [
      'chat_images_insert_member',
      'voice_messages_insert_member',
    ]) {
      expect(
        policyBody(rawSql, policy),
        contains('public.can_current_user_send_in_conversation('),
        reason: policy,
      );
    }

    for (final name in ['edit_message', 'set_message_suppress_embeds']) {
      expect(
        functionBody(sql, name),
        contains("'send_messages'"),
        reason: name,
      );
    }
    final sendBody = functionBody(sql, 'send_text_message');
    expect(sendBody, contains('visible_mentions'));
    expect(sendBody, contains("'view_channel'"));

    expect(
      rawSql,
      contains(
        'grant execute on function '
        'public.current_user_readable_conversation_ids() to authenticated',
      ),
    );
  });

  test('members can leave and owners hand the circle over', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    final leaveBody = functionBody(sql, 'leave_circle');
    expect(leaveBody, contains('security definer'));
    expect(leaveBody, contains('set search_path = public'));
    expect(leaveBody, contains('auth.uid()'));
    expect(leaveBody, contains('Transfer ownership before leaving'));
    expect(leaveBody, contains('public.conversation_threads ct'));
    expect(leaveBody, contains('delete from public.circle_members cm'));

    final transferBody = functionBody(sql, 'transfer_circle_ownership');
    expect(transferBody, contains('security definer'));
    expect(transferBody, contains('auth.uid()'));
    expect(transferBody, contains('for update'));
    expect(transferBody, contains('current_owner_id <> current_user_id'));
    expect(transferBody, contains('set owner_id = new_owner_id'));
    expect(transferBody, contains('delete from public.circle_member_roles mr'));

    for (final signature in [
      'public.leave_circle(uuid)',
      'public.transfer_circle_ownership(uuid, uuid)',
    ]) {
      expect(
        rawSql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('circle audit log is read-only for clients and written by RPCs', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    expect(sql, contains('create table if not exists public.circle_audit_log'));
    expect(sql, contains('circle_audit_log_circle_created_idx'));
    expect(
      sql,
      contains('on public.circle_audit_log (circle_id, created_at desc)'),
    );
    expect(
      sql,
      contains('alter table public.circle_audit_log enable row level security'),
    );
    expect(
      policyBody(rawSql, 'circle_audit_log_select_viewer'),
      contains(
        "current_user_has_circle_permission(circle_id, 'view_audit_log')",
      ),
    );
    expect(
      policyBodiesFor(rawSql, 'circle_audit_log').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );
    expect(
      rawSql,
      contains(
        'revoke insert, update, delete, truncate on public.circle_audit_log '
        'from authenticated',
      ),
    );

    final writeBody = functionBody(sql, 'write_circle_audit');
    expect(writeBody, contains('security definer'));
    expect(writeBody, contains('auth.uid()'));
    for (final signature in [
      'public.write_circle_audit(uuid, text, text, uuid, text, jsonb)',
      'public.circle_member_label(uuid, uuid)',
    ]) {
      expect(
        rawSql,
        contains('revoke execute on function $signature from authenticated'),
      );
    }

    final listBody = functionBody(sql, 'list_circle_audit_log');
    expect(listBody, contains("'view_audit_log'"));
    expect(listBody, contains('order by a.created_at desc, a.id desc'));
    expect(listBody, contains("split_part(a.action, '_', 1)"));
    expect(
      rawSql,
      contains(
        'grant execute on function '
        'public.list_circle_audit_log(uuid, timestamptz, integer, text) '
        'to authenticated',
      ),
    );

    // Every management RPC writes its entry.
    const actions = {
      'create_circle_channel': 'channel_create',
      'create_channel_category': 'category_create',
      'rename_channel_category': 'category_rename',
      'delete_channel_category': 'category_delete',
      'reorder_circle_channels': 'channel_reorder',
      'set_channel_overwrite': 'channel_permissions_update',
      'set_channel_privacy': 'channel_privacy_update',
      'set_channel_slowmode': 'channel_slowmode_update',
      'create_circle_role': 'role_create',
      'update_circle_role': 'role_update',
      'delete_circle_role': 'role_delete',
      'reorder_circle_roles': 'role_reorder',
      'set_member_roles': 'member_roles_update',
      'set_circle_nickname': 'member_nickname_update',
      'kick_circle_member': 'member_kick',
      'leave_circle': 'member_leave',
      'transfer_circle_ownership': 'circle_ownership_transfer',
      'create_circle_invite': 'invite_create',
      'revoke_circle_invite': 'invite_revoke',
      'invite_circle_members': 'member_add',
      'pin_message': 'message_pin',
      'unpin_message': 'message_unpin',
      'set_thread_archived': 'thread_archive',
      'delete_circle_post': 'post_delete',
    };
    for (final MapEntry(key: name, value: action) in actions.entries) {
      final body = functionBody(sql, name);
      expect(body, contains('public.write_circle_audit('), reason: name);
      expect(body, contains("'$action'"), reason: name);
    }
  });

  test('channel managers rename, describe and delete channels', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    expect(sql, contains('add column if not exists topic text'));
    expect(sql, contains('char_length(topic) between 1 and 1024'));
    expect(
      sql,
      contains("add column if not exists kind text not null default 'text'"),
    );
    expect(sql, contains("check (kind in ('text', 'voice', 'forum'))"));
    expect(
      sql,
      contains('alter table public.circle_channels replica identity full'),
    );

    final createBody = functionBody(sql, 'create_circle_channel');
    expect(createBody, contains("target_kind text default 'text'"));
    expect(
      sql,
      contains(
        'drop function if exists public.create_circle_channel(uuid, text, uuid)',
      ),
    );

    for (final name in ['update_circle_channel', 'delete_circle_channel']) {
      final body = functionBody(sql, name);
      expect(body, contains('security definer'), reason: name);
      expect(body, contains('set search_path = public'), reason: name);
      expect(body, contains('auth.uid()'), reason: name);
      expect(body, contains("'manage_channels'"), reason: name);
      expect(body, contains("'view_channel'"), reason: name);
      expect(body, contains('public.write_circle_audit('), reason: name);
    }
    final updateBody = functionBody(sql, 'update_circle_channel');
    expect(updateBody, contains("'channel_update'"));
    expect(updateBody, contains('> 1024'));
    expect(updateBody, contains('update public.conversations c'));
    final deleteBody = functionBody(sql, 'delete_circle_channel');
    expect(deleteBody, contains("'channel_delete'"));
    expect(deleteBody, contains('delete from public.conversations c'));

    final detailBody = functionBody(sql, 'get_circle_detail');
    expect(detailBody, contains("'topic', cc.topic"));
    expect(detailBody, contains("'kind', cc.kind"));

    for (final signature in [
      'public.create_circle_channel(uuid, text, uuid, text)',
      'public.update_circle_channel(uuid, text, text)',
      'public.delete_circle_channel(uuid)',
    ]) {
      expect(
        rawSql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('forum channels hold posts with tags', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    expect(
      sql,
      contains(
        'add column if not exists is_pinned boolean not null default false',
      ),
    );
    for (final table in ['forum_tags', 'thread_tags']) {
      expect(sql, contains('create table if not exists public.$table'));
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(sql, contains('alter table public.$table replica identity full'));
      expect(
        rawSql,
        contains('alter publication supabase_realtime add table public.$table'),
      );
      expect(
        rawSql,
        contains(
          'revoke insert, update, delete, truncate on public.$table '
          'from authenticated',
        ),
      );
      expect(
        policyBodiesFor(rawSql, table).where(
          (policy) => RegExp(
            r'for (insert|update|delete|all)',
            caseSensitive: false,
          ).hasMatch(policy),
        ),
        isEmpty,
      );
    }
    expect(sql, contains('char_length(name) between 1 and 20'));
    expect(sql, contains('on public.forum_tags (channel_id, lower(name))'));
    expect(
      policyBody(rawSql, 'forum_tags_select_viewer'),
      contains(
        "current_user_has_channel_permission(channel_id, 'view_channel')",
      ),
    );
    expect(
      policyBody(rawSql, 'thread_tags_select_viewer'),
      contains(
        "current_user_has_channel_permission(channel_id, 'view_channel')",
      ),
    );

    final normalizeBody = functionBody(sql, 'normalize_forum_tag_ids');
    expect(normalizeBody, contains('cardinality(normalized) > 5'));
    final createTagBody = functionBody(sql, 'create_forum_tag');
    expect(createTagBody, contains('>= 20'));

    final createPostBody = functionBody(sql, 'create_forum_post');
    expect(createPostBody, contains('can_current_user_send_in_conversation'));
    expect(createPostBody, contains("channel.kind <> 'forum'"));
    expect(createPostBody, contains('insert into public.conversation_threads'));
    expect(createPostBody, contains('insert into public.messages'));
    expect(createPostBody, contains('insert into public.thread_tags'));
    expect(createPostBody, contains("'chat-images'"));

    final listBody = functionBody(sql, 'list_forum_posts');
    expect(listBody, contains('is_current_user_conversation_member'));
    expect(listBody, contains("sort_order not in ('activity', 'created')"));
    expect(listBody, contains('order by chosen.grp, chosen.sort_at desc'));

    expect(
      functionBody(sql, 'pin_forum_post'),
      contains(
        "current_user_has_channel_permission(channel.id, 'manage_messages')",
      ),
    );
    expect(
      functionBody(sql, 'set_forum_post_tags'),
      contains('can_current_user_manage_thread'),
    );

    const audited = {
      'pin_forum_post': 'forum_post_pin',
      'create_forum_tag': 'forum_tag_create',
      'update_forum_tag': 'forum_tag_update',
      'delete_forum_tag': 'forum_tag_delete',
      'reorder_forum_tags': 'forum_tag_reorder',
    };
    for (final MapEntry(key: name, value: action) in audited.entries) {
      final body = functionBody(sql, name);
      expect(body, contains('security definer'), reason: name);
      expect(body, contains('set search_path = public'), reason: name);
      expect(body, contains('public.write_circle_audit('), reason: name);
      expect(body, contains("'$action'"), reason: name);
    }
    for (final name in ['create_forum_tag', 'reorder_forum_tags']) {
      expect(
        functionBody(sql, name),
        contains(
          "forum_channel_for_management(target_channel_id, 'manage_channels')",
        ),
        reason: name,
      );
    }

    // Forums take no direct messages or plain threads.
    expect(
      functionBody(sql, 'check_channel_message_send'),
      contains("channel.kind = 'forum'"),
    );
    expect(
      functionBody(sql, 'create_thread'),
      contains('Forum channels take posts, not threads'),
    );
    expect(
      functionBody(sql, 'create_circle_channel'),
      contains("channel_kind not in ('text', 'forum'"),
    );
    expect(
      functionBody(sql, 'get_circle_detail'),
      contains('from public.forum_tags ft'),
    );

    for (final signature in [
      'public.forum_channel_for_management(uuid, text)',
      'public.normalize_forum_tag_ids(uuid, uuid[])',
      'public.forum_post_payload(public.conversation_threads, public.circle_channels)',
    ]) {
      expect(
        rawSql,
        contains('revoke execute on function $signature from authenticated'),
      );
    }
    for (final signature in [
      'public.create_forum_post(uuid, text, text, uuid[], jsonb)',
      'public.list_forum_posts(uuid, text, uuid, timestamptz, uuid, integer)',
      'public.set_forum_post_tags(uuid, uuid[])',
      'public.pin_forum_post(uuid, boolean)',
      'public.create_forum_tag(uuid, text, text)',
      'public.update_forum_tag(uuid, text, text)',
      'public.delete_forum_tag(uuid)',
      'public.reorder_forum_tags(uuid, uuid[])',
    ]) {
      expect(
        rawSql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('forum posts record mentions of members who can see the forum', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    expect(
      rawSql,
      contains(
        'drop function if exists '
        'public.create_forum_post(uuid, text, text, uuid[], jsonb);',
      ),
    );
    final body = functionBody(sql, 'create_forum_post');
    expect(body, contains("post_mentions jsonb default '[]'::jsonb"));
    expect(body, contains('mentioned users must be conversation members'));
    expect(body, contains('public.user_has_conversation_channel_permission('));
    expect(body, contains("'view_channel'"));
    expect(body, contains('insert into public.message_mentions'));
    expect(body, contains('visible_mentions'));
    expect(
      rawSql,
      contains(
        'grant execute on function '
        'public.create_forum_post(uuid, text, text, uuid[], jsonb, jsonb) '
        'to authenticated',
      ),
    );
  });

  test('circle events are member scoped, RPC written, audited and realtime', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    for (final table in ['circle_events', 'circle_event_rsvps']) {
      expect(sql, contains('create table if not exists public.$table'));
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(sql, contains('alter table public.$table replica identity full'));
      expect(
        rawSql,
        contains('alter publication supabase_realtime add table public.$table'),
      );
      expect(
        rawSql,
        contains(
          'revoke insert, update, delete, truncate on public.$table '
          'from authenticated',
        ),
      );
      expect(
        policyBodiesFor(rawSql, table).where(
          (policy) => RegExp(
            r'for (insert|update|delete|all)',
            caseSensitive: false,
          ).hasMatch(policy),
        ),
        isEmpty,
      );
    }
    expect(sql, contains('char_length(title) between 1 and 100'));
    expect(sql, contains('char_length(description) between 1 and 2000'));
    expect(sql, contains("location_type in ('voice', 'text', 'external')"));
    expect(sql, contains('ends_at is null or ends_at > starts_at'));
    expect(sql, contains('on delete set null (channel_id)'));
    expect(
      sql,
      contains('references public.circle_members(circle_id, user_id)'),
    );
    expect(
      policyBody(rawSql, 'circle_events_select_viewer'),
      contains(
        "current_user_has_channel_permission(channel_id, 'view_channel')",
      ),
    );
    expect(
      policyBody(rawSql, 'circle_event_rsvps_select_viewer'),
      contains('is_current_user_circle_member(circle_id)'),
    );

    expect(
      functionBody(sql, 'create_circle_event'),
      contains("'manage_events'"),
    );
    expect(
      functionBody(sql, 'circle_event_for_management'),
      contains('created_by is not distinct from auth.uid()'),
    );
    final normalizeBody = functionBody(sql, 'normalize_circle_event');
    expect(normalizeBody, contains('Event must end after it starts'));
    expect(normalizeBody, contains("'view_channel'"));
    const audited = {
      'create_circle_event': 'event_create',
      'update_circle_event': 'event_update',
      'cancel_circle_event': 'event_cancel',
    };
    for (final MapEntry(key: name, value: action) in audited.entries) {
      final body = functionBody(sql, name);
      expect(body, contains('security definer'), reason: name);
      expect(body, contains('set search_path = public'), reason: name);
      expect(body, contains('public.write_circle_audit('), reason: name);
      expect(body, contains("'$action'"), reason: name);
    }
    for (final name in [
      'toggle_event_interest',
      'list_circle_events',
      'list_event_interested',
      'list_my_upcoming_event_reminders',
    ]) {
      final body = functionBody(sql, name);
      expect(body, contains('security definer'), reason: name);
      expect(body, contains('auth.uid()'), reason: name);
    }
    expect(
      functionBody(sql, 'list_circle_events'),
      contains('order by e.starts_at, e.id'),
    );
    expect(
      functionBody(sql, 'list_my_upcoming_event_reminders'),
      contains("interval '24 hours'"),
    );

    for (final signature in [
      'public.current_user_can_see_circle_event(public.circle_events)',
      'public.circle_event_payload(public.circle_events)',
      'public.circle_event_for_management(uuid)',
      'public.normalize_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz)',
    ]) {
      expect(
        rawSql,
        contains('revoke execute on function $signature from authenticated'),
      );
    }
    for (final signature in [
      'public.create_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz)',
      'public.update_circle_event(uuid, text, text, text, uuid, text, timestamptz, timestamptz)',
      'public.cancel_circle_event(uuid)',
      'public.toggle_event_interest(uuid)',
      'public.list_circle_events(uuid, boolean)',
      'public.list_event_interested(uuid)',
      'public.list_my_upcoming_event_reminders()',
    ]) {
      expect(
        rawSql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('polls are RPC written, member scoped, realtime and not forwarded', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    expect(
      rawSql,
      contains(
        "check (type in ('text', 'image', 'file', 'voice', 'system', 'poll'))",
      ),
    );
    final insertPolicy = policyBody(rawSql, 'messages_insert_member');
    expect(insertPolicy, contains("type <> 'system'"));
    expect(insertPolicy, contains("type <> 'poll'"));

    expect(
      sql,
      contains('create table if not exists public.message_poll_votes'),
    );
    expect(sql, contains('primary key (message_id, user_id, option_id)'));
    expect(
      sql,
      contains(
        'alter table public.message_poll_votes enable row level security',
      ),
    );
    expect(
      sql,
      contains('alter table public.message_poll_votes replica identity full'),
    );
    expect(
      rawSql,
      contains(
        'alter publication supabase_realtime add table public.message_poll_votes',
      ),
    );
    expect(
      policyBody(rawSql, 'message_poll_votes_select_member'),
      contains('current_user_readable_conversation_ids()'),
    );
    expect(
      policyBodiesFor(rawSql, 'message_poll_votes').where(
        (policy) => RegExp(
          r'for (insert|update|delete|all)',
          caseSensitive: false,
        ).hasMatch(policy),
      ),
      isEmpty,
    );

    final createBody = functionBody(sql, 'create_poll');
    expect(createBody, contains('Poll question must be 1 to 300 characters'));
    expect(createBody, contains('A poll needs 2 to 10 options'));
    expect(createBody, contains('Poll options must be 1 to 100 characters'));
    expect(createBody, contains('is_current_user_blocked_in_conversation'));
    final voteBody = functionBody(sql, 'vote_poll');
    expect(voteBody, contains('public.poll_is_closed(poll)'));
    expect(voteBody, contains('This poll takes one answer'));
    expect(voteBody, contains('for share'));
    final endBody = functionBody(sql, 'end_poll');
    expect(endBody, contains('can_current_user_moderate_polls'));
    expect(
      functionBody(sql, 'can_current_user_moderate_polls'),
      contains("'manage_messages'"),
    );
    final resultsBody = functionBody(sql, 'poll_results');
    expect(resultsBody, contains("'total_voters'"));
    expect(resultsBody, contains("'my_votes'"));
    expect(resultsBody, contains('is_current_user_conversation_member'));
    expect(
      functionBody(sql, 'list_poll_voters'),
      contains('is_current_user_conversation_member(m.conversation_id)'),
    );
    expect(functionBody(sql, 'forward_message'), contains("type <> 'poll'"));
    expect(
      functionBody(sql, 'search_messages'),
      contains('public.message_search_text(m.type, m.body, m.attachment)'),
    );
    for (final name in [
      'create_poll',
      'vote_poll',
      'end_poll',
      'poll_results',
      'list_poll_voters',
    ]) {
      final body = functionBody(sql, name);
      expect(body, contains('security definer'), reason: name);
      expect(body, contains('set search_path = public'), reason: name);
      expect(body, contains('auth.uid()'), reason: name);
    }
    expect(
      rawSql,
      contains(
        'revoke execute on function public.poll_is_closed(public.messages) '
        'from authenticated',
      ),
    );
    for (final signature in [
      'public.create_poll(uuid, text, text[], boolean, integer)',
      'public.vote_poll(uuid, text[])',
      'public.end_poll(uuid)',
      'public.poll_results(public.messages)',
      'public.list_poll_voters(uuid, text)',
    ]) {
      expect(
        rawSql,
        contains('grant execute on function $signature to authenticated'),
      );
    }
  });

  test('channel webhooks hide tokens, post only via service role, audited', () {
    final sql = effectiveMigrationSql();
    final rawSql = allMigrationSql();

    for (final table in ['circle_webhooks', 'webhook_rate']) {
      expect(sql, contains('create table if not exists public.$table'));
      expect(
        sql,
        contains('alter table public.$table enable row level security'),
      );
      expect(
        rawSql,
        contains('revoke all on public.$table from authenticated'),
      );
      expect(policyBodiesFor(rawSql, table), isEmpty);
    }
    expect(sql, contains("token_hash ~ '^[0-9a-f]{64}\$'"));
    expect(
      sql,
      contains(
        'add column if not exists webhook_id uuid\n'
        '    references public.circle_webhooks(id) on delete set null',
      ),
    );
    final insertPolicy = policyBody(rawSql, 'messages_insert_member');
    expect(insertPolicy, contains('webhook_id is null'));
    expect(insertPolicy, contains('webhook_name is null'));
    expect(insertPolicy, contains('webhook_avatar_url is null'));

    expect(
      functionBody(sql, 'channel_webhook_payload'),
      isNot(contains('token_hash')),
    );
    expect(
      functionBody(sql, 'webhook_token_hash'),
      contains(
        "encode(sha256(convert_to(coalesce(token, ''), 'UTF8')), 'hex')",
      ),
    );
    expect(
      functionBody(sql, 'new_webhook_token'),
      contains('extensions.gen_random_bytes(32)'),
    );

    const audited = {
      'create_channel_webhook': 'webhook_create',
      'rename_channel_webhook': 'webhook_update',
      'regenerate_webhook_token': 'webhook_regenerate',
      'delete_channel_webhook': 'webhook_delete',
    };
    for (final MapEntry(key: name, value: action) in audited.entries) {
      final body = functionBody(sql, name);
      expect(body, contains('security definer'), reason: name);
      expect(body, contains('set search_path = public'), reason: name);
      expect(body, contains('public.write_circle_audit('), reason: name);
      expect(body, contains("'$action'"), reason: name);
    }
    expect(
      functionBody(sql, 'channel_webhook_for_management'),
      contains("'manage_webhooks'"),
    );
    expect(
      functionBody(sql, 'list_channel_webhooks'),
      contains("'manage_webhooks'"),
    );

    final post = functionBody(sql, 'post_webhook_message');
    expect(post, contains('security definer'));
    expect(post, contains('public.webhook_token_hash(webhook_token)'));
    expect(post, contains('between 1 and 2000'));
    expect(post, contains("'send_messages'"));
    expect(post, contains("'manage_webhooks'"));
    expect(post, contains("errcode = 'WH429'"));
    expect(post, contains('sent_this_minute > 30'));
    expect(post, contains('set last_used_at = now()'));
    for (final role in ['public', 'anon', 'authenticated']) {
      expect(
        rawSql,
        contains(
          'revoke execute on function '
          'public.post_webhook_message(uuid, text, text, text, text) '
          'from $role',
        ),
      );
    }
    expect(
      rawSql,
      contains(
        'grant execute on function '
        'public.post_webhook_message(uuid, text, text, text, text) '
        'to service_role',
      ),
    );
    expect(
      rawSql,
      isNot(
        contains(
          'grant execute on function '
          'public.post_webhook_message(uuid, text, text, text, text) '
          'to authenticated',
        ),
      ),
    );

    final check = functionBody(sql, 'check_channel_message_send');
    expect(check, contains('or new.webhook_name is not null'));
    expect(check, contains('and m.webhook_name is null'));
    expect(
      functionBody(sql, 'edit_message'),
      contains('m.webhook_name is null'),
    );
    final summaries = functionBody(sql, 'list_conversation_summaries');
    expect(summaries, contains('last_message_webhook_name'));
    expect(summaries, contains('or unread_messages.webhook_name is not null'));
    expect(
      functionBody(sql, 'list_circle_summaries'),
      contains('or unread_message.webhook_name is not null'),
    );

    final config = File('supabase/config.toml').readAsStringSync();
    expect(config, contains('[functions.webhook]\nenabled = true\n'));
    expect(
      RegExp(
        r'\[functions\.webhook\][^\[]*verify_jwt = false',
      ).hasMatch(config),
      isTrue,
    );
  });

  test('moderators delete others\' messages, audited in circle channels', () {
    final sql = effectiveMigrationSql();
    expect(
      sql,
      contains(
        'add column if not exists recalled_by uuid\n'
        '    references public.profiles(id) on delete set null',
      ),
    );
    expect(
      policyBody(allMigrationSql(), 'messages_insert_member'),
      contains('recalled_by is null'),
    );

    final moderate = functionBody(sql, 'can_current_user_moderate_messages');
    expect(moderate, contains("'manage_messages'"));
    expect(moderate, contains("cm.role in ('owner', 'admin')"));
    expect(moderate, contains('public.conversation_circle_channel_id'));

    final recall = functionBody(sql, 'recall_message');
    expect(recall, contains("target.type = 'system'"));
    expect(recall, contains('public.can_current_user_moderate_messages'));
    expect(recall, contains('recalled_by = current_user_id'));
    expect(recall, contains("'message_delete'"));
    expect(recall, isNot(contains('target.body')));
    expect(
      sql,
      contains(
        'grant execute on function '
        'public.can_current_user_moderate_messages(uuid) to authenticated;',
      ),
    );
  });

  test('circle emoji and stickers: storage, limits, reactions, stickers', () {
    final sql = effectiveMigrationSql();
    expect(sql, contains('create table if not exists public.circle_emojis'));
    expect(sql, contains("check (name ~ '^[a-z0-9_]{2,32}\$')"));
    expect(sql, contains("check (kind in ('emoji', 'sticker'))"));
    expect(sql, contains('unique (circle_id, kind, name)'));
    expect(
      sql,
      contains('alter table public.circle_emojis enable row level security;'),
    );
    expect(
      sql,
      contains(
        'revoke insert, update, delete, truncate on public.circle_emojis '
        'from authenticated;',
      ),
    );
    expect(
      policyBody(allMigrationSql(), 'circle_emojis_select_member'),
      contains('public.is_current_user_circle_member(circle_id)'),
    );

    expect(sql, contains("'circle-emojis',\n  false,\n  262144,"));
    expect(sql, contains("array['image/png', 'image/gif', 'image/webp']"));
    expect(
      policyBody(sql, 'circle_emojis_storage_select_member'),
      contains('public.is_current_user_circle_member('),
    );
    for (final policy in [
      'circle_emojis_storage_insert_manager',
      'circle_emojis_storage_delete_manager',
    ]) {
      final body = policyBody(sql, policy);
      expect(body, contains("bucket_id = 'circle-emojis'"));
      expect(body, contains("'manage_emojis'"));
      expect(body, contains('public.circle_emoji_object_circle_id(name)'));
    }

    final create = functionBody(sql, 'create_circle_emoji');
    expect(create, contains("'manage_emojis'"));
    expect(create, contains('from storage.objects o'));
    expect(create, contains('for update'));
    expect(create, contains('then 50 else 20 end'));
    expect(create, contains("emoji_kind || '_create'"));
    expect(
      functionBody(sql, 'rename_circle_emoji'),
      contains("emoji.kind || '_update'"),
    );
    final delete = functionBody(sql, 'delete_circle_emoji');
    expect(delete, contains("emoji.kind || '_delete'"));
    expect(delete, contains('return emoji.storage_path;'));
    expect(
      functionBody(sql, 'circle_emoji_for_management'),
      contains("'manage_emojis'"),
    );
    expect(
      functionBody(sql, 'list_my_usable_emojis'),
      contains('cm.user_id = auth.uid()'),
    );

    final toggle = functionBody(sql, 'toggle_message_reaction');
    expect(toggle, contains("normalized_emoji like 'custom:%'"));
    expect(toggle, contains("e.kind = 'emoji'"));
    expect(toggle, contains('cm.user_id = current_user_id'));
    expect(functionBody(sql, 'reactions'), contains("'custom_name'"));

    expect(
      sql,
      contains(
        "check (type in ('text', 'image', 'file', 'voice', 'system', 'poll', "
        "'sticker'))",
      ),
    );
    expect(
      policyBody(allMigrationSql(), 'messages_insert_member'),
      contains("type <> 'sticker'"),
    );
    final sticker = functionBody(sql, 'send_sticker');
    expect(sticker, contains("e.kind = 'sticker'"));
    expect(sticker, contains('public.is_current_user_circle_member'));
    expect(sticker, contains('public.is_current_user_conversation_member'));
    expect(
      functionBody(sql, 'forward_message'),
      contains("and type <> 'sticker'"),
    );

    for (final grant in [
      'create_circle_emoji(uuid, text, text, text, text)',
      'rename_circle_emoji(uuid, text)',
      'delete_circle_emoji(uuid)',
      'list_circle_emojis(uuid)',
      'list_my_usable_emojis()',
      'send_sticker(uuid, uuid)',
    ]) {
      expect(
        sql,
        contains('grant execute on function public.$grant to authenticated;'),
      );
    }
    expect(
      sql,
      contains(
        'revoke execute on function '
        'public.circle_emoji_for_management(uuid) from authenticated;',
      ),
    );
  });

  test('deleted messages keep no content', () {
    final sql = effectiveMigrationSql();
    expect(
      sql,
      contains(
        "    type <> 'text'\n"
        '    or recalled_at is not null\n'
        '    or char_length(trim(body)) > 0',
      ),
    );
    expect(
      sql,
      contains('create table if not exists public.recalled_message_media'),
    );
    expect(
      sql,
      contains(
        'alter table public.recalled_message_media enable row level security;',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.recalled_message_media from anon, authenticated;',
      ),
    );

    final recall = functionBody(sql, 'recall_message');
    expect(
      recall,
      contains('returns table (bucket_id text, object_path text)'),
    );
    expect(recall, contains("body = '',"));
    expect(recall, contains('attachment = null,'));
    expect(recall, contains('reply_preview = null,'));
    expect(recall, contains('forwarded_from = null,'));
    expect(recall, contains("mentions = '[]'::jsonb"));
    for (final table in [
      'message_mentions',
      'message_reactions',
      'message_poll_votes',
      'pinned_messages',
    ]) {
      expect(recall, contains('delete from public.$table'));
    }
    expect(recall, contains("jsonb_build_object('body', '')"));
    expect(recall, contains('insert into public.recalled_message_media'));
    expect(recall, contains("'message_delete'"));
    expect(recall, isNot(contains('target.body')));

    final canDelete = functionBody(
      sql,
      'can_current_user_delete_recalled_media',
    );
    expect(canDelete, contains('r.deleted_by = auth.uid()'));
    expect(canDelete, contains("m.attachment->>'path' = target_object_path"));
    final policy = policyBody(sql, 'message_media_delete_recalled');
    expect(policy, contains('on storage.objects for delete'));
    expect(
      policy,
      contains(
        'public.can_current_user_delete_recalled_media(bucket_id, name)',
      ),
    );

    // Messages deleted earlier are wiped too.
    expect(sql, contains('where m.recalled_at is not null\n  and (\n'));
    expect(
      sql,
      contains(
        'grant execute on function public.recall_message(uuid) to authenticated;',
      ),
    );
  });

  test('voice channels: states, heartbeats and token access', () {
    final sql = effectiveMigrationSql();
    expect(
      functionBody(sql, 'create_circle_channel'),
      contains("channel_kind not in ('text', 'forum', 'voice')"),
    );
    final send = functionBody(sql, 'check_channel_message_send');
    expect(send, contains("if channel.kind = 'voice' then"));
    expect(send, contains("if channel.kind = 'forum' then"));
    expect(send, contains('new.webhook_name is not null'));

    expect(sql, contains('create table if not exists public.voice_states'));
    expect(sql, contains('primary key (channel_id, user_id)'));
    expect(
      sql,
      contains('constraint voice_states_one_channel unique (user_id)'),
    );
    expect(sql, contains('references public.circle_channels(id, circle_id)'));
    expect(
      sql,
      contains('alter table public.voice_states replica identity full;'),
    );
    expect(
      sql,
      contains('alter table public.voice_states enable row level security;'),
    );
    expect(
      sql,
      contains(
        'revoke insert, update, delete, truncate on public.voice_states '
        'from authenticated;',
      ),
    );
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.voice_states;',
      ),
    );
    final select = policyBody(allMigrationSql(), 'voice_states_select_viewer');
    expect(select, contains('public.is_current_user_circle_member(circle_id)'));
    expect(select, contains("'view_channel'"));

    expect(
      functionBody(sql, 'voice_state_ttl'),
      contains("interval '60 seconds'"),
    );
    final join = functionBody(sql, 'join_voice_state');
    expect(join, contains("channel.kind <> 'voice'"));
    expect(join, contains("'connect_voice'"));
    expect(
      join,
      contains(
        'delete from public.voice_states vs where vs.user_id = current_user_id;',
      ),
    );
    expect(join, contains('pg_advisory_xact_lock'));
    final update = functionBody(sql, 'update_voice_state');
    expect(
      update,
      contains('vs.last_seen_at <= now() - public.voice_state_ttl()'),
    );
    expect(update, contains("'connect_voice'"));
    expect(update, contains('return false;'));
    final list = functionBody(sql, 'list_voice_states');
    expect(
      list,
      contains('public.is_current_user_circle_member(target_circle_id)'),
    );
    expect(
      list,
      contains('vs.last_seen_at > now() - public.voice_state_ttl()'),
    );
    expect(list, contains("'role_color'"));
    final access = functionBody(sql, 'can_current_user_connect_voice');
    expect(access, contains("'connect_voice'"));
    expect(access, contains("'display_name'"));

    for (final grant in [
      'join_voice_state(uuid)',
      'update_voice_state(boolean, boolean, boolean, boolean)',
      'leave_voice_state()',
      'list_voice_states(uuid)',
      'can_current_user_connect_voice(uuid)',
    ]) {
      expect(
        sql,
        contains('grant execute on function public.$grant to authenticated;'),
      );
      expect(
        sql,
        contains('revoke execute on function public.$grant from anon;'),
      );
    }
  });

  test('livekit-token function checks access and its configuration', () {
    final config = File('supabase/config.toml').readAsStringSync();
    expect(
      config,
      contains(
        '[functions.livekit-token]\n'
        'enabled = true\n'
        '# Signed-in members only; the function checks connect_voice as the caller.\n'
        'verify_jwt = true',
      ),
    );
    final index = File(
      'supabase/functions/livekit-token/index.ts',
    ).readAsStringSync();
    expect(index, contains('auth.getUser('));
    expect(index, contains('"can_current_user_connect_voice"'));
    expect(index, contains('{ error: "voice_not_configured" }, 503'));
    expect(index, isNot(contains('SERVICE_ROLE')));
  });
}

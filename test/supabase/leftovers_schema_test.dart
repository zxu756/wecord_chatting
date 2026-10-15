import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for the leftovers of the 2026-10-16 batch.
void main() {
  String migration(String prefix) {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere(
          (file) => file.uri.pathSegments.last.startsWith(prefix),
          orElse: () => throw StateError('Missing migration $prefix'),
        );
    return file.readAsStringSync();
  }

  test('circle emoji changes reach open clients through realtime', () {
    final sql = migration('202610160014');

    expect(
      sql,
      contains('alter table public.circle_emojis replica identity full'),
    );
    expect(
      sql,
      contains(
        'alter publication supabase_realtime add table public.circle_emojis',
      ),
    );
    expect(sql, contains("tablename = 'circle_emojis'"));
  });

  test('group admins can pin as well as the owner', () {
    final sql = migration('202610160015');

    expect(
      sql,
      contains(
        'create or replace function public.can_current_user_pin_messages',
      ),
    );
    final group = RegExp(
      r"when 'group' then[\s\S]*?when 'channel'",
    ).firstMatch(sql)!.group(0)!;
    expect(group, contains("cm.role in ('owner', 'admin')"));
    // Channels and threads keep their checks.
    expect(sql, contains("'manage_messages'"));
    expect(
      sql,
      contains(
        'public.can_current_user_pin_messages(ct.parent_conversation_id)',
      ),
    );
  });

  test('reactions load per page and check membership once', () {
    final sql = migration('202610160016');

    expect(
      sql,
      contains(
        'on public.message_reactions (conversation_id, message_id, emoji)',
      ),
    );
    expect(sql, contains('include (user_id, created_at)'));

    final page = RegExp(
      r'create or replace function public\.list_conversation_reactions[\s\S]*?\n\$\$;',
    ).firstMatch(sql)!.group(0)!;
    expect(page, contains('security definer'));
    expect(page, contains('set search_path = public'));
    expect(
      page,
      contains(
        'public.is_current_user_conversation_member(target_conversation_id)',
      ),
    );
    expect(page, contains('m.recalled_at is null'));
    expect(page, contains("'custom_name'"));
    expect(
      sql,
      contains(
        'revoke execute on function public.list_conversation_reactions(uuid) from anon',
      ),
    );

    final field = RegExp(
      r'create or replace function public\.reactions\([\s\S]*?\n\$\$;',
    ).firstMatch(sql)!.group(0)!;
    // Once per message, not once per reaction.
    expect(
      field,
      contains(
        'public.is_current_user_conversation_member(\n      message_row.conversation_id',
      ),
    );
    expect(field, contains('mr.conversation_id = message_row.conversation_id'));
    expect(field, contains('message_row.recalled_at is not null'));
  });

  test('deleted channels and circles return their files for removal', () {
    final sql = migration('202610160017');

    String function(String name) => RegExp(
      'create or replace function public\\.$name\\([\\s\\S]*?\\n\\\$\\\$;',
    ).firstMatch(sql)!.group(0)!;

    final remember = function('remember_conversation_media');
    expect(remember, contains('insert into public.recalled_message_media'));
    expect(
      remember,
      contains("in ('chat-images', 'voice-messages', 'chat-files')"),
    );
    expect(
      sql,
      contains(
        'revoke execute on function public.remember_conversation_media(uuid[], uuid) from authenticated',
      ),
    );

    for (final name in ['delete_circle_channel', 'prepare_account_deletion']) {
      final body = function(name);
      expect(
        body,
        contains('returns table (bucket_id text, object_path text)'),
        reason: name,
      );
      expect(
        body,
        contains('public.remember_conversation_media('),
        reason: name,
      );
      // Files a forwarded copy still uses stay.
      expect(
        body,
        contains("m.attachment->>'path' = u.media_path"),
        reason: name,
      );
      expect(sql, contains('drop function if exists public.$name('));
    }
    final channel = function('delete_circle_channel');
    expect(channel, contains("'manage_channels'"));
    expect(channel, contains("'channel_delete'"));
    expect(
      channel,
      contains('ct.parent_conversation_id = channel.conversation_id'),
    );
    final account = function('prepare_account_deletion');
    expect(account, contains("o.bucket_id in ('circle-emojis', 'chat-media')"));
    expect(account, contains("errcode = '55000'"));

    final edge = File(
      'supabase/functions/delete-account/index.ts',
    ).readAsStringSync();
    expect(edge, contains('data: deletedObjects'));
    expect(edge, contains('admin.storage.from(bucket).remove('));
  });

  test('pushes check what each recipient can see, not the caller', () {
    final sql = migration('202610160032');
    final claim = RegExp(
      r'create or replace function public\.claim_push_delivery\([\s\S]*?\n\$\$;',
    ).firstMatch(sql)!.group(0)!;

    // The push function calls it with the service role (no auth.uid()).
    expect(claim, isNot(contains('conversation_member_can_view')));
    expect(claim, isNot(contains('auth.uid()')));
    expect(claim, contains('public.user_has_conversation_channel_permission('));
    expect(claim, contains("'view_channel'"));
    // Do Not Disturb, mutes and blocks still leave recipients out.
    expect(claim, contains("coalesce(ups.presence_status, 'online') <> 'dnd'"));
    expect(claim, contains('public.are_users_blocked('));
    expect(
      sql,
      contains(
        'grant execute on function public.claim_push_delivery(uuid, uuid) to service_role',
      ),
    );
  });
}

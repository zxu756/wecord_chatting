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
}

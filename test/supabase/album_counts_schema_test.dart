import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for albums counting as one message: unread and mention
/// counts, conversation summaries, the inbox and pushes.
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

  // The album-aware count: rows, less the album rows, plus one per album.
  final albumCount = RegExp(
    r'count\(\*\)\s*-\s*count\((\w+)\.attachment_group_id\)\s*\+\s*count\(distinct \1\.attachment_group_id\)',
  );

  group('202610170002 counts', () {
    late String sql;

    setUpAll(() => sql = migration('202610170002'));

    test('unread and reply counts take an album once', () {
      // list_circle_summaries (unread), thread_payload (reply, unread) and
      // forum_post_payload (reply, unread).
      expect(albumCount.allMatches(sql).length, 5);
      expect(
        sql,
        contains(
          'count(distinct coalesce(\n'
          '          mentioned_message.attachment_group_id,\n'
          '          mentioned_message.id\n'
          '        ))',
        ),
      );
    });

    test('redefines the newest version of each function', () {
      for (final signature in [
        'create or replace function public.list_circle_summaries()',
        'create or replace function public.thread_payload(thread_row public.conversation_threads)',
        'create or replace function public.forum_post_payload(',
        'create or replace function public.list_inbox(p_limit integer default 50)',
      ]) {
        expect(sql, contains(signature));
      }
      // From 202610160003, not the first inbox: @here and role mentions.
      expect(sql, contains("'mention_here'"));
      // From 202610130024: webhook messages are unread for their creator.
      expect(sql, contains('unread_message.webhook_name is not null'));
    });

    test('the inbox lists an album once, per sender', () {
      expect(
        sql,
        contains(
          'distinct on (m.sender_id, coalesce(m.attachment_group_id, m.id))',
        ),
      );
      expect(
        sql,
        contains('limit greatest(1, least(coalesce(p_limit, 50), 100))'),
      );
      expect(sql, contains('security invoker'));
      expect(
        sql,
        contains(
          'grant execute on function public.list_inbox(integer) to authenticated',
        ),
      );
    });

    test('unread counting rides an index with the album id in it', () {
      expect(
        sql,
        contains(
          'create index if not exists messages_conversation_unread_idx\n'
          '  on public.messages (conversation_id, created_at desc)\n'
          '  include (sender_id, attachment_group_id, webhook_name)',
        ),
      );
    });

    test('helper functions stay locked down', () {
      for (final role in ['public', 'anon', 'authenticated']) {
        expect(
          sql,
          contains(
            'revoke execute on function public.thread_payload(public.conversation_threads) from $role',
          ),
        );
        expect(
          sql,
          contains(
            'revoke execute on function public.forum_post_payload(public.conversation_threads, public.circle_channels) from $role',
          ),
        );
      }
    });
  });

  group('202610170003 summaries', () {
    late String sql;

    setUpAll(() => sql = migration('202610170003'));

    test('unread counts an album once and has no GROUP BY over everything', () {
      expect(
        sql,
        contains(
          'count(unread_messages.id)\n'
          '        - count(unread_messages.attachment_group_id)\n'
          '        + count(distinct unread_messages.attachment_group_id)',
        ),
      );
      expect(sql, contains('unread_counts as ('));
      expect(
        sql,
        contains('left join unread_counts uc on uc.conversation_id = c.id'),
      );
      // The unread rows are no longer joined into the summary query.
      expect(sql, isNot(contains('left join public.messages unread_messages')));
    });

    test('keeps what 202610160050 returned and adds the album', () {
      expect(
        sql,
        contains(
          'drop function if exists public.list_conversation_summaries()',
        ),
      );
      expect(
        sql,
        contains(
          'last_message_attachment_kind text,\n  last_message_album jsonb,',
        ),
      );
      expect(
        sql,
        contains(
          "'images', count(*) filter (where album_message.type = 'image')",
        ),
      );
      expect(sql, contains("'videos'"));
      expect(sql, contains("'files'"));
      expect(sql, contains('when album.total >= 2 then album.counts'));
      // Same sender, same album, not deleted.
      expect(sql, contains('album_message.sender_id = last_message.sender_id'));
      expect(sql, contains('album_message.recalled_at is null'));
      expect(sql, contains('webhook_name'));
      expect(sql, contains('can_send_messages boolean'));
      expect(sql, contains('slowmode_seconds integer'));
      expect(
        sql,
        contains(
          'grant execute on function public.list_conversation_summaries() to authenticated',
        ),
      );
    });
  });

  group('202610170004 push', () {
    late String sql;

    setUpAll(() => sql = migration('202610170004'));

    test('one push per album, saying what it holds', () {
      expect(sql, contains('pg_advisory_xact_lock'));
      expect(
        sql,
        contains(
          'join public.push_deliveries delivery on delivery.message_id = sibling.id',
        ),
      );
      expect(sql, contains("'%s photos'"));
      expect(sql, contains("'%s video'"));
      expect(sql, contains("'%s files'"));
      expect(
        sql,
        contains("push_body := 'sent ' || array_to_string(album_parts, ', ')"),
      );
      expect(sql, contains('album_images + album_videos + album_files >= 2'));
    });

    test('is the push recipients version, still service-role only', () {
      expect(sql, contains('user_has_conversation_channel_permission('));
      expect(sql, isNot(contains('conversation_member_can_view')));
      expect(
        sql,
        contains(
          'revoke execute on function public.claim_push_delivery(uuid, uuid) from public, anon, authenticated',
        ),
      );
      expect(
        sql,
        contains(
          'grant execute on function public.claim_push_delivery(uuid, uuid) to service_role',
        ),
      );
    });
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Moments 2.0 (roadmap B2, migrations 202610260600 to 202610260650): schema
/// checks plus the behaviour script (reminders, pins, 3-minute videos,
/// descriptions, comment pictures, the Moment card, deleting an account).
void main() {
  late Map<String, String> sql;

  setUpAll(() {
    String read(String name) =>
        File('supabase/migrations/$name').readAsStringSync();
    sql = {
      'schema': read('202610260600_moments2_schema.sql'),
      'write': read('202610260610_moments2_write.sql'),
      'read': read('202610260620_moments2_read.sql'),
      'push': read('202610260630_moments2_push.sql'),
      'card': read('202610260640_moment_card.sql'),
      'account': read('202610260650_moments2_account.sql'),
    };
  });

  test('hard-codes no user id and keeps to its numbers', () {
    final uuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );
    for (final entry in sql.entries) {
      // The path patterns in the schema are regexes, not ids.
      if (entry.key == 'schema' || entry.key == 'read') {
        continue;
      }
      expect(uuid.hasMatch(entry.value), isFalse, reason: entry.key);
    }
  });

  test('who was reminded and the pins are not readable through the API', () {
    // Nothing in the new migrations widens the column grant of moments_posts.
    for (final entry in sql.entries) {
      expect(
        entry.value,
        isNot(contains('grant select (')),
        reason: '${entry.key} must not grant columns of moments_posts',
      );
    }
    expect(sql['schema'], contains('mentioned_user_ids uuid[]'));
    expect(sql['schema'], contains('cardinality(mentioned_user_ids) <= 30'));
  });

  test('a reminder only reaches friends who can see this very post', () {
    final write = sql['write']!;
    expect(write, contains('public.moments_are_friends(me, a.id)'));
    expect(write, contains('public.moments_post_visible_to(a.id, stored)'));
    expect(write, contains('You can remind at most 30 people'));
    // It is the earlier create_moment with a longer video, not a new rule.
    expect(write, contains('video_duration > 181000'));
    expect(write, contains('video_size > 52428800'));
    expect(write, contains('That video is not one of yours'));
    expect(write, contains('Photo % is not one of yours'));
  });

  test('three pins at most, only the author\'s own', () {
    final write = sql['write']!;
    expect(write, contains('where id = p_id and author_id = me'));
    expect(write, contains(">= 3 then"));
    expect(write, contains("errcode = '54000'"));
    expect(write, contains('pg_advisory_xact_lock'));
  });

  test('the feed keeps every rule and adds the new fields', () {
    final read = sql['read']!;
    expect(read, contains('public.moments_post_visible_to(me, p)'));
    expect(read, contains('public.moments_interaction_visible('));
    expect(read, contains('fp.hide_theirs'));
    expect(read, contains("'image', c.image"));
    expect(read, contains('page.author_id = me'));
    expect(read, contains('p.pinned_at is not null'));
    expect(read, contains('limit 3'));
  });

  test('a comment picture is read by whoever may see the comment', () {
    final read = sql['read']!;
    expect(read, contains(r"'\.(jpg|png|webp|gif)$'"));
    expect(
      read,
      contains(
        'public.moments_interaction_visible(\n'
        '          auth.uid(), p.author_id, c.author_id, c.reply_to_user_id',
      ),
    );
    final schema = sql['schema']!;
    expect(schema, contains("'image/gif'"));
    expect(
      schema,
      contains('(storage.foldername(name))[1] = auth.uid()::text'),
    );
    expect(schema, contains('That picture is not yours'));
    expect(schema, contains('The picture was not uploaded'));
    expect(schema, isNot(contains('public = true')));
  });

  test('a push is worded in Chinese for a Chinese subscription', () {
    final push = sql['push']!;
    expect(push, contains("s.language = 'zh'"));
    expect(push, contains('提醒你看TA的朋友圈'));
    expect(push, contains("case when s.language = 'zh' then '某人'"));
    expect(push, contains('[图片]'));
    // The rules of the earlier definition stay.
    expect(push, contains("coalesce(ups.presence_status, 'online') <> 'dnd'"));
    expect(push, contains('coalesce(ms.push_enabled, true)'));
    expect(push, contains('public.moments_post_visible_to(c.user_id, p)'));
    expect(push, contains("interval '10 minutes'"));
    expect(
      push,
      isNot(contains('function public.run_later_dispatch')),
      reason: 'the dispatcher is not rewritten here',
    );
  });

  test('the card holds nothing but the post and is read for the reader', () {
    final card = sql['card']!;
    expect(
      card,
      contains(
        "jsonb_build_object('kind', 'moment_card', 'post_id', p_post_id)",
      ),
    );
    expect(card, contains("'[Moment]'"));
    expect(card, contains('public.moments_can_view(p_post_id)'));
    expect(card, contains('public.moments_post_visible_to(me, p)'));
    expect(card, contains("when 'moment_card' then '[朋友圈]'"));
    // The other cards keep their Chinese.
    for (final kind in [
      'live_location',
      'chat_history',
      'contact_card',
      'note',
      'list',
    ]) {
      expect(card, contains("'$kind'"), reason: kind);
    }
  });

  test('deleting an account erases the new data, and exports cover it', () {
    final account = sql['account']!;
    expect(account, contains('after update of deleted_at on public.profiles'));
    expect(account, contains('array_remove(p.mentioned_user_ids, new.id)'));
    expect(account, contains('delete from public.moments_posts'));
    expect(account, contains('export_my_moments_more'));
    expect(
      account,
      contains(
        'revoke execute on function public.export_my_moments_more(uuid) from authenticated',
      ),
    );
  });

  behaviourTest(
    'moments 2.0: reminders, pins, descriptions, comment pictures, the card',
    'test/supabase/moments2_behaviour.sql',
  );
}

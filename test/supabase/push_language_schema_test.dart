import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for push text in the recipient's language.
void main() {
  late String sql;

  setUpAll(() {
    sql = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere(
          (file) => file.uri.pathSegments.last.startsWith(
            '202610170005_push_language',
          ),
        )
        .readAsStringSync();
  });

  test('subscriptions keep a language, English or Chinese', () {
    expect(
      sql,
      contains(
        'add column if not exists language text not null default \'en\'',
      ),
    );
    expect(sql, contains("check (language in ('en', 'zh'))"));
  });

  test('registering takes the language and replaces the old signature', () {
    expect(
      sql,
      contains(
        'drop function if exists public.register_push_subscription(text, text, text, text);',
      ),
    );
    expect(sql, contains("target_language text default 'en'"));
    expect(
      sql,
      contains(
        'grant execute on function public.register_push_subscription(text, text, text, text, text) to authenticated;',
      ),
    );
  });

  test('claim_push_delivery stays service-role only and speaks both', () {
    expect(
      sql,
      contains(
        'grant execute on function public.claim_push_delivery(uuid, uuid) to service_role;',
      ),
    );
    for (final text in ['[图片]', '发来 ', '发起了通话', '[语音消息]']) {
      expect(sql, contains(text));
    }
    expect(
      sql,
      contains("case when s.language = 'zh' then title_zh else title_en end"),
    );
  });

  test('keeps the recipient rules of the newest definition', () {
    final newest = File(
      'supabase/migrations/202610170004_album_push.sql',
    ).readAsStringSync();
    for (final rule in [
      "coalesce(ups.presence_status, 'online') <> 'dnd'",
      'public.are_users_blocked(message.sender_id, cm.user_id)',
      "'view_channel'",
      "ns.level = 'mentions'",
      'push-album:',
    ]) {
      expect(newest, contains(rule));
      expect(sql, contains(rule));
    }
  });
}

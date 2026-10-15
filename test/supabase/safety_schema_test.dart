import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for moderation and safety (AutoMod, onboarding).
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

  /// The newest definition of [name] across all migrations.
  String functionBody(String sql, String name) {
    final matches = RegExp(
      'create or replace function public\\.$name\\s*\\([\\s\\S]*?\\n\\\$\\\$;',
    ).allMatches(sql);
    expect(matches, isNotEmpty, reason: 'Missing function $name');
    return matches.last.group(0)!;
  }

  group('AutoMod', () {
    test('adds the manage_circle permission to every mask', () {
      final sql = allMigrationSql();
      expect(
        functionBody(sql, 'circle_permission_bit'),
        contains("when 'manage_circle' then 1048576::bigint"),
      );
      expect(
        functionBody(sql, 'circle_all_permissions'),
        contains('select 2097151::bigint;'),
      );
      expect(
        migration('202610160020'),
        contains('permissions >= 0 and permissions <= 2097151'),
      );
    });

    test('rules are read by managers and written only through RPCs', () {
      final sql = migration('202610160020');
      expect(
        sql,
        contains('create table if not exists public.circle_automod_rules'),
      );
      expect(sql, contains("kind in ('keyword', 'mention_spam', 'spam')"));
      expect(
        sql,
        contains(
          'revoke insert, update, delete, truncate on public.circle_automod_rules from anon, authenticated;',
        ),
      );
      expect(
        sql,
        contains(
          "using (public.current_user_has_circle_permission(circle_id, 'manage_circle'))",
        ),
      );
      expect(
        sql,
        contains(
          'revoke all on public.circle_automod_notices from anon, authenticated;',
        ),
      );

      final save = functionBody(sql, 'save_circle_automod_rule');
      expect(save, contains("'manage_circle'"));
      expect(save, contains('when invalid_regular_expression then'));
      expect(save, contains('char_length(pattern) > 260'));
      expect(save, contains("'automod_rule_create'"));
      expect(save, contains("'automod_rule_update'"));
      expect(
        functionBody(sql, 'delete_circle_automod_rule'),
        contains("'automod_rule_delete'"),
      );
    });

    test('keywords match whole words unless they use wildcards', () {
      final pattern = functionBody(
        migration('202610160020'),
        'circle_automod_keyword_pattern',
      );
      expect(pattern, contains("'(^|[^[:alnum:]_])'"));
      expect(pattern, contains("'([^[:alnum:]_]|\$)'"));
      expect(pattern, contains(r"'([.^$*+?()\[\]{}|\\-])', '\\\1', 'g'"));
    });

    test('a trigger after the send check enforces the rules', () {
      final sql = migration('202610160020');
      expect(
        sql,
        contains(
          'create trigger messages_circle_automod\n  before insert on public.messages',
        ),
      );
      // Triggers fire in name order: the permission check comes first.
      expect(
        'messages_check_channel_send'.compareTo('messages_circle_automod'),
        lessThan(0),
      );
      expect(sql, contains('before update of body on public.messages'));

      final enforce = functionBody(sql, 'enforce_circle_automod');
      expect(enforce, contains('new.sender_id is distinct from auth.uid()'));
      expect(enforce, contains('public.circle_automod_soft_block()'));
      expect(enforce, contains('return null;'));
      expect(enforce, contains("detail = 'automod_block'"));

      final verdict = functionBody(sql, 'circle_automod_verdict');
      expect(verdict, contains("'manage_circle'"));
      expect(verdict, contains('rule.exempt_role_ids && sender_role_ids'));
      expect(verdict, contains('channel.id = any(rule.exempt_channel_ids)'));
      expect(verdict, contains('mention_count > rule.mention_limit'));
      expect(verdict, contains('recent_count >= rule.message_limit'));

      final act = functionBody(sql, 'circle_automod_act');
      expect(act, contains("'kind', 'automod_alert'"));
      expect(act, contains("'automod_block'"));
      expect(act, contains("'automod_alert'"));
      expect(act, contains("'automod_timeout'"));
      expect(act, contains('set timed_out_until = greatest('));
      expect(act, contains('delete from public.voice_states vs'));
    });

    test('send_text_message keeps its checks and tolerates a dropped row', () {
      final sql = allMigrationSql();
      final send = functionBody(sql, 'send_text_message');
      expect(send, contains("set_config('wecord.automod_soft', 'on', true)"));
      expect(send, contains('if created_message_id is null then'));
      expect(send, contains('public.resolve_message_mentions('));
      expect(send, contains('public.record_message_mentions('));
      expect(send, contains('is_current_user_blocked_in_conversation'));
    });
  });
}

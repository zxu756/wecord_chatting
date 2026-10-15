import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for the circles items of the 2026-10-16 batch:
/// announcement channels, templates, tags and bots.
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

  String function(String sql, String name) {
    return RegExp(
      'create or replace function public\\.$name\\([\\s\\S]*?\\n\\\$\\\$;',
    ).firstMatch(sql)!.group(0)!;
  }

  group('announcement channels', () {
    final sql = migration('202610160027');

    test('the kind check adds announcement and keeps stage', () {
      expect(
        sql,
        contains(
          "check (kind in ('text', 'voice', 'forum', 'stage', 'announcement'))",
        ),
      );
    });

    test('clients cannot forge copies or publish marks', () {
      final guard = function(sql, 'messages_guard_server_fields');
      expect(guard, isNot(contains('security definer')));
      expect(guard, contains("current_user in ('authenticated', 'anon')"));
      expect(guard, contains('new.crosspost is not null'));
      expect(guard, contains('new.published_at is not null'));
      expect(sql, contains('before insert on public.messages'));
      expect(
        sql,
        contains('revoke all on public.channel_follows from authenticated'),
      );
    });

    test('following needs to see the source and manage the target', () {
      final follow = function(sql, 'follow_announcement_channel');
      expect(
        follow,
        contains(
          "public.current_user_has_channel_permission(source.id, 'view_channel')",
        ),
      );
      expect(
        follow,
        contains(
          "public.current_user_has_channel_permission(target.id, 'manage_webhooks')",
        ),
      );
      expect(follow, contains("source.kind <> 'announcement'"));
      final unfollow = function(sql, 'unfollow_announcement_channel');
      expect(unfollow, contains("'manage_webhooks'"));
    });

    test('publishing is for the author or message managers', () {
      final publish = function(sql, 'publish_message');
      expect(publish, contains("'manage_messages'"));
      expect(publish, contains('message.sender_id = auth.uid()'));
      expect(publish, contains("'send_messages'"));
      expect(publish, contains("channel.kind <> 'announcement'"));
      expect(publish, contains("errcode = 'PB429'"));
      // Copies are sent as the follow's creator only while they may post.
      expect(
        publish,
        contains(
          "public.circle_channel_has_permission(target.id, follow.created_by, 'send_messages')",
        ),
      );
      expect(publish, contains('webhook_name'));
    });

    test('edits and deletions reach the copies', () {
      expect(
        sql,
        contains('after update of body, recalled_at on public.messages'),
      );
      expect(sql, contains('when (new.published_at is not null)'));
    });
  });
  group('circle templates', () {
    final sql = migration('202610160028');

    test('templates are private to their RPCs and one per circle', () {
      expect(
        sql,
        contains('revoke all on public.circle_templates from authenticated'),
      );
      expect(
        sql,
        contains(
          'constraint circle_templates_circle_unique unique (circle_id)',
        ),
      );
      expect(sql, contains("check (code ~ '^[a-z0-9]{10}\$')"));
    });

    test('managing a template needs manage_circle', () {
      for (final name in [
        'create_circle_template',
        'get_circle_template',
        'circle_template_for_management',
      ]) {
        expect(function(sql, name), contains("'manage_circle'"), reason: name);
      }
      expect(
        function(sql, 'sync_circle_template'),
        contains('circle_template_for_management'),
      );
      expect(
        function(sql, 'delete_circle_template'),
        contains('circle_template_for_management'),
      );
    });

    test('the snapshot leaves out messages, members and member overwrites', () {
      final snapshot = function(sql, 'circle_template_snapshot');
      expect(snapshot, isNot(contains('public.messages')));
      expect(snapshot, isNot(contains('circle_members')));
      expect(snapshot, contains('o.role_id is not null'));
    });

    test('building a circle goes through create_circle and masks bits', () {
      final build = function(sql, 'create_circle_from_template');
      expect(build, contains('public.create_circle(circle_name'));
      expect(build, contains('& public.circle_all_permissions()'));
      expect(build, contains('overwrite_bits'));
      expect(build, contains('usage_count = t.usage_count + 1'));
    });
  });
}

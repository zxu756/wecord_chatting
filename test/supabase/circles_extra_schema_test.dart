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
  group('circle tags', () {
    final sql = migration('202610160029');

    test('tags are short and badges come from a fixed set', () {
      expect(sql, contains('char_length(tag) between 2 and 4'));
      expect(sql, contains("'leaf', 'star', 'flame', 'heart', 'bolt',"));
      expect(sql, contains('check ((tag is null) = (tag_badge is null))'));
    });

    test('only members show a tag, and leaving clears it', () {
      final check = function(sql, 'check_display_circle_tag');
      expect(check, contains('cm.user_id = new.id'));
      expect(check, contains('c.tag is not null'));
      expect(
        sql,
        contains(
          'before insert or update of display_circle_tag_id on public.profiles',
        ),
      );
      expect(sql, contains('after delete on public.circle_members'));
      final clear = function(sql, 'clear_display_circle_tag_on_leave');
      expect(clear, contains('p.display_circle_tag_id = old.circle_id'));
    });

    test(
      'setting the tag needs manage_circle and turning it off clears choices',
      () {
        final set = function(sql, 'set_circle_tag');
        expect(set, contains("'manage_circle'"));
        expect(set, contains('set display_circle_tag_id = null'));
        expect(set, contains("'circle_tag_update'"));
      },
    );

    test('badge lookups are bounded', () {
      final badges = function(sql, 'list_profile_badges');
      expect(badges, contains('> 200'));
      expect(badges, contains('c.tag is not null'));
    });
  });
  group('bot API', () {
    final sql = migration('202610160030');

    test('only hashes of tokens are kept and clients cannot read bots', () {
      expect(sql, contains("token_hash ~ '^[0-9a-f]{64}\$'"));
      expect(
        sql,
        contains('revoke all on public.circle_bots from anon, authenticated'),
      );
      expect(
        function(sql, 'bot_from_token'),
        contains('public.webhook_token_hash(bot_token)'),
      );
    });

    test('clients cannot mark bots or forge interactions', () {
      final guard = function(sql, 'profiles_guard_is_bot');
      expect(guard, isNot(contains('security definer')));
      expect(guard, contains("current_user in ('authenticated', 'anon')"));
      final fields = function(sql, 'messages_guard_server_fields');
      expect(fields, contains('new.interaction is not null'));
      expect(fields, contains('new.crosspost is not null'));
    });

    test('bot accounts cannot sign in', () {
      final create = function(sql, 'create_circle_bot');
      expect(create, contains("'infinity'"));
      expect(create, contains("'manage_circle'"));
      expect(create, contains('public.circle_member_rank'));
    });

    test('bot writes reuse the member functions as the bot', () {
      final act = function(sql, 'act_as_bot');
      expect(act, contains("'request.jwt.claims'"));
      expect(act, contains("'request.jwt.claim.sub'"));
      expect(
        function(sql, 'bot_api_send_message'),
        contains('public.send_text_message('),
      );
      expect(
        function(sql, 'bot_api_add_reaction'),
        contains('public.toggle_message_reaction('),
      );
      expect(function(sql, 'bot_visible_channel'), contains("'view_channel'"));
      expect(function(sql, 'count_bot_write'), contains('> 60'));
    });

    test('only the Edge Function may call the bot API functions', () {
      expect(sql, contains("'bot_api_send_message(text, uuid, text, uuid)'"));
      expect(
        sql,
        contains('grant execute on function public.%s to service_role'),
      );
      expect(
        sql,
        contains(
          'revoke execute on function public.%s from public, anon, authenticated',
        ),
      );
    });

    test('commands need send permission and the bot must answer there', () {
      final invoke = function(sql, 'invoke_bot_command');
      expect(invoke, contains("'send_messages'"));
      expect(
        invoke,
        contains(
          "public.circle_channel_has_permission(channel.id, bot.user_id, 'view_channel')",
        ),
      );
      final respond = function(sql, 'bot_api_respond_interaction');
      expect(respond, contains('pending.responded_at is not null'));
      expect(respond, contains('pending.expires_at <= now()'));
    });
  });
}

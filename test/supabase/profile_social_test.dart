import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the profile and social extras (B4 status bubbles, B5
/// birthdays, A14 mutuals and add sources, J4 support links: migrations
/// 202610230600 to 202610230650), plus the behaviour script that plays them.
void main() {
  late String status;
  late String birthday;
  late String push;
  late String links;
  late String source;
  late String mutuals;

  setUpAll(() {
    String read(String name) =>
        File('supabase/migrations/$name.sql').readAsStringSync();
    status = read('202610230600_status_visibility');
    birthday = read('202610230610_profile_birthday');
    push = read('202610230620_birthday_push');
    links = read('202610230630_support_links');
    source = read('202610230640_friend_source');
    mutuals = read('202610230650_mutuals');
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group(
    'every new function is closed to the signed-out and checks its caller',
    () {
      test('security definer functions pin the search path', () {
        for (final sql in [status, birthday, push, links, source, mutuals]) {
          final functions = RegExp(
            r'create or replace function public\.\w+\([^)]*\)[\s\S]*?\n\$\$;',
          ).allMatches(sql);
          for (final match in functions) {
            final text = match.group(0)!;
            if (text.contains('security definer')) {
              expect(
                text,
                contains('set search_path = public'),
                reason: text.split('\n').first,
              );
            }
          }
        }
      });

      test('the callable RPCs need a signed-in user', () {
        for (final (sql, name) in [
          (status, 'set_status_visibility'),
          (birthday, 'set_my_birthday'),
          (links, 'set_my_links'),
          (links, 'set_circle_support_url'),
          (source, 'set_friend_request_source'),
          (mutuals, 'get_mutuals'),
          (mutuals, 'get_mutual_counts'),
          (mutuals, 'get_profile_extras'),
        ]) {
          final text = body(sql, name);
          expect(text, contains('auth.uid()'), reason: name);
          expect(text, contains("errcode = '42501'"), reason: name);
        }
        expect(
          body(status, 'status_visible_to_caller'),
          contains('if viewer is null then\n    return false'),
        );
        for (final (sql, name) in [
          (status, 'list_friend_statuses(): from public, anon'),
          (birthday, 'list_birthdays_today(date): from public, anon'),
          (mutuals, 'get_mutuals(uuid): from public, anon'),
        ]) {
          final function = name.split(':').first;
          expect(
            sql,
            contains('revoke execute on function public.$function'),
            reason: name,
          );
        }
      });
    },
  );

  group('status bubbles (B4)', () {
    test('custom_status keeps its expiry and adds the visibility rule', () {
      final text = body(status, 'custom_status');
      expect(text, contains('security definer'));
      expect(text, contains('profile_row.status_expires_at <= now()'));
      expect(text, contains('status_visible_to_caller'));
    });

    test('the audience rule covers blocks, friends, stars and self', () {
      final rule = body(status, 'status_visible_to_caller');
      expect(rule, contains('b.blocker_id = owner_id'));
      expect(rule, contains('b.blocked_id = viewer'));
      expect(rule, contains("visibility = 'self'"));
      expect(rule, contains('public.friendships'));
      expect(rule, contains('public.friend_stars'));
      expect(rule, contains('s.owner_id = status_visible_to_caller.owner_id'));
      expect(
        status,
        contains(
          'revoke execute on function public.status_visible_to_caller(uuid, text)\n'
          '  from public, anon, authenticated',
        ),
      );
    });

    test('the raw columns are closed, so nobody can walk around the rule', () {
      expect(
        status,
        contains(
          'revoke select (status_emoji, status_text, status_expires_at)\n'
          '  on public.profiles from authenticated',
        ),
      );
    });

    test('no function that returns profiles is rewritten', () {
      for (final name in [
        'get_profile_summary',
        'get_circle_detail',
        'list_friends_with_aliases',
        'set_custom_status',
      ]) {
        expect(status, isNot(contains('function public.$name(')), reason: name);
      }
    });

    test('the bubble list leaves out bots and deleted accounts', () {
      final list = body(status, 'list_friend_statuses');
      expect(list, contains('not p.is_bot'));
      expect(list, contains('p.deleted_at is null'));
      expect(list, contains('public.custom_status(p)'));
    });
  });

  group('birthdays (B5)', () {
    test('only a month and a day are stored, closed to clients', () {
      expect(birthday, isNot(contains('birthday_year')));
      expect(birthday, contains('add column if not exists birthday_month'));
      expect(
        birthday,
        isNot(contains('grant select (birthday')),
        reason: 'read through the RPCs that apply the rule',
      );
      expect(
        birthday,
        contains("birthday_visibility text not null default 'friends'"),
      );
      expect(birthday, contains("birthday_visibility in ('friends', 'self')"));
    });

    test('a birthday is shown to friends who may see it, not blocked', () {
      final rule = body(birthday, 'can_view_birthday');
      expect(rule, contains('are_users_blocked'));
      expect(rule, contains("choice is distinct from 'friends'"));
      expect(rule, contains('public.friendships'));
    });

    test('a deleted account keeps no birthday', () {
      expect(
        birthday,
        contains('before update of deleted_at on public.profiles'),
      );
      expect(
        body(birthday, 'clear_deleted_profile_birthday'),
        contains('birthday_month := null'),
      );
    });

    test('the reminder rides on the existing dispatcher, no new cron job', () {
      expect(push, isNot(contains('cron.schedule')));
      final dispatcher = body(push, 'run_later_dispatch');
      expect(dispatcher, contains('public.birthday_pushes_waiting()'));
      // Everything 202610190021 woke the function for is still there.
      for (final part in [
        'dispatch_due_scheduled_messages',
        'chat_event_due_reminders',
        'public.scheduled_messages',
        'public.message_reminders',
        'public.chat_event_reminders',
        'public.task_items',
        'public.recalled_message_media',
        'public.moments_notifications',
        'net.http_post',
        'wecord_dispatch_secret',
      ]) {
        expect(dispatcher, contains(part), reason: part);
      }
    });

    test(
      '9 o\'clock in the recipient\'s own time, once a year, in their language',
      () {
        final due = body(push, 'birthday_due_reminders');
        expect(due, contains('between 9 and 20'));
        expect(due, contains('s.time_zone'));
        expect(due, contains('birthday_reminder_log'));
        expect(due, contains("'dnd'"));
        expect(due, contains('b.blocker_id'));
        expect(due, contains("p.birthday_visibility = 'friends'"));
        expect(due, contains('me.birthday_reminders'));
        final claim = body(push, 'claim_birthday_pushes');
        expect(claim, contains("s.language = 'zh'"));
        expect(claim, contains("replace(replace("));
        expect(claim, contains('on conflict do nothing'));
        expect(
          push,
          contains(
            'revoke execute on function public.claim_birthday_pushes()\n'
            '  from public, anon, authenticated;\n'
            'grant execute on function public.claim_birthday_pushes() to service_role;',
          ),
        );
      },
    );
  });

  group('add sources and mutuals (A14)', () {
    test('send_friend_request and accept_friend_request are not rewritten', () {
      for (final name in [
        'send_friend_request',
        'accept_friend_request',
        'get_profile_summary',
      ]) {
        expect(source, isNot(contains('function public.$name(')), reason: name);
        expect(
          mutuals,
          isNot(contains('function public.$name(')),
          reason: name,
        );
      }
      expect(source, contains('before insert on public.friendships'));
    });

    test('claims that can be checked are checked', () {
      final note = body(source, 'set_friend_request_source');
      expect(note, contains("c.type = 'group'"));
      expect(note, contains('public.circle_members'));
      expect(note, contains("r.status = 'pending'"));
      expect(note, contains('r.requester_id = me'));
    });

    test('mutual names are for friends, numbers for everyone allowed', () {
      final text = body(mutuals, 'get_mutuals');
      expect(text, contains('are_users_blocked'));
      expect(text, contains('can_view_profile_details'));
      expect(text, contains('not is_friend'));
      expect(text, contains('not p.is_bot'));
      expect(text, contains('p.deleted_at is null'));
      expect(text, isNot(contains('.bio')));
      expect(text, isNot(contains('bio,')));
    });

    test('a request card gets numbers only, at most 50 people', () {
      final text = body(mutuals, 'get_mutual_counts');
      expect(text, contains('> 50'));
      expect(text, isNot(contains("'display_name'")));
    });
  });

  group('support links (J4)', () {
    test('the allow list is checked on the server', () {
      final text = body(links, 'normalize_support_url');
      expect(text, contains("'^https://"));
      for (final domain in [
        'afdian.net',
        'ko-fi.com',
        'patreon.com',
        'buymeacoffee.com',
      ]) {
        expect(text, contains("'$domain'"), reason: domain);
      }
      expect(text, contains("host like '%.' || domain"));
      expect(text, contains("'github.com'"));
      expect(text, contains('/sponsors/'));
    });

    test('links and the circle page are written through checked RPCs', () {
      expect(links, isNot(contains('grant select (links')));
      final mine = body(links, 'set_my_links');
      expect(mine, contains('normalize_support_url'));
      expect(mine, contains('> 5'));
      final circle = body(links, 'set_circle_support_url');
      expect(circle, contains("'manage_circle'"));
      expect(circle, contains('normalize_support_url'));
      final read = body(links, 'get_circle_support_url');
      expect(read, contains('is_current_user_circle_member'));
    });

    test('get_my_profile_extras is the one definition with the links', () {
      expect(links, contains("'links', p.links"));
      expect(
        body(birthday, 'get_my_profile_extras'),
        isNot(contains("'links'")),
      );
    });
  });

  behaviourTest(
    'profile social: status audience, birthdays and their 9 o\'clock reminder, '
        'support links, add sources, mutuals',
    'test/supabase/profile_social_behaviour.sql',
  );
}

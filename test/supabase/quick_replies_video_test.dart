import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Quick replies, the away auto-reply and round video messages (A8 and A13:
/// migrations 202610280300 to 202610280330): what the SQL says, as text, plus
/// the behaviour script that plays people through it against the local
/// database.
void main() {
  final names = [
    '202610280300_quick_replies.sql',
    '202610280310_away_auto_reply.sql',
    '202610280320_video_notes.sql',
    '202610280330_quick_replies_account.sql',
  ];
  late Map<String, String> sql;
  late String all;

  setUpAll(() {
    sql = {
      for (final name in names)
        name: File('supabase/migrations/$name').readAsStringSync(),
    };
    all = sql.values.join('\n');
  });

  group('numbering and what is left alone', () {
    test('the migrations are in this package\'s range, ten apart', () {
      final numbers = [
        for (final name in names) int.parse(name.substring(0, 12)),
      ];
      for (var i = 0; i < numbers.length; i++) {
        expect(numbers[i], 202610280300 + i * 10);
      }
      expect(numbers.last, lessThan(202610280400));
    });

    test('the every-minute dispatcher and the push claim are not redefined', () {
      expect(all, isNot(contains('function public.run_later_dispatch')));
      expect(all, isNot(contains('function public.claim_push_delivery')));
      expect(all, isNot(contains('function public.send_text_message')));
      expect(
        all,
        isNot(contains('function public.messages_guard_server_fields')),
      );
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('the job has a cron of its own, chosen by pg_extension', () {
      final away = sql['202610280310_away_auto_reply.sql']!;
      expect(away, contains("'wecord-away-reply-push'"));
      expect(away, contains("from pg_extension where extname = 'pg_cron'"));
      expect(away, contains('public.wake_scheduled_dispatch()'));
    });
  });

  group('the auto-reply rules', () {
    late String trigger;

    setUpAll(() {
      final source = sql['202610280310_away_auto_reply.sql']!;
      final start = source.indexOf(
        'create or replace function public.messages_send_away_reply()',
      );
      expect(start, isNonNegative);
      trigger = source.substring(start, source.indexOf('\n\$\$;', start));
    });

    test('it never answers an auto-reply, a system notice or a webhook', () {
      expect(trigger, contains('new.auto_reply'));
      expect(trigger, contains("new.type = 'system'"));
      expect(trigger, contains('new.webhook_id is not null'));
      expect(trigger, contains('new.review_state is not null'));
    });

    test('only in a direct chat of two, with a friend who is not blocked', () {
      expect(trigger, contains("conversation_kind is distinct from 'direct'"));
      expect(trigger, contains('cardinality(member_ids), 0) <> 2'));
      expect(trigger, contains('public.friendships'));
      expect(trigger, contains('public.are_users_blocked'));
      expect(trigger, contains('is_bot'));
      expect(trigger, contains('deleted_at'));
    });

    test('once a day for each person and a ceiling for the away person', () {
      expect(trigger, contains("interval '24 hours'"));
      expect(trigger, contains('>= 300'));
      expect(trigger, contains('pg_advisory_xact_lock'));
    });

    test('the answer is never silent', () {
      expect(trigger, contains("set_config('wecord.send_silent', 'off'"));
    });
  });

  group('round video messages', () {
    test('the limits are 60 seconds and 30 MB', () {
      final source = sql['202610280320_video_notes.sql']!;
      expect(source, contains('61000'));
      expect(source, contains('31457280'));
      expect(source, contains("attachment->>'kind' is distinct from 'video'"));
    });
  });

  group('the account', () {
    test('the export holds only the person\'s own', () {
      final source = sql['202610280330_quick_replies_account.sql']!;
      expect(source, contains('q.user_id = target_user_id'));
      expect(source, contains('s.user_id = target_user_id'));
      expect(source, contains('on public.profiles'));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/quick_replies_video_behaviour.sql',
  );
}

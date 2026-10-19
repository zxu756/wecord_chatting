import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for urgent messages and announcements that need a
/// confirmation (A7: migrations 202610240400 to 202610240460), plus the
/// behaviour script that plays them.
void main() {
  late String schema;
  late String rpcs;
  late String announcements;
  late String pushes;
  late String dispatch;

  setUpAll(() {
    String read(String name) =>
        File('supabase/migrations/$name').readAsStringSync();
    schema = read('202610240400_urgent_schema.sql');
    rpcs = read('202610240410_urgent_rpcs.sql');
    announcements = read('202610240420_announcement_ack_rpcs.sql');
    pushes = read('202610240430_urgent_pushes.sql');
    dispatch = read('202610240460_dispatch_urgent.sql');
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('tables', () {
    test('writes are closed to clients, reads are their own rows', () {
      for (final table in [
        'message_urgents',
        'message_urgent_targets',
        'urgent_sender_mutes',
      ]) {
        expect(
          schema,
          contains('alter table public.$table enable row level security'),
        );
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated',
          ),
        );
        expect(
          schema,
          contains('grant select on public.$table to authenticated'),
        );
      }
      expect(schema, contains('using (user_id = auth.uid())'));
      expect(schema, contains('using (sender_id = auth.uid())'));
      for (final table in ['announcement_acks', 'announcement_ack_reminders']) {
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated',
          ),
        );
        expect(schema, isNot(contains('grant select on public.$table')));
      }
    });

    test(
      'a person is made urgent once per message, and rows follow the message',
      () {
        expect(schema, contains('unique (message_id, user_id)'));
        expect(
          schema,
          contains('references public.messages(id) on delete cascade'),
        );
        expect(schema, contains('add table public.message_urgent_targets'));
      },
    );

    test(
      'a new announcement or switching the request off clears confirmations',
      () {
        expect(
          schema,
          contains('after update of announcement, announcement_requires_ack'),
        );
        expect(schema, contains('delete from public.announcement_acks'));
      },
    );
  });

  group('send_message_urgent', () {
    test('is for the sender of the message, with a limit of 5 a day', () {
      final send = body(rpcs, 'send_message_urgent');
      expect(send, contains('security definer'));
      expect(send, contains('set search_path = public'));
      expect(send, contains('message.sender_id is distinct from me'));
      expect(send, contains("interval '24 hours'"));
      expect(send, contains(">= 5"));
      expect(send, contains("errcode = '53400'"));
      expect(send, contains('can_current_user_send_in_conversation'));
      expect(send, contains('> 10'));
    });

    test('keeps the rules of the app', () {
      final send = body(rpcs, 'send_message_urgent');
      expect(send, contains('are_users_blocked'));
      expect(send, contains('urgent_sender_mutes'));
      expect(send, contains('message.recalled_at is not null'));
      expect(send, contains('message.review_state is not null'));
      expect(send, contains('message.expires_at'));
      expect(send, contains('note_to_self_conversations'));
      expect(send, contains('not p.is_bot'));
      expect(send, contains('conversation_in_suspended_circle'));
      expect(send, contains("'view_channel'"));
    });

    test('is called by signed-in people only', () {
      expect(
        rpcs,
        contains(
          'revoke execute on function public.send_message_urgent(uuid, uuid[]) from public, anon',
        ),
      );
      expect(
        rpcs,
        contains(
          'grant execute on function public.send_message_urgent(uuid, uuid[]) to authenticated',
        ),
      );
    });
  });

  group('announcements to confirm', () {
    test('only the owner and admins ask, and only in groups', () {
      for (final name in [
        'set_announcement_requires_ack',
        'remind_announcement_unacked',
        'list_announcement_ack_members',
      ]) {
        final fn = body(announcements, name);
        expect(fn, contains("('owner', 'admin')"), reason: name);
        expect(fn, contains("c.type = 'group'"), reason: name);
        expect(fn, contains('security definer'), reason: name);
        expect(fn, contains('set search_path = public'), reason: name);
      }
    });

    test('update_group_profile is not rewritten', () {
      expect(
        announcements,
        isNot(contains('function public.update_group_profile(')),
      );
      expect(schema, isNot(contains('function public.update_group_profile(')));
    });

    test('reminders are limited to one in six hours', () {
      final remind = body(announcements, 'remind_announcement_unacked');
      expect(remind, contains("interval '6 hours'"));
      expect(remind, contains("errcode = '53400'"));
    });
  });

  group('pushes', () {
    test('are private to the server and written in both languages', () {
      for (final name in [
        'claim_urgent_pushes()',
        'claim_announcement_ack_pushes()',
      ]) {
        expect(
          pushes,
          contains(
            'revoke execute on function public.$name\n  from public, anon, authenticated',
          ),
        );
        expect(pushes, contains('grant execute on function public.$name'));
      }
      final claim = body(pushes, 'claim_urgent_pushes');
      expect(claim, contains("s.language = 'zh'"));
      expect(claim, contains('加急了一条消息'));
    });

    test(
      'urgent pushes break through mutes and Do Not Disturb but not blocks',
      () {
        final claim = body(pushes, 'claim_urgent_pushes');
        expect(claim, isNot(contains('muted_until')));
        expect(claim, isNot(contains('presence_status')));
        expect(claim, contains('are_users_blocked'));
        expect(claim, contains('urgent_sender_mutes'));
        expect(claim, contains('m.recalled_at is null'));
        expect(claim, contains('m.review_state is null'));
      },
    );

    test('the second push is once, ten minutes later', () {
      final claim = body(pushes, 'claim_urgent_pushes');
      expect(
        claim,
        contains("push_claimed_at <= now() - interval '10 minutes'"),
      );
      expect(claim, contains('repush_claimed_at is null'));
    });

    test('claim_push_delivery is not touched', () {
      expect(pushes, isNot(contains('function public.claim_push_delivery(')));
    });
  });

  group('the dispatcher', () {
    test('is the birthday version with the urgent reasons added', () {
      expect(dispatch, contains('public.birthday_pushes_waiting()'));
      expect(dispatch, contains('message_urgent_targets'));
      expect(dispatch, contains('announcement_ack_reminders'));
      expect(dispatch, contains('public.moments_notifications'));
      expect(dispatch, contains('public.recalled_message_media'));
      expect(dispatch, contains('public.chat_event_due_reminders()'));
    });

    test('it is rewritten once for A7 and D4 together', () {
      final migrations = Directory('supabase/migrations')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.contains('2026102404'))
          .where(
            (f) => f.readAsStringSync().contains(
              'create or replace function public.run_later_dispatch(',
            ),
          )
          .toList();
      expect(migrations, hasLength(1));
    });
  });

  behaviourTest(
    'urgent messages and confirmations: limits, rules, pushes, counts',
    'test/supabase/urgent_behaviour.sql',
  );
}

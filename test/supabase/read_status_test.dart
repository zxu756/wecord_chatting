import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the group read list, the read receipts switch and
/// "remind unread", plus the behaviour script.
void main() {
  late String setting;
  late String status;
  late String remind;

  setUpAll(() {
    setting = File(
      'supabase/migrations/202610220300_read_receipts_setting.sql',
    ).readAsStringSync();
    status = File(
      'supabase/migrations/202610220310_message_read_status.sql',
    ).readAsStringSync();
    remind = File(
      'supabase/migrations/202610220320_remind_unread.sql',
    ).readAsStringSync();
  });

  test('the switch defaults to on and has its own setter', () {
    expect(
      setting,
      contains(
        'add column if not exists send_read_receipts boolean not null default true',
      ),
    );
    expect(setting, contains('function public.set_send_read_receipts('));
    // The existing privacy setter is not rewritten.
    expect(setting, isNot(contains('function public.set_privacy_permissions')));
  });

  test('read positions are served by a new function, not a rewrite', () {
    expect(setting, contains('function public.list_read_markers('));
    for (final rewritten in [
      'mark_conversation_read',
      'list_conversation_summaries',
      'get_or_create_direct_conversation',
    ]) {
      expect(setting, isNot(contains('function public.$rewritten(')));
      expect(status, isNot(contains('function public.$rewritten(')));
      expect(remind, isNot(contains('function public.$rewritten(')));
    }
    expect(setting, contains('public.are_users_blocked('));
    expect(setting, contains('note_to_self_conversations'));
    expect(setting, contains('member_total <= 200'));
  });

  test('the read list is sender only, small groups only, blocking aware', () {
    expect(status, contains('message.sender_id is distinct from caller_id'));
    expect(status, contains("conversation_type is distinct from 'group'"));
    expect(status, contains('member_total > 200'));
    expect(status, contains('note_to_self_conversations'));
    expect(status, contains('public.are_users_blocked(caller_id'));
    expect(status, contains('read_message.created_at >= message.created_at'));
    expect(status, contains("raise exception 'read_receipts_off'"));
    // The internal rules function is not callable by clients.
    expect(
      status,
      contains(
        'revoke execute on function public.message_read_status_rows(uuid, uuid)',
      ),
    );
  });

  test('remind unread is once per message and leaves unknown people alone', () {
    expect(remind, contains('message_id uuid primary key references'));
    expect(remind, contains("where r.status = 'unread'"));
    expect(remind, contains("raise exception 'already_reminded'"));
    expect(remind, contains("raise exception 'nobody_to_remind'"));
    expect(remind, contains('reminded_today >= 30'));
    expect(
      remind,
      contains('revoke all on public.read_reminder_notices from anon'),
    );
    // The push claim is for the service role only, and in both languages.
    expect(
      remind,
      contains(
        'revoke execute on function public.claim_read_reminder_pushes(uuid, uuid)',
      ),
    );
    expect(remind, contains("s.language = 'zh'"));
    expect(remind, contains("'<t:'"));
    // The existing claim functions are not rewritten.
    expect(remind, isNot(contains('function public.claim_push_delivery')));
  });

  behaviourTest(
    'sender only, the 200 cap, receipts both ways, blocking, remind once, '
        'the push and quiet hours',
    'test/supabase/read_status_behaviour.sql',
  );
}

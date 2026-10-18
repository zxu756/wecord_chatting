import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for privacy permissions 2.0 and new-login alerts
/// (migrations 202610210410, 202610210420 and 202610210430), plus the
/// behaviour script.
void main() {
  late String permissions;
  late String invitations;
  late String alerts;

  setUpAll(() {
    permissions = File(
      'supabase/migrations/202610210410_privacy_permissions.sql',
    ).readAsStringSync();
    invitations = File(
      'supabase/migrations/202610210420_group_invitations.sql',
    ).readAsStringSync();
    alerts = File(
      'supabase/migrations/202610210430_login_alerts.sql',
    ).readAsStringSync();
  });

  test('the settings are checked values with open defaults', () {
    expect(
      permissions,
      contains("friend_request_from text not null default 'everyone'"),
    );
    expect(
      permissions,
      contains('discoverable_by_username boolean not null default true'),
    );
    expect(
      permissions,
      contains('discoverable_by_qr boolean not null default true'),
    );
    expect(
      permissions,
      contains("allow_calls_from text not null default 'friends'"),
    );
    expect(
      permissions,
      contains("group_invite_from text not null default 'all_friends'"),
    );
    expect(
      permissions,
      contains("'everyone', 'friends_of_friends', 'circle_members', 'nobody'"),
    );
  });

  test('friend requests are held to the setting by a trigger', () {
    expect(permissions, contains('before insert on public.friend_requests'));
    expect(permissions, contains('users_share_a_friend'));
    expect(permissions, contains('users_share_a_circle'));
  });

  test('search, QR and calls apply their setting on the server', () {
    expect(permissions, contains('function public.search_users_by_username'));
    expect(permissions, contains('coalesce(s.discoverable_by_username, true)'));
    expect(permissions, contains('coalesce(s.discoverable_by_qr, true)'));
    expect(permissions, contains('function public.resolve_user_qr_code'));
    expect(
      permissions,
      contains('function public.can_current_user_call_in_conversation'),
    );
    expect(permissions, contains('user_accepts_calls_from'));
  });

  test('the rewritten functions keep the rules of their latest versions', () {
    // resolve_user_qr_code (202610180030): deleted accounts and blocks.
    final qr = permissions.substring(
      permissions.indexOf('function public.resolve_user_qr_code'),
    );
    expect(qr, contains('p.deleted_at is null'));
    expect(qr, contains('are_users_blocked'));
    // can_current_user_call_in_conversation (202610140006): membership and
    // blocks, direct and group chats only.
    final calls = permissions.substring(
      permissions.indexOf(
        'function public.can_current_user_call_in_conversation',
      ),
    );
    expect(calls, contains("c.type in ('direct', 'group')"));
    expect(calls, contains('is_current_user_conversation_member'));
    expect(calls, contains('is_current_user_blocked_in_conversation'));
  });

  test(
    'a group invitation lasts seven days and is closed to direct writes',
    () {
      expect(invitations, contains("default now() + interval '7 days'"));
      expect(
        invitations,
        contains(
          'revoke all on public.group_invitations from anon, authenticated',
        ),
      );
      expect(
        invitations,
        contains('grant select on public.group_invitations to authenticated'),
      );
      expect(invitations, contains('i.expires_at > now()'));
      expect(invitations, contains('invitation.expires_at <= now()'));
    },
  );

  test('both ways of putting friends in a group apply the setting', () {
    final add = invitations.substring(
      invitations.indexOf('function public.add_group_members'),
      invitations.indexOf('function public.create_group_conversation'),
    );
    expect(add, contains("cm.role in ('owner', 'admin')"));
    expect(add, contains('Group members must be accepted friends'));
    expect(add, contains('can_add_to_group_directly'));
    expect(add, contains('invite_to_group'));
    final create = invitations.substring(
      invitations.indexOf('function public.create_group_conversation'),
    );
    expect(
      create,
      contains('A group conversation requires at least two members'),
    );
    expect(create, contains('Contract guard: role, \'owner\''));
    expect(create, contains('can_add_to_group_directly'));
  });

  test('voluntary paths do not go through the invitation check', () {
    // join_group_by_qr and contact cards are not rewritten here.
    expect(invitations, isNot(contains('function public.join_group_by_qr')));
    expect(permissions, isNot(contains('get_or_create_direct_conversation')));
  });

  test('a login alert comes from a new device row, never a refresh', () {
    expect(alerts, contains('after insert on public.user_devices'));
    expect(alerts, contains('d.session_id <> new.session_id'));
    expect(alerts, isNot(contains('after update on public.user_devices')));
  });

  test('alerts hold no address or location', () {
    final table = alerts.substring(
      alerts.indexOf('create table if not exists public.login_alerts'),
      alerts.indexOf('create index if not exists login_alerts_user_idx'),
    );
    expect(table, isNot(matches(RegExp(r'\bip\b'))));
    expect(table, isNot(contains('location')));
    expect(table, isNot(contains('user_agent')));
  });

  test('the push claim is for the service role and in two languages', () {
    expect(
      alerts,
      contains(
        'revoke execute on function public.claim_security_alert_pushes() from public, anon, authenticated;',
      ),
    );
    expect(
      alerts,
      contains(
        'grant execute on function public.claim_security_alert_pushes() to service_role;',
      ),
    );
    expect(alerts, contains("s.language = 'zh'"));
    expect(alerts, contains("<t:"));
    expect(alerts, contains('s.created_at <= c.created_at'));
  });

  test('scheduled-dispatch claims the alert pushes', () {
    final function = File(
      'supabase/functions/scheduled-dispatch/index.ts',
    ).readAsStringSync();
    expect(function, contains('claim_security_alert_pushes'));
    expect(function, contains('securityTarget'));
  });

  behaviourTest(
    'permissions, invitations and login alerts work against a database',
    'test/supabase/privacy_permissions_behaviour.sql',
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for circle join requests (migrations 202610220600 to
/// 202610220630), plus the behaviour script that walks every join path in
/// every join mode.
void main() {
  late String schema;
  late String paths;
  late String rpcs;
  late String push;

  setUpAll(() {
    schema = File(
      'supabase/migrations/202610220600_join_requests_schema.sql',
    ).readAsStringSync();
    paths = File(
      'supabase/migrations/202610220610_join_requests_paths.sql',
    ).readAsStringSync();
    rpcs = File(
      'supabase/migrations/202610220620_join_request_rpcs.sql',
    ).readAsStringSync();
    push = File(
      'supabase/migrations/202610220630_join_request_push.sql',
    ).readAsStringSync();
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('the data', () {
    test('a circle has three join modes, open by default', () {
      expect(
        schema,
        contains(
          "add column if not exists join_mode text not null default 'open'",
        ),
      );
      expect(
        schema,
        contains("check (join_mode in ('open', 'apply', 'invite_only'))"),
      );
    });

    test('at most five questions, text or single choice', () {
      expect(schema, contains('check (position between 0 and 4)'));
      expect(schema, contains("check (kind in ('text', 'choice'))"));
      expect(schema, contains("Up to 5 questions"));
    });

    test('a request is pending, approved or denied, and decided once', () {
      expect(
        schema,
        contains("check (status in ('pending', 'approved', 'denied'))"),
      );
      expect(schema, contains('decided_by uuid references public.profiles'));
      expect(
        schema,
        contains(
          'create unique index if not exists circle_join_requests_one_pending_idx',
        ),
      );
    });

    test('the tables are closed to clients except for reading your own', () {
      for (final table in ['circle_join_questions', 'circle_join_requests']) {
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
      }
      expect(
        schema,
        contains(
          'grant select on public.circle_join_requests to authenticated',
        ),
      );
      expect(schema, isNot(contains('grant insert')));
      expect(schema, isNot(contains('grant update')));
      expect(schema, isNot(contains('grant delete')));
      expect(
        schema,
        contains(
          "public.current_user_has_circle_permission(circle_id, 'kick_members')",
        ),
      );
    });
  });

  group('every join path reads the mode', () {
    test('accept_circle_invite, join_public_circle, invite_circle_members', () {
      expect(
        body(paths, 'accept_circle_invite'),
        contains("circle.join_mode = 'apply'"),
      );
      expect(
        body(paths, 'join_public_circle'),
        contains("circle.join_mode = 'apply'"),
      );
      expect(
        body(paths, 'join_public_circle'),
        contains("circle.join_mode = 'invite_only'"),
      );
      expect(body(paths, 'invite_circle_members'), contains("= 'apply'"));
      for (final name in [
        'accept_circle_invite',
        'join_public_circle',
        'invite_circle_members',
      ]) {
        expect(body(paths, name), contains('security definer'), reason: name);
        expect(body(paths, name), contains('set search_path = public'));
      }
    });

    test('a path that forgot the mode is refused by a trigger', () {
      expect(schema, contains('before insert on public.circle_members'));
      expect(schema, contains("'This circle reviews who joins'"));
      // Named to fire after the ban and the take-down triggers.
      expect(schema, contains('create trigger circle_members_require_review'));
    });

    test('the paths keep the rules of the definitions they come from', () {
      // accept_circle_invite: the invite's own checks, blocks, no-op for members.
      final accept = body(paths, 'accept_circle_invite');
      expect(accept, contains('are_users_blocked'));
      expect(accept, contains('circle_invite_invalid_reason'));
      expect(accept, contains('use_count = use_count + 1'));
      // join_public_circle: take-down, bans, hourly allowance.
      final join = body(paths, 'join_public_circle');
      expect(join, contains('disabled_at is not null'));
      expect(join, contains('circle_bans'));
      expect(join, contains('Too many circles joined'));
      expect(join, contains('circle_public_joins'));
      // invite_circle_members: friends only, not blocked, audited.
      final invite = body(paths, 'invite_circle_members');
      expect(invite, contains('public.friendships'));
      expect(invite, contains('are_users_blocked'));
      expect(invite, contains("'member_add'"));
    });

    test('skipping review needs create_invites and kick_members', () {
      expect(
        schema,
        contains(
          "circle_member_has_permission(\n      target_circle_id, inviter, 'create_invites')",
        ),
      );
      expect(schema, contains("'kick_members')"));
      expect(paths, contains('and not ci.skip_review'));
    });
  });

  group('the moderator side', () {
    test('deciding needs kick_members and writes the audit log', () {
      final decide = body(rpcs, 'decide_join_request');
      expect(decide, contains("'kick_members'"));
      expect(decide, contains("'join_request_approve'"));
      expect(decide, contains("'join_request_deny'"));
      expect(decide, contains('write_circle_audit'));
      expect(decide, contains('wake_scheduled_dispatch'));
    });

    test('the pushes are claimed by the service role only', () {
      expect(
        push,
        contains(
          'revoke execute on function public.claim_join_request_pushes()\n'
          '  from public, anon, authenticated;',
        ),
      );
      expect(
        push,
        contains(
          'grant execute on function public.claim_join_request_pushes() to service_role',
        ),
      );
    });
  });

  behaviourTest(
    'join requests: every path, the exemption, decisions, pushes and RLS',
    'test/supabase/join_requests_behaviour.sql',
  );
}

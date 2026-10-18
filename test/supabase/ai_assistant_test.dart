import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the @WeCord AI assistant (migrations 202610230400 to
/// 202610230430), plus the behaviour script: which texts count as a mention,
/// what queues a job (and what never does), the rate limit, who reads the job
/// queue, every gate the claim checks, what the model may read, the
/// assistant's identity, posting and reporting an answer, and the sweep.
void main() {
  late String identity;
  late String jobs;
  late String rpcs;
  late String channelSend;

  setUpAll(() {
    identity = File(
      'supabase/migrations/202610230400_ai_assistant_identity.sql',
    ).readAsStringSync();
    jobs = File(
      'supabase/migrations/202610230410_ai_assistant_jobs.sql',
    ).readAsStringSync();
    rpcs = File(
      'supabase/migrations/202610230420_ai_assistant_rpcs.sql',
    ).readAsStringSync();
    channelSend = File(
      'supabase/migrations/202610230430_ai_reply_channel_send.sql',
    ).readAsStringSync();
  });

  group('the identity', () {
    test('hard-codes no user id', () {
      final uuid = RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      );
      for (final sql in [identity, jobs, rpcs, channelSend]) {
        expect(uuid.hasMatch(sql), isFalse);
      }
    });

    test('is made at run time from a bot login the function just created', () {
      expect(identity, contains("raw_app_meta_data->>'provider' = 'bot'"));
      expect(identity, contains("interval '10 minutes'"));
      expect(identity, contains('pg_advisory_xact_lock'));
      expect(identity, contains("from public.system_bots b where b.key"));
      expect(
        identity,
        contains(
          'revoke execute on function public.register_ai_assistant(uuid) from public, anon, authenticated',
        ),
      );
      expect(
        identity,
        contains(
          'grant execute on function public.register_ai_assistant(uuid) to service_role',
        ),
      );
      expect(
        RegExp(
          r'^\s*insert into auth\.users',
          multiLine: true,
        ).hasMatch(identity),
        isFalse,
      );
    });

    test('the AI mark can only be written by the server', () {
      expect(identity, contains('messages_guard_ai_reply'));
      expect(identity, contains("current_user in ('authenticated', 'anon')"));
      expect(identity, contains('before insert or update of ai_reply'));
    });

    test('the group switch is read by members and written by the owner', () {
      expect(identity, contains("cm.role = 'owner'"));
      expect(identity, contains("c.type = 'group'"));
      expect(identity, isNot(contains('grant insert')));
      expect(identity, isNot(contains('grant update')));
    });
  });

  group('the queue', () {
    test('is closed to the API except the requester reading their status', () {
      expect(
        jobs,
        contains('alter table public.ai_jobs enable row level security'),
      );
      expect(
        jobs,
        contains('revoke all on public.ai_jobs from anon, authenticated'),
      );
      expect(jobs, contains('using (requester_id = auth.uid())'));
      final grant = jobs.substring(
        jobs.indexOf('grant select ('),
        jobs.indexOf('on public.ai_jobs to authenticated'),
      );
      expect(grant, isNot(contains('attempts')));
      expect(jobs, isNot(contains('grant insert')));
      expect(jobs, isNot(contains('grant update')));
      expect(jobs, isNot(contains('grant delete')));
    });

    test('wakes the ai function the way the AI guard does', () {
      expect(jobs, contains("public.ai_guard_wake("));
      expect(jobs, contains("'action', 'assistant'"));
      expect(jobs, contains('message_id uuid not null unique'));
    });

    test('every server function is closed to clients', () {
      for (final name in [
        'ai_assistant_close(uuid, text, text)',
        'ai_assistant_claim(uuid)',
        'ai_assistant_context(uuid)',
        'ai_assistant_reply(uuid, text, text, jsonb)',
        'ai_assistant_finish(uuid, text, text)',
      ]) {
        expect(
          rpcs,
          contains('revoke execute on function public.$name'),
          reason: name,
        );
      }
      for (final name in [
        'ai_assistant_claim(uuid)',
        'ai_assistant_context(uuid)',
        'ai_assistant_reply(uuid, text, text, jsonb)',
        'ai_assistant_finish(uuid, text, text)',
      ]) {
        expect(
          rpcs,
          contains('grant execute on function public.$name to service_role'),
          reason: name,
        );
      }
    });

    test('the context never includes held messages', () {
      expect(rpcs, contains('and m.review_state is null'));
      expect(rpcs, contains('current_user_readable_conversation_ids'));
    });
  });

  group('circle channels', () {
    test('only an AI reply skips the member checks', () {
      expect(channelSend, contains('if new.ai_reply is not null then'));
      expect(channelSend, contains("slowmode_seconds <= 0"));
      expect(channelSend, contains('An album can hold up to 10 items'));
    });
  });

  behaviourTest(
    'the assistant: mentions, queue, gates, context, identity, reports',
    'test/supabase/ai_assistant_behaviour.sql',
  );
}

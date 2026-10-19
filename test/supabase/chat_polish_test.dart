import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for the chat polish batch (A9 quoting part of a message and
/// silent sending, E6 voice channel status: migrations 202610240500 and
/// 202610240510), plus the behaviour script that plays them.
void main() {
  late String quote;
  late String status;

  setUpAll(() {
    String read(String name) =>
        File('supabase/migrations/$name.sql').readAsStringSync();
    quote = read('202610240500_quote_and_silent');
    status = read('202610240510_voice_channel_status');
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('quoting part of a message', () {
    test('the quote is checked against the original on the server', () {
      final text = body(quote, 'messages_check_reply_quote');
      expect(text, contains('strpos(original.body, quote_text) = 0'));
      expect(text, contains('m.conversation_id = new.conversation_id'));
      expect(text, contains('m.recalled_at is null'));
      expect(text, contains('m.expires_at > now()'));
      expect(text, contains('message_visible_to_current_user'));
      expect(text, contains('not between 1 and 500'));
      expect(text, contains("errcode = '22023'"));
    });

    test('only text, start and end are kept', () {
      final text = body(quote, 'messages_check_reply_quote');
      expect(text, contains("jsonb_build_object('text', quote_text)"));
      expect(text, contains("'start'"));
      expect(text, contains("'end'"));
    });

    test('a recall blanks the quote with the preview body', () {
      final text = body(quote, 'messages_check_reply_quote');
      expect(text, contains("new.reply_preview->>'body' = ''"));
      expect(text, contains("new.reply_preview - 'quote'"));
    });

    test('it works for direct inserts as well as the RPC', () {
      expect(
        quote,
        contains('before insert or update of reply_preview on public.messages'),
      );
      expect(quote, isNot(contains('function public.send_text_message(')));
    });
  });

  group('silent sending', () {
    test('send_text_message is not rewritten', () {
      for (final name in [
        'send_text_message',
        'claim_push_delivery',
        'run_later_dispatch',
        'recall_message',
      ]) {
        expect(quote, isNot(contains('function public.$name(')), reason: name);
      }
    });

    test('the flag is set on insert only', () {
      expect(
        quote,
        contains(
          'add column if not exists silent boolean not null default false',
        ),
      );
      expect(quote, contains('before insert on public.messages'));
      expect(
        body(quote, 'messages_silent_unchanged'),
        contains('new.silent := old.silent'),
      );
    });

    test('the wrapper needs a signed-in user and the push list is private', () {
      expect(
        body(quote, 'send_silent_text_message'),
        contains("errcode = '42501'"),
      );
      expect(
        quote,
        contains(
          'revoke execute on function public.silent_message_ids(uuid[]) from public, anon, authenticated;\n'
          'grant execute on function public.silent_message_ids(uuid[]) to service_role;',
        ),
      );
      expect(
        quote,
        contains(
          'grant execute on function public.send_silent_text_message(uuid, text, uuid, jsonb, jsonb, uuid) to authenticated;',
        ),
      );
    });

    test('the push functions leave silent messages out', () {
      final push = File('supabase/functions/push/index.ts').readAsStringSync();
      final dispatch = File(
        'supabase/functions/scheduled-dispatch/index.ts',
      ).readAsStringSync();
      expect(push, contains('dropSilentPushes('));
      expect(dispatch, contains('dropSilentPushes('));
    });
  });

  group('voice channel status', () {
    test('the length is limited in the table as well as the function', () {
      expect(status, contains('char_length(voice_status) between 1 and 60'));
      expect(status, contains(r"voice_status !~ '[\r\n\t]'"));
      expect(
        body(status, 'set_voice_channel_status'),
        contains('char_length(cleaned) > 60'),
      );
    });

    test('only people in the channel can set it', () {
      final text = body(status, 'set_voice_channel_status');
      expect(text, contains('from public.voice_states vs'));
      expect(
        text,
        contains('vs.last_seen_at > now() - public.voice_state_ttl()'),
      );
      expect(text, contains("'connect_voice'"));
      expect(text, contains("channel.kind <> 'voice'"));
      expect(text, contains('auth.uid()'));
      expect(text, contains("errcode = '42501'"));
    });

    test('readers must be members who can see the channel', () {
      final text = body(status, 'list_voice_channel_statuses');
      expect(text, contains('is_current_user_circle_member'));
      expect(text, contains("'view_channel'"));
      expect(
        text,
        contains('vs.last_seen_at > now() - public.voice_state_ttl()'),
      );
    });

    test('get_circle_detail is not rewritten', () {
      expect(status, isNot(contains('function public.get_circle_detail(')));
      expect(status, isNot(contains('function public.join_voice_state(')));
    });

    test('the functions are closed to the signed-out', () {
      for (final signature in [
        'set_voice_channel_status(uuid, text)',
        'list_voice_channel_statuses(uuid)',
      ]) {
        expect(
          status,
          contains(
            'revoke execute on function public.$signature from public, anon;',
          ),
          reason: signature,
        );
        expect(
          status,
          contains(
            'grant execute on function public.$signature to authenticated;',
          ),
          reason: signature,
        );
      }
    });
  });

  behaviourTest(
    'chat polish: quoting part of a message, silent sending, voice channel status',
    'test/supabase/chat_polish_behaviour.sql',
  );
}

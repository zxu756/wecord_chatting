import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Interactive components and interaction callbacks (I1: migrations
/// 202610280610 to 202610280660): what the SQL says, as text, plus the
/// behaviour script that plays people through it against the local database.
void main() {
  final names = [
    '202610280610_interactions_schema.sql',
    '202610280620_interactions_send.sql',
    '202610280630_interactions_submit.sql',
    '202610280640_interactions_bot_api.sql',
    '202610280650_interactions_callbacks.sql',
    '202610280660_interactions_account.sql',
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

  String body(String name, String function) {
    final source = sql[name]!;
    final start = source.indexOf(
      'create or replace function public.$function(',
    );
    expect(start, isNonNegative, reason: function);
    return source.substring(start, source.indexOf('\n\$\$;', start));
  }

  group('numbering and what is left alone', () {
    test('the migrations are in this package\'s range, ten apart', () {
      final numbers = [
        for (final name in names) int.parse(name.substring(0, 12)),
      ];
      for (var i = 0; i < numbers.length; i++) {
        expect(numbers[i], 202610280610 + i * 10);
      }
      expect(numbers.last, lessThan(202610280700));
    });

    test('the every-minute dispatcher is not redefined or run from here', () {
      expect(all, isNot(contains('function public.run_later_dispatch')));
      expect(all, isNot(contains('run_later_dispatch()')));
      final callbacks = sql['202610280650_interactions_callbacks.sql']!;
      expect(callbacks, contains("'wecord-bot-callbacks-retry'"));
      expect(callbacks, contains("'wecord-bot-interactions-purge'"));
      expect(
        callbacks,
        contains("pg_available_extensions where name = 'pg_cron'"),
      );
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('the functions other packages patched are not rewritten', () {
      for (final function in [
        'send_text_message',
        'edit_message',
        'messages_guard_server_fields',
        'message_visible_to_current_user',
        'check_channel_message_send',
        'current_user_readable_conversation_ids',
        'prepare_account_deletion',
        'list_circle_bots',
        'circle_bot_payload',
        'create_circle_bot',
        'invoke_bot_command',
        'bot_api_send_message',
      ]) {
        expect(
          all,
          isNot(contains('create or replace function public.$function(')),
          reason: function,
        );
      }
    });

    test(
      'the two bot functions that are rewritten say where they come from',
      () {
        final api = sql['202610280640_interactions_bot_api.sql']!;
        expect(api, contains('latest definition is 202610160030'));
        expect(api, contains('bot_api_poll_interactions'));
        expect(api, contains('bot_api_respond_interaction'));
        // The old answer keeps its signature so a function deployed before the
        // migration still works for commands.
        expect(
          body(
            '202610280640_interactions_bot_api.sql',
            'bot_api_respond_interaction',
          ),
          contains("pending.kind <> 'command'"),
        );
        expect(
          body(
            '202610280640_interactions_bot_api.sql',
            'bot_api_poll_interactions',
          ),
          contains("bi.delivery_state in ('none', 'failed')"),
        );
      },
    );
  });

  group('what a message may carry', () {
    test('the guard refuses clients and anything but a bot\'s text', () {
      final guard = body(
        '202610280610_interactions_schema.sql',
        'messages_guard_components',
      );
      expect(guard, contains("current_user in ('authenticated', 'anon')"));
      expect(guard, contains("new.type <> 'text'"));
      expect(guard, contains('new.webhook_id is not null'));
      expect(guard, contains('new.forwarded_from is not null'));
      expect(guard, contains('new.crosspost is not null'));
      expect(guard, contains('from public.circle_bots b'));
      expect(guard, contains('normalize_message_components(new.components)'));
      expect(guard, contains('new.recalled_at is not null'));
    });

    test('the checker keeps to the limits', () {
      final checker = body(
        '202610280610_interactions_schema.sql',
        'normalize_message_components',
      );
      expect(checker, contains('> 5'));
      expect(checker, contains('not between 1 and 5'));
      expect(checker, contains('total > 25'));
      expect(checker, contains('8192'));
      expect(checker, contains('not between 1 and 25'));
      expect(checker, contains("'A list takes a whole row'"));
      final schema = sql['202610280610_interactions_schema.sql']!;
      expect(schema, contains("candidate ~* '^https://"));
      expect(schema, contains('(:443)?'));
      expect(schema, contains(r'‪-‮'));
      expect(schema, contains('[[:cntrl:]'));
    });

    test('unknown keys are never copied', () {
      final checker = body(
        '202610280610_interactions_schema.sql',
        'normalize_message_components',
      );
      // Every kind is built key by key; the input is never stored as it is.
      expect(checker, isNot(contains('built := item')));
      expect(checker, isNot(contains('row_out || jsonb_build_array(item)')));
      expect(checker, isNot(contains('rows_out || jsonb_build_array(row_in)')));
      expect(
        RegExp(
          r'built := (jsonb_strip_nulls\()?jsonb_build_object\(',
        ).allMatches(checker).length,
        3,
      );
    });

    test('the private replies table is read-only to its owner', () {
      final schema = sql['202610280610_interactions_schema.sql']!;
      expect(
        schema,
        contains(
          'revoke all on public.bot_ephemeral_messages from public, anon, authenticated;',
        ),
      );
      expect(
        schema,
        contains(
          'grant select on public.bot_ephemeral_messages to authenticated;',
        ),
      );
      expect('create policy'.allMatches(all).length, 1);
      expect(schema, contains('user_id = auth.uid()'));
      expect(schema, contains('current_user_readable_conversation_ids()'));
      expect(schema, contains('offset 20'));
      expect(schema, contains('supabase_realtime'));
    });

    test('the callback table is closed to clients', () {
      final schema = sql['202610280610_interactions_schema.sql']!;
      expect(
        schema,
        contains('alter table public.bot_callbacks enable row level security;'),
      );
      expect(
        schema,
        contains(
          'revoke all on public.bot_callbacks from public, anon, authenticated;',
        ),
      );
      expect(schema, contains("secret ~ '^[0-9a-f]{64}\$'"));
    });
  });

  group('who may press', () {
    test('only someone who can read the message as it is now', () {
      final submit = body(
        '202610280630_interactions_submit.sql',
        'submit_interaction',
      );
      expect(submit, contains('current_user_readable_conversation_ids()'));
      expect(submit, contains('is_user_suspended(current_user_id)'));
      expect(submit, contains('message.recalled_at is not null'));
      expect(submit, contains('message.expires_at <= now()'));
      expect(submit, contains('message.review_state is not null'));
      expect(
        submit,
        contains(
          "circle_channel_has_permission(channel_id, bot.user_id, 'view_channel')",
        ),
      );
      expect(
        submit,
        contains('are_users_blocked(current_user_id, bot.user_id)'),
      );
      expect(submit, contains('e.user_id = current_user_id'));
      // A message the caller cannot read looks like one that is not there.
      expect(
        "raise exception 'Message not found' using errcode = 'P0002'"
            .allMatches(submit)
            .length,
        greaterThanOrEqualTo(3),
      );
    });

    test('limits: per person, per component, per bot', () {
      final submit = body(
        '202610280630_interactions_submit.sql',
        'submit_interaction',
      );
      expect(submit, contains(">= 30"));
      expect(submit, contains("interval '1 minute'"));
      expect(submit, contains("interval '1 second'"));
      expect(submit, contains(">= 200"));
      expect("errcode = 'BT429'".allMatches(submit).length, 3);
    });

    test('the answer is checked against what the bot defined', () {
      final check = body(
        '202610280630_interactions_submit.sql',
        'check_component_values',
      );
      expect(check, contains("component->>'min_values'"));
      expect(check, contains("component->>'max_values'"));
      expect(check, contains('That option is not in the list'));
      expect(check, contains('That field is not in the form'));
      expect(check, contains("field->>'max_length'"));
      expect(check, contains('A button takes no values'));
    });

    test('grants: members press, nobody else', () {
      final submit = sql['202610280630_interactions_submit.sql']!;
      for (final signature in [
        'submit_interaction(uuid, text, jsonb)',
        'interaction_status(uuid)',
        'list_my_ephemeral_messages(uuid)',
        'dismiss_ephemeral_message(uuid)',
      ]) {
        expect(
          submit,
          contains(
            'revoke execute on function public.$signature from public, anon;',
          ),
        );
        expect(
          submit,
          contains(
            'grant execute on function public.$signature to authenticated;',
          ),
        );
      }
    });
  });

  group('what the bot can do', () {
    test('bot functions are for the service role only', () {
      for (final signature in [
        'bot_api_send_message_with_components(text, uuid, text, uuid, jsonb)',
        'bot_api_edit_message(text, uuid, text, boolean, jsonb)',
        'bot_api_respond(text, uuid, jsonb)',
      ]) {
        expect(
          all,
          contains(
            'revoke execute on function public.$signature from public, anon, authenticated;',
          ),
        );
        expect(
          all,
          contains(
            'grant execute on function public.$signature to service_role;',
          ),
        );
      }
    });

    test('a bot\'s writes count and AutoMod reads the buttons', () {
      expect(
        body(
          '202610280620_interactions_send.sql',
          'bot_api_send_message_with_components',
        ),
        allOf(
          contains('count_bot_write(bot)'),
          contains('bot_components_automod'),
          contains('act_as_bot(bot)'),
          contains('bot_visible_channel(bot, target_channel_id)'),
        ),
      );
      expect(
        body('202610280640_interactions_bot_api.sql', 'bot_api_respond'),
        allOf(
          contains('count_bot_write(bot)'),
          contains('bot_components_automod'),
          contains('bot_text_blocked'),
        ),
      );
      expect(
        body('202610280620_interactions_send.sql', 'bot_text_blocked'),
        contains('circle_automod_verdict'),
      );
    });

    test('components ride in on a setting that is cleared again', () {
      final send = body('202610280620_interactions_send.sql', 'bot_send_text');
      expect(send, contains("set_config('wecord.message_components'"));
      expect(
        "set_config('wecord.message_components', '', true)"
            .allMatches(send)
            .length,
        2,
      );
      expect(send, contains('public.send_text_message('));
    });

    test('a bot changes only its own message', () {
      final edit = body(
        '202610280620_interactions_send.sql',
        'bot_edit_own_message',
      );
      expect(edit, contains('message.sender_id <> bot.user_id'));
      expect(edit, contains('message.recalled_at is not null'));
      expect(edit, contains("message.type <> 'text'"));
      expect(edit, contains('cc.circle_id = bot.circle_id'));
      expect(edit, contains("sqlerrm like 'AutoMod blocked%'"));
    });

    test('one answer per press', () {
      final respond = body(
        '202610280640_interactions_bot_api.sql',
        'bot_api_respond',
      );
      expect(respond, contains('for update'));
      expect(respond, contains("errcode = '23505'"));
      expect(respond, contains("pending.expires_at <= now()"));
      expect(respond, contains('bi.bot_id = bot.id'));
      expect(respond, contains("response_type <> 'message'"));
    });
  });

  group('the callback', () {
    test('the address is checked in the database', () {
      final callbacks = sql['202610280650_interactions_callbacks.sql']!;
      final check = body(
        '202610280650_interactions_callbacks.sql',
        'bot_callback_url_problem',
      );
      expect(check, contains("!~* '^https://'"));
      expect(check, contains('components_https_url_ok'));
      expect(check, contains('nip'));
      expect(callbacks, contains('(no IP address'));
      expect(
        body('202610280650_interactions_callbacks.sql', 'set_bot_callback'),
        allOf(
          contains('circle_bot_for_management(target_bot_id)'),
          contains('bot_callback_url_problem(callback_url)'),
          contains("'bot_callback_set'"),
        ),
      );
    });

    test('the secret is shown once and never read back', () {
      final callbacks = sql['202610280650_interactions_callbacks.sql']!;
      final state = body(
        '202610280650_interactions_callbacks.sql',
        'bot_callback_state',
      );
      expect(state, isNot(contains('secret')));
      expect(
        callbacks,
        contains("encode(extensions.gen_random_bytes(32), 'hex')"),
      );
      for (final function in [
        'set_bot_callback',
        'rotate_bot_callback_secret',
      ]) {
        expect(
          body('202610280650_interactions_callbacks.sql', function),
          contains("write_circle_audit"),
        );
      }
      // The audit entry never holds the secret.
      final set = body(
        '202610280650_interactions_callbacks.sql',
        'set_bot_callback',
      );
      final audit = set.substring(
        set.indexOf('write_circle_audit'),
        set.indexOf(');', set.indexOf('write_circle_audit')),
      );
      expect(audit, isNot(contains('secret')));
      expect(audit, contains('host'));
    });

    test('delivery is for the service role, with leases and backoff', () {
      final callbacks = sql['202610280650_interactions_callbacks.sql']!;
      final claim = body(
        '202610280650_interactions_callbacks.sql',
        'claim_bot_callbacks',
      );
      expect(claim, contains('for update of bi skip locked'));
      expect(claim, contains("interval '30 seconds'"));
      expect(claim, contains('bi.delivery_attempts < 4'));
      expect(claim, contains('bi.expires_at > now()'));
      final finish = body(
        '202610280650_interactions_callbacks.sql',
        'finish_bot_callback',
      );
      expect(finish, contains("interval '5 seconds'"));
      expect(finish, contains("interval '30 seconds'"));
      expect(finish, contains("interval '2 minutes'"));
      expect(finish, contains('>= 20'));
      for (final signature in [
        'claim_bot_callbacks(integer)',
        'finish_bot_callback(uuid, boolean, integer, text)',
        'wake_bot_callbacks()',
        'wake_bot_callbacks_if_due()',
        'purge_bot_interactions()',
      ]) {
        expect(
          callbacks,
          contains(
            'grant execute on function public.$signature to service_role;',
          ),
        );
      }
      expect(
        callbacks,
        contains("'Authorization', 'Bearer ' || dispatch_secret"),
      );
      expect(
        callbacks,
        contains("rtrim(functions_url, '/') || '/bot-callbacks'"),
      );
    });
  });

  group('account and export', () {
    test('deleting an account erases presses and private replies', () {
      final account = sql['202610280660_interactions_account.sql']!;
      final erase = body(
        '202610280660_interactions_account.sql',
        'erase_interactions_of_deleted_account',
      );
      expect(erase, contains('delete from public.bot_interactions'));
      expect(erase, contains('delete from public.bot_ephemeral_messages'));
      expect(
        account,
        contains('after update of deleted_at on public.profiles'),
      );
      expect(
        account,
        isNot(contains('function public.prepare_account_deletion')),
      );
    });

    test('the export holds only the person\'s own', () {
      final export = body(
        '202610280660_interactions_account.sql',
        'export_my_interactions',
      );
      expect(export, contains('bi.user_id = target_user_id'));
      expect(export, contains('e.user_id = target_user_id'));
      expect(export, isNot(contains('token')));
      expect(export, isNot(contains('secret')));
      expect(
        sql['202610280660_interactions_account.sql'],
        contains(
          'grant execute on function public.export_my_interactions(uuid) to service_role;',
        ),
      );
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/interactions_behaviour.sql',
  );
}

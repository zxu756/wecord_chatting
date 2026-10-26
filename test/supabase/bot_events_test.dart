import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Event subscriptions (I2), the bot API 2.0 and the developer page (I3:
/// migrations 202610281100 to 202610281160): what the SQL says, as text, plus
/// the behaviour script that plays people and bots through it against the
/// local database.
void main() {
  final names = [
    '202610281100_bot_events_schema.sql',
    '202610281110_bot_events_enqueue.sql',
    '202610281120_bot_api2_core.sql',
    '202610281130_bot_api2_chats.sql',
    '202610281140_bot_api2_access.sql',
    '202610281150_developer_page.sql',
    '202610281160_developer_account.sql',
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
        expect(numbers[i], 202610281100 + i * 10);
      }
      expect(numbers.last, lessThan(202610281200));
    });

    test('the every-minute dispatcher is not redefined or run from here', () {
      expect(all, isNot(contains('function public.run_later_dispatch')));
      expect(all, isNot(contains('run_later_dispatch()')));
      final enqueue = sql['202610281110_bot_events_enqueue.sql']!;
      expect(enqueue, contains("'wecord-bot-events-retry'"));
      expect(enqueue, contains("'wecord-bot-events-purge'"));
      expect(
        enqueue,
        contains("pg_available_extensions where name = 'pg_cron'"),
      );
      expect(
        sql['202610281120_bot_api2_core.sql'],
        contains("'wecord-bot-api-calls-purge'"),
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
        'recall_message',
        'toggle_message_reaction',
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
        'bot_api_send_message_with_components',
        'bot_api_edit_message',
        'bot_from_token',
        'count_bot_write',
        'act_as_bot',
        'set_bot_callback',
        'claim_bot_callbacks',
        'create_group_conversation',
        'create_poll',
        'create_thread',
      ]) {
        expect(
          all,
          isNot(contains('create or replace function public.$function(')),
          reason: function,
        );
      }
    });

    test('the rewritten functions say where they come from', () {
      final core = sql['202610281120_bot_api2_core.sql']!;
      expect(core, contains('bot_api_me             (202610160030)'));
      expect(core, contains('bot_api_list_channels  (202610160030)'));
      expect(core, contains('bot_edit_own_message   (202610280620)'));
      expect(core, contains('bot_api_add_reaction   (202610160030)'));
      final edit = body(
        '202610281120_bot_api2_core.sql',
        'bot_edit_own_message',
      );
      expect(
        edit,
        contains('bot_conversation_access(bot, message.conversation_id)'),
      );
      expect(edit, contains("sqlerrm like 'AutoMod blocked%'"));
      expect(edit, contains('message.sender_id <> bot.user_id'));
    });

    test('the direct chat function is patched in place, once', () {
      final access = sql['202610281140_bot_api2_access.sql']!;
      expect(
        access,
        contains(
          "pg_get_functiondef('public.get_or_create_direct_conversation(uuid)'::regprocedure)",
        ),
      );
      expect(access, contains('/ length(anchor) <> 1'));
      expect(
        access,
        contains('bot_accepts_direct_chat(current_user_id, other_user_id)'),
      );
      expect(
        access,
        isNot(
          contains(
            'create or replace function public.get_or_create_direct_conversation',
          ),
        ),
      );
    });
  });

  group('who is told what', () {
    test('one rule decides what a bot may read', () {
      final access = body(
        '202610281100_bot_events_schema.sql',
        'bot_conversation_access',
      );
      expect(access, contains('bot.token_hash is null'));
      expect(access, contains('cm.user_id = bot.user_id'));
      expect(access, contains('conversation_in_suspended_circle'));
      expect(access, contains("'view_channel'"));
      expect(access, contains('allow_groups'));
      expect(access, contains('allow_direct'));
      expect(access, contains('are_users_blocked(bot.user_id, peer)'));
      expect(access, contains('conversation_threads'));
    });

    test('the words are held back where they must be', () {
      final withheld = body(
        '202610281110_bot_events_enqueue.sql',
        'bot_event_withheld_reason',
      );
      expect(withheld, contains('conversation_restricts_sharing'));
      expect(withheld, contains('locked_conversation_ids'));
      expect(withheld, contains('message.expires_at is not null'));
      expect(withheld, contains("view_once"));
    });

    test('a person is only id, username, name and whether a bot', () {
      final person = body(
        '202610281110_bot_events_enqueue.sql',
        'bot_event_person',
      );
      for (final key in ["'id'", "'username'", "'name'", "'is_bot'"]) {
        expect(person, contains(key));
      }
      for (final leak in ['email', 'bio', 'birthday', 'status', 'phone']) {
        expect(person, isNot(contains(leak)));
      }
    });

    test('a file is named, never linked', () {
      final message = body(
        '202610281110_bot_events_enqueue.sql',
        'bot_event_message_json',
      );
      expect(message, contains("message.attachment->>'name'"));
      expect(message, isNot(contains("attachment->>'path'")));
      expect(message, isNot(contains("attachment->>'bucket'")));
      expect(message, contains('left(message.body, 4000)'));
    });

    test('nothing is queued for the bot\'s own doings, blocks or review', () {
      final enqueue = sql['202610281110_bot_events_enqueue.sql']!;
      expect(
        'public.are_users_blocked('.allMatches(enqueue).length,
        greaterThanOrEqualTo(6),
      );
      expect(enqueue, contains('bot.user_id = message.sender_id'));
      expect(
        enqueue,
        contains(
          "when (new.type <> 'system' and new.review_state is null and new.recalled_at is null)",
        ),
      );
      expect(
        enqueue,
        contains('old.review_state is not null and new.review_state is null'),
      );
    });

    test('the queue is checked again before anything is sent', () {
      final claim = body(
        '202610281110_bot_events_enqueue.sql',
        'claim_bot_events',
      );
      expect(
        claim,
        contains('bot_conversation_access(bot, due.conversation_id)'),
      );
      expect(claim, contains("'owner_lost_access'"));
      expect(claim, contains("interval '6 hours'"));
      expect(claim, contains("interval '30 seconds'"));
      expect(claim, contains('for update of d skip locked'));
      final finish = body(
        '202610281110_bot_events_enqueue.sql',
        'finish_bot_event',
      );
      expect(finish, contains(">= 20"));
      for (final step in [
        "'5 seconds'",
        "'30 seconds'",
        "'2 minutes'",
        "'10 minutes'",
        "'1 hour'",
      ]) {
        expect(finish, contains(step));
      }
    });

    test('limits: 300 a minute, 1000 waiting, payloads under 14 KB', () {
      final enqueue = sql['202610281110_bot_events_enqueue.sql']!;
      expect(enqueue, contains('counted > 300'));
      expect(enqueue, contains('>= 1000'));
      expect(sql['202610281100_bot_events_schema.sql'], contains('<= 14336'));
    });
  });

  group('settings and secrets', () {
    test('managers only, the same address rules as the callback', () {
      for (final function in [
        'get_bot_event_subscription',
        'set_bot_event_subscription',
        'rotate_bot_event_secret',
        'clear_bot_event_subscription',
      ]) {
        expect(
          body('202610281100_bot_events_schema.sql', function),
          contains('circle_bot_for_management(target_bot_id)'),
          reason: function,
        );
      }
      expect(
        body(
          '202610281100_bot_events_schema.sql',
          'set_bot_event_subscription',
        ),
        contains('bot_callback_url_problem(event_url)'),
      );
    });

    test('the secret is shown once and never read back', () {
      expect(
        body(
          '202610281100_bot_events_schema.sql',
          'bot_event_subscription_state',
        ),
        isNot(contains('secret')),
      );
      expect(
        body(
          '202610281100_bot_events_schema.sql',
          'get_bot_event_subscription',
        ),
        isNot(contains('secret')),
      );
      expect(
        body(
          '202610281110_bot_events_enqueue.sql',
          'list_bot_event_deliveries',
        ),
        isNot(contains('payload')),
      );
      expect(
        body('202610281150_developer_page.sql', 'list_my_developer_bots'),
        isNot(contains('token_hash')),
      );
    });

    test('the tables are closed to clients', () {
      final schema = sql['202610281100_bot_events_schema.sql']!;
      for (final table in ['bot_event_subscriptions', 'bot_event_deliveries']) {
        expect(
          schema,
          contains('alter table public.$table enable row level security;'),
        );
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated;',
          ),
        );
      }
      expect(
        sql['202610281120_bot_api2_core.sql'],
        contains(
          'revoke all on public.bot_api_calls from public, anon, authenticated;',
        ),
      );
      expect('create policy'.allMatches(all).length, 0);
    });

    test('server functions are for the service role only', () {
      for (final signature in [
        'claim_bot_events(integer)',
        'finish_bot_event(uuid, boolean, integer, text)',
        'bot_api_log_call(text, text, text, integer)',
        'export_my_developer(uuid)',
      ]) {
        expect(
          all,
          contains(
            'grant execute on function public.$signature to service_role;',
          ),
          reason: signature,
        );
      }
    });
  });

  group('the bot API', () {
    test('every write counts and runs as the bot', () {
      final chats = sql['202610281130_bot_api2_chats.sql']!;
      for (final function in [
        'bot_api_send_chat_message',
        'bot_api_send_file_message',
        'bot_api_create_poll',
        'bot_api_create_thread',
        'bot_api_delete_message',
        'bot_api_remove_reaction',
      ]) {
        final text = body('202610281130_bot_api2_chats.sql', function);
        expect(text, contains('count_bot_write(bot)'), reason: function);
        expect(text, contains('act_as_bot(bot)'), reason: function);
      }
      expect(chats, contains('bot_components_automod'));
      expect(chats, contains('bot_text_blocked'));
    });

    test('a bot reads only the chats it may', () {
      final chats = sql['202610281130_bot_api2_chats.sql']!;
      expect(chats, contains('bot_visible_conversation(bot, target_chat_id)'));
      expect(chats, contains('bot_conversation_access(bot, c.id)'));
      expect(chats, contains('m.created_at >= joined'));
      expect(chats, contains('m.review_state is null'));
      expect(chats, contains('are_users_blocked(m.sender_id, bot.user_id)'));
      expect(chats, contains('p.deleted_at is null'));
    });

    test('files must be in the bot\'s own folder and not used twice', () {
      final file = body(
        '202610281130_bot_api2_chats.sql',
        'bot_api_send_file_message',
      );
      expect(file, contains("chat_id::text || '/' || bot.user_id::text"));
      expect(file, contains("o.bucket_id = 'chat-files'"));
      expect(file, contains("errcode = '23505'"));
      expect(file, contains('52428800'));
    });

    test('a bot deletes only its own messages', () {
      final delete = body(
        '202610281130_bot_api2_chats.sql',
        'bot_api_delete_message',
      );
      expect(delete, contains('message.sender_id <> bot.user_id'));
      expect(delete, contains('recall_message(message.id)'));
    });
  });

  group('who may bring a bot in', () {
    test('only the group owner, within the limits', () {
      final add = body('202610281140_bot_api2_access.sql', 'add_bot_to_group');
      expect(add, contains("cm.role = 'owner'"));
      expect(add, contains('not bot.allow_groups'));
      expect(add, contains('conversation_restricts_sharing'));
      expect(add, contains('>= 5'));
      expect(add, contains('are_users_blocked(current_user_id, bot.user_id)'));
    });

    test('the direct chat exception is for people and open bots', () {
      final accepts = body(
        '202610281140_bot_api2_access.sql',
        'bot_accepts_direct_chat',
      );
      expect(accepts, contains('b.allow_direct'));
      expect(accepts, contains('b.token_hash is not null'));
      expect(accepts, contains('circle_is_suspended'));
      expect(accepts, contains('p.is_bot'));
    });

    test('the developer page asks for manage_circle', () {
      final page = sql['202610281150_developer_page.sql']!;
      expect(page, contains("'manage_circle'"));
      expect(
        body('202610281150_developer_page.sql', 'list_bot_api_calls'),
        contains('circle_bot_for_management(target_bot_id)'),
      );
    });
  });

  group('deleting an account and taking the data', () {
    test('events about the person go, their subscription is paused', () {
      final erase = body(
        '202610281160_developer_account.sql',
        'erase_bot_events_of_deleted_account',
      );
      expect(erase, contains('d.actor_id = new.id'));
      expect(erase, contains("last_error = 'owner_lost_access'"));
    });

    test('the export holds no token and no secret', () {
      final export = body(
        '202610281160_developer_account.sql',
        'export_my_developer',
      );
      expect(export, contains('b.created_by = target_user_id'));
      expect(export, isNot(contains('token')));
      expect(export, isNot(contains('s.secret')));
      expect(export, isNot(contains('cb.secret')));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/bot_events_behaviour.sql',
  );
}

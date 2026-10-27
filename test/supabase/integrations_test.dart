import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Rich webhooks, RSS feeds and GitHub connections (I6: migrations
/// 202610290200 to 202610290230): what the SQL says, as text, plus the
/// behaviour script that plays people through it against the local database.
void main() {
  final names = [
    '202610290200_integrations_schema.sql',
    '202610290210_integrations_rpcs.sql',
    '202610290220_integrations_post.sql',
    '202610290230_integrations_account.sql',
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
        expect(numbers[i], 202610290200 + i * 10);
      }
      expect(numbers.last, lessThan(202610290300));
    });

    test(
      'the dispatcher, the push claim and the webhook post stay as they are',
      () {
        expect(all, isNot(contains('function public.run_later_dispatch')));
        expect(all, isNot(contains('function public.claim_push_delivery')));
        expect(all, isNot(contains('function public.post_webhook_message(')));
      },
    );

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('the webhook functions are patched in place, not rewritten', () {
      final rpcs = sql['202610290210_integrations_rpcs.sql']!;
      expect(rpcs, contains('pg_get_functiondef'));
      expect(rpcs, contains('changed shape; patch it by hand'));
    });
  });

  group('the tables', () {
    test('feeds and connections are closed to clients', () {
      final schema = sql['202610290200_integrations_schema.sql']!;
      for (final table in [
        'channel_feeds',
        'channel_github_hooks',
        'github_deliveries',
      ]) {
        expect(
          schema,
          contains('alter table public.$table enable row level security'),
          reason: table,
        );
      }
      expect(schema, isNot(contains('create policy')));
      expect(
        schema,
        isNot(matches(RegExp(r'grant (select|insert|update|delete)'))),
      );
    });

    test('cards are an object of bounded size and clients cannot set them', () {
      final schema = sql['202610290200_integrations_schema.sql']!;
      expect(schema, contains("jsonb_typeof(embeds) = 'object'"));
      expect(schema, contains('messages_guard_embeds'));
      expect(schema, contains('8192'));
      expect(schema, contains('6000'));
      expect(schema, contains('At most 3 cards'));
    });

    test('a feed keeps what it needs to read politely and no more', () {
      final schema = sql['202610290200_integrations_schema.sql']!;
      for (final column in [
        'etag',
        'last_modified',
        'seen_keys',
        'next_fetch_at',
        'lease_until',
        'consecutive_failures',
      ]) {
        expect(schema, contains(column), reason: column);
      }
    });
  });

  group('the functions', () {
    test(
      'every new function is security definer with a pinned search path',
      () {
        final pattern = RegExp(
          r'create or replace function public\.(\w+)\(([\s\S]*?)\n\$\$;',
        );
        for (final name in names) {
          for (final match in pattern.allMatches(sql[name]!)) {
            final body = match.group(0)!;
            final function = match.group(1)!;
            expect(
              body,
              contains('set search_path = public'),
              reason: '$function in $name',
            );
            // The guard trigger must see who is asking, so it is not definer.
            if (function == 'messages_guard_embeds') {
              continue;
            }
            expect(
              body,
              anyOf(
                contains('security definer'),
                contains('immutable'),
                contains('\nstable'),
                contains('language sql'),
              ),
              reason: '$function in $name',
            );
          }
        }
      },
    );

    test('people manage them only with the permission, in a live circle', () {
      final rpcs = sql['202610290210_integrations_rpcs.sql']!;
      expect(rpcs, contains("'manage_webhooks'"));
      expect(rpcs, contains('This circle was taken down'));
      expect(rpcs, contains('bot_callback_url_problem'));
      expect(rpcs, contains('A circle can follow at most 10 feeds'));
      expect(rpcs, contains('A channel can follow at most 5 feeds'));
    });

    test('the posting and reading functions are for the service role only', () {
      final post = sql['202610290220_integrations_post.sql']!;
      for (final function in [
        'claim_channel_feeds',
        'finish_channel_feed',
        'post_feed_items',
        'post_github_event',
        'post_webhook_message_rich',
        'github_hook_for_delivery',
        'wake_feed_fetch_if_due',
      ]) {
        expect(
          post,
          anyOf(
            contains("'$function("),
            contains('grant execute on function public.$function('),
          ),
          reason: function,
        );
      }
      expect(post, contains('to service_role'));
      expect(post, isNot(contains('to authenticated')));
    });

    test('feeds are paced and fail politely', () {
      final post = sql['202610290220_integrations_post.sql']!;
      expect(post, contains("interval '15 minutes'"));
      expect(post, contains('failures >= 8'));
      expect(post, contains('48'));
      expect(post, contains('lease_until'));
    });

    test('a separate cron wakes the feed function like the dispatcher', () {
      final post = sql['202610290220_integrations_post.sql']!;
      expect(post, contains('wecord-feed-fetch'));
      expect(post, contains('*/5 * * * *'));
      expect(post, contains('wecord_functions_url'));
      expect(post, contains('wecord_dispatch_secret'));
      expect(post, contains('wecord-integrations-purge'));
    });
  });

  group('the account', () {
    test(
      'deleting an account pauses what it set up; the export has no secret',
      () {
        final account = sql['202610290230_integrations_account.sql']!;
        expect(account, contains('erase_integrations_of_deleted_account'));
        expect(account, contains('profiles_erase_integrations'));
        expect(account, contains('export_my_integrations'));
        expect(account, contains('service_role'));
        final export = account.substring(
          account.indexOf('function public.export_my_integrations'),
        );
        expect(export, isNot(contains('h.secret')));
      },
    );
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/integrations_behaviour.sql',
  );
}

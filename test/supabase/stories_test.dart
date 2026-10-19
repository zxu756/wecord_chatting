import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// The Daily (B1, migrations 202610240200 to 202610240250): schema checks plus
/// the behaviour script (who sees what, the end of a daily, replies, reports,
/// the private bucket, export and account deletion).
void main() {
  String read(String name) =>
      File('supabase/migrations/$name').readAsStringSync();

  late String schema;
  late String visibility;
  late String rpcs;
  late String reports;
  late String cleanup;
  late String export;

  setUpAll(() {
    schema = read('202610240200_stories_schema.sql');
    visibility = read('202610240210_stories_visibility.sql');
    rpcs = read('202610240220_stories_rpcs.sql');
    reports = read('202610240230_story_reports.sql');
    cleanup = read('202610240240_stories_signals_cleanup.sql');
    export = read('202610240250_export_my_stories.sql');
  });

  test(
    'every table is closed to the API, apart from what a person may read',
    () {
      for (final table in [
        'stories',
        'story_views',
        'story_reactions',
        'story_close_friends',
        'story_media_cleanup',
        'story_reports',
      ]) {
        expect(schema, contains('alter table public.$table enable row level'));
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated;',
          ),
          reason: table,
        );
      }
      // Views, reactions, the queue and reports are never readable directly.
      for (final table in [
        'story_views',
        'story_reactions',
        'story_media_cleanup',
        'story_reports',
      ]) {
        expect(schema, isNot(contains('grant select on public.$table')));
      }
    },
  );

  test('the audience of a daily is not a readable column', () {
    final grant = RegExp(
      r'grant select \(([^)]*)\) on public\.stories to authenticated;',
    ).firstMatch(schema);
    expect(grant, isNotNull);
    expect(grant!.group(1), contains('expires_at'));
    expect(grant.group(1), isNot(contains('audience')));
  });

  test('a daily is 15 seconds and 20 MB, in a private bucket', () {
    expect(schema, contains('duration_ms between 1 and 16000'));
    expect(schema, contains('size between 0 and 20971520'));
    expect(visibility, contains('20971520'));
    expect(
      visibility,
      contains("'stories',\n  'stories',\n  false,"),
      reason: 'the bucket is private',
    );
    expect(
      visibility,
      contains('(storage.foldername(name))[1] = auth.uid()::text'),
    );
    expect(rpcs, contains("p_duration_ms > 16000"));
  });

  test('the rule is the Moments rule with a clock', () {
    expect(visibility, contains('s.expires_at <= now()'));
    expect(
      visibility,
      contains('public.moments_are_friends(viewer, s.author_id)'),
    );
    expect(visibility, contains('fp.hide_mine'));
    expect(visibility, contains('friend_tag_members'));
    expect(
      visibility,
      contains('revoke execute on function public.story_visible_to'),
    );
  });

  test('the files are read by the rule and nothing else does', () {
    expect(visibility, contains('public.story_visible_to(st, auth.uid())'));
    expect(visibility, contains('public.is_app_admin()'));
    expect(visibility, contains("r.status = 'open'"));
  });

  test('replies are chat messages and go through the chat rules', () {
    expect(
      rpcs,
      contains('public.get_or_create_direct_conversation(s.author_id)'),
    );
    expect(rpcs, contains('is_current_user_blocked_in_conversation'));
    expect(rpcs, contains("'story_ref'"));
  });

  test('only the author lists viewers', () {
    final start = rpcs.indexOf('function public.list_story_viewers(');
    final body = rpcs.substring(start, rpcs.indexOf(r'$$;', start));
    expect(body, contains('s.author_id <> me'));
    expect(body, contains('moments_are_friends(me, v.viewer_id)'));
  });

  test('the end of a daily has its own jobs and leaves the dispatch alone', () {
    expect(cleanup, contains("'wecord-purge-expired-stories'"));
    expect(cleanup, contains("'wecord-expire-story-files'"));
    // The wake-up uses the project's own Vault secrets, and the job is made
    // whether or not they exist yet.
    expect(cleanup, contains("'wecord_functions_url'"));
    expect(cleanup, contains("'wecord_dispatch_secret'"));
    expect(cleanup, contains("'select public.wake_expire_stories()'"));
    expect(cleanup, isNot(contains('project_url')));
    expect(cleanup, isNot(contains('service_role_key')));
    expect(cleanup, contains("pg_available_extensions where name = 'pg_cron'"));
    for (final sql in [schema, visibility, rpcs, reports, cleanup, export]) {
      expect(sql, isNot(contains('function public.run_later_dispatch')));
    }
    expect(cleanup, contains('after update of deleted_at on public.profiles'));
  });

  test('admin report functions check the role first', () {
    for (final name in [
      'admin_list_story_reports',
      'admin_get_story_report',
      'admin_resolve_story_report',
    ]) {
      final start = reports.indexOf('function public.$name(');
      final body = reports.substring(start, reports.indexOf(r'$$;', start));
      expect(body, contains('admin_require('), reason: name);
    }
  });

  test('the export is for the service role only', () {
    for (final role in ['public', 'anon', 'authenticated']) {
      expect(
        export,
        contains(
          'revoke execute on function public.export_my_stories(uuid) from $role;',
        ),
      );
    }
  });

  test('migrations stay in the numbers of this package and name no user', () {
    for (final entry in {
      '202610240200_stories_schema.sql': schema,
      '202610240210_stories_visibility.sql': visibility,
      '202610240220_stories_rpcs.sql': rpcs,
      '202610240230_story_reports.sql': reports,
      '202610240240_stories_signals_cleanup.sql': cleanup,
      '202610240250_export_my_stories.sql': export,
    }.entries) {
      expect(entry.value, isNot(contains('insert into auth.users')));
      expect(
        entry.value,
        isNot(
          matches(
            RegExp(
              r"'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'",
            ),
          ),
        ),
        reason: '${entry.key} names no user id',
      );
    }
  });

  test(
    'deleting an account empties the stories folder and the export links it',
    () {
      final account = File(
        'supabase/functions/delete-account/index.ts',
      ).readAsStringSync();
      expect(account, contains('"stories",'));
      final collect = File(
        'supabase/functions/data-export/collect.ts',
      ).readAsStringSync();
      expect(collect, contains('"export_my_stories"'));
      final config = File('supabase/config.toml').readAsStringSync();
      expect(config, contains('[functions.expire-stories]'));
      final stories = File(
        'supabase/functions/expire-stories/index.ts',
      ).readAsStringSync();
      expect(stories, contains('DISPATCH_SECRET'));
      expect(stories, contains('unauthorized'));
    },
  );

  behaviourTest(
    'dailies follow the audience, the clock, the bucket and the chat rules',
    'test/supabase/stories_behaviour.sql',
  );
}

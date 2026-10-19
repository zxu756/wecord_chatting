import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for Favorites 2.0 (B3), migrations 202610250400 to
/// 202610250430, plus the behaviour script that plays every kind, rule,
/// refusal and removal through the RPCs.
void main() {
  late Map<String, String> sql;

  setUpAll(() {
    sql = {
      for (final name in const [
        '202610250400_saved_items_schema',
        '202610250410_saved_items_rpcs',
        '202610250420_saved_notes_bucket',
        '202610250430_export_my_saved_items',
      ])
        name: File('supabase/migrations/$name.sql').readAsStringSync(),
    };
  });

  String body(String file, String name) {
    final text = sql[file]!;
    final start = text.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return text.substring(start, text.indexOf('\n\$\$;', start));
  }

  group('closed to the outside', () {
    test('definers pin the search path', () {
      for (final MapEntry(:key, :value) in sql.entries) {
        final functions = RegExp(
          r'create or replace function public\.(\w+)\(',
        ).allMatches(value);
        for (final match in functions) {
          final text = body(key, match.group(1)!);
          if (text.contains('security definer')) {
            expect(
              text,
              contains('set search_path = public'),
              reason: '${match.group(1)} in $key',
            );
          }
        }
      }
    });

    test('the tables allow reading and deleting one\'s own rows only', () {
      final schema = sql['202610250400_saved_items_schema']!;
      for (final table in ['saved_items', 'saved_folders']) {
        expect(
          schema,
          contains('alter table public.$table enable row level security'),
          reason: table,
        );
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated',
          ),
          reason: table,
        );
        expect(
          schema,
          contains('grant select, delete on public.$table to authenticated'),
          reason: table,
        );
      }
      expect(schema, isNot(contains('grant insert')));
      expect(schema, isNot(contains('grant update')));
    });

    test('listing and search run as the caller', () {
      final rpcs = sql['202610250410_saved_items_rpcs']!;
      for (final name in [
        'list_saved_items',
        'list_saved_messages',
        'search_saved_items',
      ]) {
        final text = body('202610250410_saved_items_rpcs', name);
        expect(text, contains('security invoker'), reason: name);
        expect(text, isNot(contains('security definer')), reason: name);
      }
      expect(
        rpcs,
        contains('revoke execute on function public.list_saved_items(integer)'),
      );
    });

    test('the export is for the service role only', () {
      final export = sql['202610250430_export_my_saved_items']!;
      for (final role in ['public', 'anon', 'authenticated']) {
        expect(
          export,
          contains(
            'revoke execute on function public.export_my_saved_items(uuid) from $role',
          ),
        );
      }
    });
  });

  group('what is kept', () {
    test('only the person\'s own words are stored', () {
      final rpcs = sql['202610250410_saved_items_rpcs']!;
      // Messages, Moments and posts are inserted as references.
      expect(
        rpcs,
        contains(
          "insert into public.saved_items (user_id, kind, target_id, conversation_id)",
        ),
      );
      expect(
        rpcs,
        contains(
          'insert into public.saved_items (user_id, kind, target_id, circle_id)',
        ),
      );
    });

    test('save_message keeps every 202610190011 rule and adds view-once', () {
      final save = body('202610250410_saved_items_rpcs', 'save_message');
      for (final kept in [
        'm.recalled_at is null',
        'm.expires_at is null or m.expires_at > now()',
        'message_visible_to_current_user(m.review_state, m.sender_id, m.conversation_id)',
        'current_user_readable_conversation_ids()',
        "coalesce(m.attachment->>'view_once', '') <> 'true'",
        'assert_saved_room',
      ]) {
        expect(save, contains(kept), reason: kept);
      }
    });

    test(
      'Moments go through the Moments rule and posts through membership',
      () {
        final save = body('202610250410_saved_items_rpcs', 'save_item');
        expect(save, contains('moments_post_visible_to(current_user_id, p)'));
        expect(save, contains('cp.deleted_at is null'));
        expect(save, contains('is_current_user_circle_member(cp.circle_id)'));
        expect(save, contains('circle_is_suspended(cp.circle_id)'));
      },
    );

    test('old apps keep working through a view', () {
      final schema = sql['202610250400_saved_items_schema']!;
      expect(schema, contains('create or replace view public.saved_messages'));
      expect(schema, contains('security_invoker = true'));
      expect(schema, contains('drop table public.saved_messages'));
      expect(
        schema,
        contains('profiles_erase_favorites'),
        reason: 'account deletion',
      );
    });

    test('nothing in these migrations rewrites the shared dispatcher', () {
      for (final text in sql.values) {
        expect(text, isNot(contains('function public.run_later_dispatch')));
      }
    });
  });

  group('the pictures\' bucket', () {
    test('is private, jpeg, 5 MB, and the owner\'s alone', () {
      final bucket = sql['202610250420_saved_notes_bucket']!;
      expect(bucket, contains("'saved-notes'"));
      expect(bucket, contains('false,\n  5242880'));
      expect(bucket, contains("array['image/jpeg']"));
      for (final policy in [
        'saved_notes_select_owner',
        'saved_notes_insert_owner',
        'saved_notes_delete_owner',
      ]) {
        expect(bucket, contains(policy));
      }
      expect(
        RegExp(
          r"\(storage\.foldername\(name\)\)\[1\] = auth\.uid\(\)::text",
        ).allMatches(bucket).length,
        3,
      );
    });
  });

  behaviourTest(
    'favorites 2.0: moving in, keeping, filing, reading, search, export and deleting',
    'test/supabase/favorites2_behaviour.sql',
  );
}

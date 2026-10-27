import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// The whiteboard (D10: migrations 202610281400 to 202610281450): what the
/// SQL says, as text, plus the behaviour script that plays people through it
/// against the local database.
void main() {
  final names = [
    '202610281400_whiteboard_schema.sql',
    '202610281410_whiteboard_versions.sql',
    '202610281420_whiteboard_rpcs.sql',
    '202610281430_whiteboard_files_realtime.sql',
    '202610281440_whiteboard_tabs_guard.sql',
    '202610281450_whiteboard_account.sql',
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
        expect(numbers[i], 202610281400 + i * 10);
      }
      expect(numbers.last, lessThan(202610281500));
    });

    test('the dispatcher and the push claim are not redefined', () {
      expect(all, isNot(contains('function public.run_later_dispatch')));
      expect(all, isNot(contains('function public.claim_push_delivery')));
      expect(all, isNot(contains('function public.send_text_message')));
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });
  });

  group('the tables', () {
    test('elements are read through policies and written only by the RPC', () {
      final schema = sql['202610281400_whiteboard_schema.sql']!;
      expect(schema, contains('alter table public.whiteboards enable row level security'));
      expect(
        schema,
        contains('alter table public.whiteboard_elements enable row level security'),
      );
      expect(schema, isNot(contains('for insert')));
      expect(schema, isNot(contains('for update')));
      expect(schema, isNot(contains('for delete')));
    });

    test('an element is checked: kinds, keys, sizes and ordering key', () {
      final schema = sql['202610281400_whiteboard_schema.sql']!;
      expect(schema, contains("kind in ('stroke', 'shape', 'sticky', 'text', 'image')"));
      expect(schema, contains('z text not null collate "C"'));
      expect(schema, contains('40000'));
      expect(schema, contains('points > 4000'));
      expect(schema, contains('<= 1000'));
      expect(schema, contains('<= 2000'));
    });

    test('both tables are published for Realtime', () {
      final schema = sql['202610281400_whiteboard_schema.sql']!;
      expect(schema, contains('supabase_realtime'));
      expect(schema, contains('whiteboard_elements'));
    });
  });

  group('the functions', () {
    test('every new function is security definer with a pinned search path', () {
      final pattern = RegExp(
        r'create or replace function public\.(\w+)\(([\s\S]*?)\n\$\$;',
      );
      for (final name in names) {
        for (final match in pattern.allMatches(sql[name]!)) {
          final body = match.group(0)!;
          final function = match.group(1)!;
          if (function == 'guard_item_reviews_type' ||
              function == 'guard_item_text' ||
              function == 'guard_items_after_write' ||
              function == 'conversation_tab_target_ok' ||
              function == 'get_conversation_tabs' ||
              function == 'add_conversation_tab') {
            // Patched in place from their latest definitions.
            continue;
          }
          expect(
            body,
            contains('set search_path = public'),
            reason: '$function in $name',
          );
          expect(
            body,
            anyOf(contains('security definer'), contains('immutable')),
            reason: '$function in $name',
          );
        }
      }
    });

    test('the one write path is whiteboard_apply_ops with the limits in it', () {
      final rpcs = sql['202610281420_whiteboard_rpcs.sql']!;
      expect(rpcs, contains('function public.whiteboard_apply_ops'));
      expect(rpcs, contains('> 200'));
      expect(rpcs, contains('live_count >= 3000'));
      expect(rpcs, contains('6000000'));
      expect(rpcs, contains("'conflict'"));
      expect(rpcs, contains('revive'));
      expect(rpcs, contains('can_current_user_edit_whiteboard'));
    });

    test('versions keep the newest eight, automatic ones going first', () {
      final versions = sql['202610281410_whiteboard_versions.sql']!;
      expect(versions, contains('8'));
      expect(versions, contains("kind = 'auto'"));
    });

    test('anonymous callers cannot run the functions', () {
      final rpcs = sql['202610281420_whiteboard_rpcs.sql']!;
      for (final fn in [
        'create_whiteboard',
        'list_whiteboards',
        'get_whiteboard',
        'whiteboard_apply_ops',
        'update_whiteboard_meta',
        'clear_whiteboard',
        'restore_whiteboard_version',
        'delete_whiteboard',
      ]) {
        expect(rpcs, contains('revoke execute on function public.$fn('));
        expect(rpcs, contains('grant execute on function public.$fn('));
      }
    });
  });

  group('pictures and the live channel', () {
    test('the bucket is private, 5 MB, pictures only', () {
      final files = sql['202610281430_whiteboard_files_realtime.sql']!;
      expect(files, contains("'whiteboard-files'"));
      expect(files, contains('5242880'));
      expect(files, contains('false'));
      expect(files, contains('image/jpeg'));
      expect(files, contains('<= 60'));
    });

    test('the live channel lets viewers listen and only editors broadcast', () {
      final files = sql['202610281430_whiteboard_files_realtime.sql']!;
      expect(files, contains("'whiteboard-live-'"));
      expect(files, contains('whiteboard_live_receive'));
      expect(files, contains('whiteboard_live_send'));
      expect(files, contains('can_send_whiteboard_live'));
      expect(files, contains('can_current_user_edit_whiteboard'));
    });
  });

  group('tabs, guard and the account', () {
    test('a tab can point at a board; the guard reads the board name', () {
      final tabs = sql['202610281440_whiteboard_tabs_guard.sql']!;
      expect(tabs, contains("'whiteboard'"));
      expect(tabs, contains('conversation_tab_kinds'));
      expect(tabs, contains('guard_items_whiteboards_ins'));
      expect(tabs, contains('pg_get_functiondef'));
    });

    test('deleting an account removes its boards and the export is its own', () {
      final account = sql['202610281450_whiteboard_account.sql']!;
      expect(account, contains('erase_whiteboards_of_deleted_account'));
      expect(account, contains('export_my_whiteboards'));
      expect(account, contains('service_role'));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/whiteboard_behaviour.sql',
  );
}

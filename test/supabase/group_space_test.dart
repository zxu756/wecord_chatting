import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// The group space (B6: migrations 202610280200 to 202610280230): what the SQL
/// says, as text, plus the behaviour script that plays people through it
/// against the local database.
void main() {
  final names = [
    '202610280200_group_space_schema.sql',
    '202610280210_group_space_albums.sql',
    '202610280220_group_space_folders.sql',
    '202610280230_group_space_account.sql',
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
        expect(numbers[i], 202610280200 + i * 10);
      }
      expect(numbers.last, lessThan(202610280300));
    });

    test('no existing function is rewritten', () {
      // The only things that touch the older machinery are a trigger on the
      // queue of deleted files and new functions of the space's own.
      for (final old in [
        'recall_message',
        'list_conversation_media',
        'run_later_dispatch',
        'wake_scheduled_dispatch',
        'can_current_user_delete_recalled_media',
        'remember_conversation_media',
        'purge_expired_messages',
        'forward_message',
        'set_disappearing_messages',
        'prepare_account_deletion',
      ]) {
        expect(
          all,
          isNot(contains('create or replace function public.$old(')),
          reason: old,
        );
      }
      expect(all, isNot(contains('cron.schedule')));
    });

    test('nothing reintroduces a bare bio', () {
      expect(all, isNot(matches(RegExp(r"'bio',\s*\w+\.bio\b"))));
      expect(all, isNot(matches(RegExp(r'\n\s*\w+\.bio,\n'))));
    });

    test('no new storage bucket and no storage policy', () {
      // Uploads go in the chat buckets under <chat>/space/, which their
      // policies already cover.
      expect(all, isNot(contains('storage.buckets')));
      expect(all, isNot(contains('on storage.objects')));
    });
  });

  group('who may do what', () {
    test('every table is closed to clients', () {
      final schema = sql['202610280200_group_space_schema.sql']!;
      for (final table in [
        'conversation_albums',
        'album_items',
        'conversation_folders',
        'folder_files',
      ]) {
        expect(
          schema,
          contains('alter table public.$table enable row level security;'),
          reason: table,
        );
        expect(
          schema,
          contains(
            'revoke all on public.$table from public, anon, authenticated;',
          ),
          reason: table,
        );
      }
      expect(all, isNot(contains('create policy')));
    });

    test('one function decides who may touch the space', () {
      final access = body(
        '202610280200_group_space_schema.sql',
        'group_space_access',
      );
      expect(access, contains("conversation.type <> 'group'"));
      expect(access, contains('is_current_user_conversation_member'));
      expect(access, contains('is_user_suspended(current_user_id)'));
      expect(access, contains('can_current_user_send_in_conversation'));
      expect(access, contains('disappear_after_seconds is not null'));
      expect(access, contains("cm.role in ('owner', 'admin')"));
    });

    test('every write goes through it', () {
      for (final entry in {
        '202610280210_group_space_albums.sql': [
          'create_group_album',
          'add_album_items_from_messages',
          'add_album_upload',
          'remove_album_item',
          'set_album_item_alt',
          'list_album_items',
          'list_group_albums',
          'list_group_event_album',
          'group_space_album_for_change',
        ],
        '202610280220_group_space_folders.sql': [
          'create_group_folder',
          'add_folder_files_from_messages',
          'add_folder_upload',
          'list_folder_files',
          'list_group_folders',
          'group_space_folder_for_change',
          'group_space_file_for_change',
        ],
      }.entries) {
        for (final function in entry.value) {
          expect(
            body(entry.key, function),
            contains('group_space_access('),
            reason: function,
          );
        }
      }
    });

    test('changing needs the person who made it or an admin', () {
      for (final (file, function) in [
        ('202610280210_group_space_albums.sql', 'group_space_album_for_change'),
        ('202610280210_group_space_albums.sql', 'remove_album_item'),
        ('202610280210_group_space_albums.sql', 'set_album_item_alt'),
        (
          '202610280220_group_space_folders.sql',
          'group_space_folder_for_change',
        ),
        ('202610280220_group_space_folders.sql', 'group_space_file_for_change'),
      ]) {
        expect(
          body(file, function),
          contains('Only the person who made it or a group admin can do this'),
          reason: function,
        );
      }
    });

    test('adding is for people who may send, and not while a timer is on', () {
      for (final function in [
        'create_group_album',
        'add_album_items_from_messages',
        'add_album_upload',
      ]) {
        expect(
          body('202610280210_group_space_albums.sql', function),
          contains("'add'"),
          reason: function,
        );
      }
      for (final function in [
        'create_group_folder',
        'add_folder_files_from_messages',
        'add_folder_upload',
      ]) {
        expect(
          body('202610280220_group_space_folders.sql', function),
          contains("'add'"),
          reason: function,
        );
      }
    });

    test('what cannot be kept is refused', () {
      for (final (file, function) in [
        (
          '202610280210_group_space_albums.sql',
          'add_album_items_from_messages',
        ),
        (
          '202610280220_group_space_folders.sql',
          'add_folder_files_from_messages',
        ),
      ]) {
        final source = body(file, function);
        expect(
          source,
          contains('message.recalled_at is null'),
          reason: function,
        );
        expect(
          source,
          contains('message.expires_at is null'),
          reason: function,
        );
        expect(
          source,
          contains('message.review_state is null'),
          reason: function,
        );
        expect(source, contains("'view_once'"), reason: function);
        expect(source, contains("message.attachment->>'path' ~ '\\.\\.'"));
        expect(source, contains("not like"), reason: function);
        expect(source, contains('cardinality(p_message_ids) > 50'));
      }
    });

    test('uploads must be under <chat>/space/ and really in Storage', () {
      for (final (file, function) in [
        ('202610280210_group_space_albums.sql', 'add_album_upload'),
        ('202610280220_group_space_folders.sql', 'add_folder_upload'),
      ]) {
        final source = body(file, function);
        expect(source, contains('/space/[^/]+\$'), reason: function);
        expect(source, contains('storage.objects'), reason: function);
        expect(source, contains("p_path ~ '\\.\\.'"), reason: function);
        expect(source, contains('2147483648'), reason: function);
      }
    });

    test('blocked people\'s entries are left out of lists and counts', () {
      for (final (file, function) in [
        ('202610280210_group_space_albums.sql', 'list_group_albums'),
        ('202610280210_group_space_albums.sql', 'list_album_items'),
        ('202610280210_group_space_albums.sql', 'list_group_event_album'),
        ('202610280220_group_space_folders.sql', 'list_group_folders'),
        ('202610280220_group_space_folders.sql', 'list_folder_files'),
      ]) {
        expect(
          body(file, function),
          contains('are_users_blocked'),
          reason: function,
        );
      }
    });

    test('grants: signed-in people call the RPCs, helpers stay internal', () {
      for (final function in [
        'get_group_space(uuid)',
        'create_group_album(uuid, text)',
        'add_album_items_from_messages(uuid, uuid[])',
        'delete_group_album(uuid)',
        'list_group_folders(uuid)',
        'add_folder_upload(uuid, uuid, text, text, text, text, bigint)',
        'remove_folder_file(uuid)',
      ]) {
        expect(all, contains('grant execute on function public.$function'));
      }
      expect(
        sql['202610280200_group_space_schema.sql'],
        contains(
          'revoke execute on function public.group_space_access(uuid, text)\n  from public, anon, authenticated;',
        ),
      );
      expect(
        sql['202610280230_group_space_account.sql'],
        contains(
          'grant execute on function public.export_my_group_space(uuid) to service_role;',
        ),
      );
    });
  });

  group('keeping the files', () {
    test('a deleted message\'s file stays while the space names it', () {
      final schema = sql['202610280200_group_space_schema.sql']!;
      expect(
        schema,
        contains('before insert on public.recalled_message_media'),
      );
      final trigger = body(
        '202610280200_group_space_schema.sql',
        'recalled_media_keep_space_files',
      );
      expect(trigger, contains('group_space_file_in_use'));
      expect(trigger, contains('return null;'));
    });

    test('the file goes when the last entry goes, and not before', () {
      final release = body(
        '202610280200_group_space_schema.sql',
        'group_space_release_files',
      );
      expect(release, contains('group_space_file_in_use'));
      expect(release, contains("m.attachment->>'path' = candidate.p"));
      expect(release, contains('event_photos'));
      expect(release, contains('insert into public.recalled_message_media'));
      for (final (file, function) in [
        ('202610280210_group_space_albums.sql', 'remove_album_item'),
        ('202610280210_group_space_albums.sql', 'delete_group_album'),
        ('202610280220_group_space_folders.sql', 'remove_folder_file'),
        ('202610280220_group_space_folders.sql', 'delete_group_folder'),
      ]) {
        expect(
          body(file, function),
          contains('group_space_release_files'),
          reason: function,
        );
      }
    });
  });

  group('account and export', () {
    test(
      'deleting an account takes the name off, the group keeps its things',
      () {
        final account = sql['202610280230_group_space_account.sql']!;
        final detach = body(
          '202610280230_group_space_account.sql',
          'detach_group_space_of_deleted_account',
        );
        expect(detach, contains('set added_by = null'));
        expect(detach, contains('set created_by = null'));
        expect(detach, isNot(contains('delete from')));
        expect(
          account,
          contains('after update of deleted_at on public.profiles'),
        );
        expect(
          account,
          isNot(contains('function public.prepare_account_deletion')),
        );
      },
    );

    test('the export holds only the person\'s own', () {
      final export = body(
        '202610280230_group_space_account.sql',
        'export_my_group_space',
      );
      expect(export, contains('x.created_by = target_user_id'));
      expect(export, contains('x.added_by = target_user_id'));
      // The group's title only while the person is still in it.
      expect(export, contains('m.user_id is not null'));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/group_space_behaviour.sql',
  );
}

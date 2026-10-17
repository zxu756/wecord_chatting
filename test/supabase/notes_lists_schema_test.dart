import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for Notes and Lists (migrations 202610170060 to 065).
void main() {
  late Map<String, String> sql;

  setUpAll(() {
    final files = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .where((file) {
          final name = file.uri.pathSegments.last;
          return RegExp(r'^2026101700(6[0-5])_').hasMatch(name);
        });
    sql = {
      for (final file in files)
        file.uri.pathSegments.last.substring(0, 12): file.readAsStringSync(),
    };
  });

  test('six migrations, numbered 060 to 065', () {
    expect(sql.keys.toList()..sort(), [
      '202610170060',
      '202610170061',
      '202610170062',
      '202610170063',
      '202610170064',
      '202610170065',
    ]);
  });

  test('every table is read-only to clients with row level security', () {
    final all = sql.values.join('\n');
    for (final table in [
      'notes',
      'note_blocks',
      'note_versions',
      'task_lists',
      'task_items',
      'task_item_assignees',
      'task_notifications',
    ]) {
      expect(
        all,
        contains('alter table public.$table enable row level security'),
        reason: table,
      );
      expect(
        all,
        contains('revoke all on public.$table from anon, authenticated'),
        reason: table,
      );
    }
    // Nobody may write a table directly.
    expect(all, isNot(contains('grant insert')));
    expect(all, isNot(contains('grant update')));
    expect(all, isNot(contains('grant delete')));
  });

  test('viewing follows the conversation, editing follows sending', () {
    final notes = sql['202610170060']!;
    expect(
      notes,
      contains('public.is_current_user_conversation_member(conversation_id)'),
    );
    expect(
      notes,
      contains('public.can_current_user_write_docs(n.conversation_id)'),
    );
    expect(
      notes,
      contains('public.can_current_user_send_in_conversation('),
      reason: 'writing needs send_messages',
    );
    expect(
      notes,
      contains('public.can_current_user_moderate_messages(n.conversation_id)'),
    );
    // "Only managers can edit" and pinning need a manager.
    expect(notes, contains("raise exception 'Only managers can change this'"));
  });

  test('blocks use fractional keys in C collation and revisions', () {
    final notes = sql['202610170060']!;
    expect(notes, contains('pos text not null collate "C"'));
    expect(notes, contains("pos ~ '^[0-9A-Za-z]{1,64}\$'"));
    expect(notes, contains('rev integer not null default 1'));
    expect(notes, contains("'status', 'conflict'"));
    expect(notes, contains('deleted boolean not null default false'));
  });

  test('the note-files bucket is private and mirrors chat files', () {
    final files = sql['202610170061']!;
    expect(files, contains("'note-files', 'note-files', false"));
    expect(files, contains('note_files_select_member'));
    expect(files, contains('note_files_insert_editor'));
    expect(files, contains('can_current_user_edit_note'));
    expect(files, contains('note_files_delete_deleted_note'));
  });

  test('realtime streams notes, blocks, lists and items', () {
    final all = sql.values.join('\n');
    expect(all, contains("tablename = 'note_blocks'"));
    expect(all, contains("'task_lists', 'task_items', 'task_item_assignees'"));
  });

  test('due reminders and the assignment claim are service-role only', () {
    final notifications = sql['202610170063']!;
    expect(
      notifications,
      contains(
        'revoke execute on function public.due_list_item_reminders() '
        'from public, anon, authenticated',
      ),
    );
    expect(
      notifications,
      contains(
        'grant execute on function public.due_list_item_reminders() '
        'to service_role',
      ),
    );
    expect(
      notifications,
      contains(
        'grant execute on function '
        'public.claim_task_assignment_push(uuid, uuid) to service_role',
      ),
    );
    // Reminded once per person, item and due date.
    expect(notifications, contains('task_notifications_due_once_idx'));
  });

  test('every function runs with a fixed search path', () {
    final all = sql.values.join('\n');
    final definitions = RegExp(
      r'create or replace function public\.\w+\([\s\S]*?\n\$\$;',
    ).allMatches(all);
    expect(definitions, isNotEmpty);
    for (final match in definitions) {
      final text = match.group(0)!;
      expect(text, contains('set search_path = public'), reason: text);
    }
  });
}

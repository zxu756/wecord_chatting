import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// The circle knowledge base (D6: migrations 202610270100 to 202610270130):
/// what the SQL says, as text, plus the behaviour script that plays people
/// through it against the local database.
void main() {
  late String schema;
  late String rpcs;
  late String reading;
  late String account;

  setUpAll(() {
    String read(String name) =>
        File('supabase/migrations/$name').readAsStringSync();
    schema = read('202610270100_kb_schema.sql');
    rpcs = read('202610270110_kb_rpcs.sql');
    reading = read('202610270120_kb_required_reading.sql');
    account = read('202610270130_kb_account.sql');
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('a page is a note of the circle', () {
    test('a note has exactly one home and pages are plain', () {
      expect(schema, contains('alter column conversation_id drop not null'));
      expect(
        schema,
        contains('check ((conversation_id is null) <> (circle_id is null))'),
      );
      expect(
        schema,
        contains('circle_id is null or (not pinned and not managers_only)'),
      );
      expect(schema, contains('cardinality(view_role_ids) <= 10'));
    });

    test('the tree is checked whatever writes it', () {
      final check = body(schema, 'kb_check_page_tree');
      expect(check, contains('A page cannot be inside itself'));
      expect(check, contains('Pages can be nested 5 levels deep'));
      expect(schema, contains('create trigger notes_kb_check_tree'));
    });

    test('reads are recorded in a table closed to clients', () {
      expect(
        schema,
        contains('create table if not exists public.circle_kb_reads'),
      );
      expect(
        schema,
        contains(
          'revoke all on public.circle_kb_reads from public, anon, authenticated',
        ),
      );
    });
  });

  group('who may do what', () {
    test('access comes from the circle: a member reads, managers write', () {
      final access = body(schema, 'kb_user_access');
      expect(access, contains('circle_is_suspended(home)'));
      expect(access, contains('is_user_suspended(p_user)'));
      expect(access, contains("circle_permission_bit('manage_channels')"));
      expect(access, contains('timed_out_until'));
      expect(access, contains('view_role_ids'));
      expect(access, contains('edit_role_ids'));
    });

    test('the note checks and the table policy know pages', () {
      expect(
        body(schema, 'can_current_user_view_note'),
        contains('kb_user_access(n.id, auth.uid()) >= 1'),
      );
      expect(
        body(schema, 'can_current_user_edit_note'),
        contains('kb_user_access(n.id, auth.uid()) >= 2'),
      );
      expect(
        body(schema, 'can_current_user_manage_note'),
        contains('kb_is_manager'),
      );
      expect(schema, contains('create policy notes_select_member'));
      expect(schema, contains('kb_user_access(id, auth.uid()) >= 1'));
    });

    test('the other note functions are patched in place, not rewritten', () {
      expect(schema, contains('pg_get_functiondef(fn::regprocedure)'));
      for (final fn in [
        'public.get_note(uuid)',
        'public.update_note_meta(uuid, jsonb)',
        'public.note_apply_ops(uuid, jsonb)',
        'public.create_note_version(uuid, text)',
        'public.restore_note_version(uuid)',
      ]) {
        expect(schema, contains("'$fn'"), reason: fn);
      }
      expect(
        schema,
        contains("pg_get_functiondef('public.guard_items_after_write()'"),
      );
      expect(schema, contains('changed shape; patch it by hand'));
      expect(
        schema,
        isNot(contains('create or replace function public.note_apply_ops(')),
      );
      expect(
        schema,
        isNot(contains('create or replace function public.get_note(')),
      );
    });

    test('nothing here rewrites the scheduler', () {
      for (final sql in [schema, rpcs, reading, account]) {
        expect(sql, isNot(contains('run_later_dispatch')));
      }
    });
  });

  group('the calls', () {
    test('members and managers get the right grants', () {
      for (final signature in [
        'kb_list_pages(uuid)',
        'kb_mark_read(uuid)',
        'kb_search(uuid, text, integer)',
        'kb_create_page(uuid, uuid, text, text, uuid)',
        'kb_move_page(uuid, uuid, uuid)',
        'kb_delete_page(uuid)',
        'kb_get_page_access(uuid)',
        'kb_set_page_access(uuid, uuid[], uuid[])',
      ]) {
        expect(
          rpcs,
          contains(
            'revoke execute on function public.$signature from public, anon;',
          ),
          reason: signature,
        );
        expect(
          rpcs,
          contains(
            'grant execute on function public.$signature to authenticated;',
          ),
          reason: signature,
        );
      }
      expect(rpcs, isNot(contains('to anon')));
    });

    test('managers only change the tree, and rank is checked', () {
      for (final fn in [
        'kb_move_page',
        'kb_delete_page',
        'kb_set_page_access',
      ]) {
        final sql = body(rpcs, fn);
        expect(sql, contains('kb_is_manager'), reason: fn);
        expect(sql, contains('kb_lock_rank'), reason: fn);
        expect(sql, contains('circle_member_rank'), reason: fn);
      }
      expect(body(rpcs, 'kb_set_page_access'), contains('not r.is_default'));
    });

    test('every change of the tree is audited', () {
      expect(rpcs, contains("'kb_page_create'"));
      expect(rpcs, contains("'kb_page_move'"));
      expect(rpcs, contains("'kb_page_delete'"));
      expect(rpcs, contains("'kb_page_access'"));
    });

    test('a suspended circle refuses writes', () {
      expect(body(rpcs, 'kb_create_page'), contains('circle_is_suspended'));
      expect(body(rpcs, 'kb_list_pages'), contains('circle_is_suspended'));
    });
  });

  group('required reading', () {
    test('patches the three guide functions from their newest definitions', () {
      for (final fn in [
        'public.get_circle_guide(uuid)',
        'public.get_circle_guide_config(uuid)',
        'public.set_circle_guide_tasks(uuid, jsonb)',
      ]) {
        expect(reading, contains("pg_get_functiondef('$fn'"), reason: fn);
      }
      expect(reading, contains("'read_page'"));
      expect(reading, contains('kb_user_access'));
      expect(
        schema,
        contains("(action = 'read_page') = (page_id is not null)"),
      );
    });
  });

  group('leaving and exporting', () {
    test('deleting an account erases what was read; the export is closed', () {
      expect(
        account,
        contains('delete from public.circle_kb_reads where user_id = new.id'),
      );
      expect(account, contains('create trigger profiles_erase_kb'));
      expect(
        account,
        contains(
          'grant execute on function public.export_my_knowledge(uuid) to service_role;',
        ),
      );
      expect(
        account,
        contains(
          'revoke execute on function public.export_my_knowledge(uuid) from public, anon, authenticated;',
        ),
      );
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/knowledge_base_behaviour.sql',
  );
}

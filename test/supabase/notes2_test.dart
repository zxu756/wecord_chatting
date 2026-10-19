import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for notes 2.0 (migrations 202610240300 to 202610240340),
/// plus the behaviour script: tables in notes, comments (who reads, writes,
/// edits, deletes and resolves; members only; blocks; a suspended circle;
/// quotations; mentions), personal templates, pages on the web (only
/// editors; the token; withdrawing; dead links look alike; nothing lists
/// tokens) and the account (erasing, the export).
void main() {
  late String tables;
  late String comments;
  late String templates;
  late String publish;
  late String account;

  setUpAll(() {
    String read(String name) =>
        File('supabase/migrations/$name').readAsStringSync();
    tables = read('202610240300_notes_tables.sql');
    comments = read('202610240310_note_comments.sql');
    templates = read('202610240320_note_templates.sql');
    publish = read('202610240330_note_publish.sql');
    account = read('202610240340_notes2_account.sql');
  });

  group('the tables', () {
    test('hard-code no user id', () {
      final uuid = RegExp(
        r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
      );
      for (final sql in [tables, comments, templates, publish, account]) {
        expect(uuid.hasMatch(sql), isFalse);
      }
    });

    test('are closed to the API; members may only read comments', () {
      for (final table in ['note_comments']) {
        expect(
          comments,
          contains('alter table public.$table enable row level security'),
        );
        expect(
          comments,
          contains('revoke all on public.$table from anon, authenticated'),
        );
      }
      expect(
        comments,
        contains('grant select on public.note_comments to authenticated'),
      );
      for (final sql in [comments, templates, publish]) {
        expect(sql, isNot(contains('grant insert')));
        expect(sql, isNot(contains('grant update')));
        expect(sql, isNot(contains('grant delete')));
      }
      for (final table in [
        'note_templates',
        'note_publications',
        'note_comment_notifications',
      ]) {
        final sql = [comments, templates, publish].join();
        expect(
          sql,
          contains('alter table public.$table enable row level security'),
        );
        expect(
          sql,
          contains('revoke all on public.$table from anon, authenticated'),
        );
        expect(sql, isNot(contains('grant select on public.$table')));
      }
    });

    test('the comment policy asks the note\'s rules and the blocks', () {
      expect(comments, contains('public.can_current_user_view_note(note_id)'));
      expect(
        comments,
        contains(
          'public.note_comment_visible_to(author_id, parent_id, auth.uid())',
        ),
      );
      expect(comments, contains('public.are_users_blocked(viewer, author)'));
      expect(comments, contains('public.can_current_user_write_docs'));
    });

    test('block rules live in one place, which note_apply_ops asks', () {
      expect(
        tables,
        contains('create or replace function public.note_block_is_valid('),
      );
      expect(
        tables,
        contains(
          'public.note_block_is_valid(new_kind, new_text, new_marks, new_props, new_pos)',
        ),
      );
      expect(tables, contains("'code', 'divider', 'image', 'table'"));
      expect(tables, contains('length(p_props::text) <= 60000'));
      expect(templates, contains('public.note_block_is_valid('));
    });

    test('the scrub triggers empty a deleted table', () {
      expect(
        tables,
        contains(
          "props = case when kind = 'table' then '{}'::jsonb else props end",
        ),
      );
      expect(tables, contains("if new.kind = 'table' then"));
    });
  });

  group('the web page', () {
    test(
      'the token is 192 random bits and the lookup is for the service role only',
      () {
        expect(
          publish,
          contains("encode(extensions.gen_random_bytes(24), 'hex')"),
        );
        expect(publish, contains("token ~ '^[0-9a-f]{48}\$'"));
        expect(
          publish,
          contains(
            'revoke execute on function public.public_note_by_token(text) from public, anon, authenticated',
          ),
        );
        expect(
          publish,
          contains(
            'grant execute on function public.public_note_by_token(text) to service_role',
          ),
        );
      },
    );

    test('goes dead with the note, the circle and the publisher', () {
      expect(publish, contains('n.deleted_at is null'));
      expect(
        publish,
        contains(
          'public.note_user_can_view(pub.published_by, n.conversation_id)',
        ),
      );
      expect(
        comments,
        contains('public.conversation_in_suspended_circle(p_conversation_id)'),
      );
      expect(publish, contains('after update of deleted_at on public.notes'));
    });

    test('hands out only what a page needs', () {
      expect(publish, contains('public.note_marks_without_mentions(b.marks)'));
      expect(publish, contains('public.note_public_props(b.kind, b.props)'));
      for (final leak in ['created_by', 'updated_by', 'author', 'comment']) {
        final body = publish.substring(
          publish.indexOf(
            'create or replace function public.public_note_by_token',
          ),
        );
        expect(
          body.substring(0, body.indexOf('-- A deleted note is withdrawn')),
          isNot(contains("'$leak'")),
          reason: leak,
        );
      }
    });

    test('publishing needs edit rights', () {
      final body = publish.substring(
        publish.indexOf('create or replace function public.publish_note('),
      );
      expect(body, contains('public.can_current_user_edit_note(n.id)'));
    });
  });

  group('the account', () {
    test('erases what the person wrote, and exports it without the link', () {
      expect(
        account,
        contains('after update of deleted_at on public.profiles'),
      );
      for (final erased in [
        'delete from public.note_comments where author_id = new.id',
        'delete from public.note_templates where owner_id = new.id',
        'delete from public.note_publications where published_by = new.id',
      ]) {
        expect(account, contains(erased));
      }
      expect(account, isNot(contains('pub.token')));
      expect(
        account,
        contains(
          'revoke execute on function public.export_my_note_extras(uuid) from public, anon, authenticated',
        ),
      );
      expect(
        account,
        contains(
          'grant execute on function public.export_my_note_extras(uuid) to service_role',
        ),
      );
    });
  });

  behaviourTest(
    'notes 2.0: tables, comments, templates, pages on the web, the account',
    'test/supabase/notes2_behaviour.sql',
  );
}

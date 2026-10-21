import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Media channels and Q&A channels (C9: migrations 202610270300 to
/// 202610270330): what the SQL says, as text, plus the behaviour script that
/// plays people through it against the local database.
void main() {
  late String schema;
  late String solved;
  late String media;
  late String export;

  setUpAll(() {
    String read(String name) =>
        File('supabase/migrations/$name').readAsStringSync();
    schema = read('202610270300_channel_types_schema.sql');
    solved = read('202610270310_qa_solved.sql');
    media = read('202610270320_media_channel_posts.sql');
    export = read('202610270330_channel_posts_export.sql');
  });

  String body(String sql, String name) {
    final start = sql.indexOf('create or replace function public.$name(');
    expect(start, isNonNegative, reason: name);
    return sql.substring(start, sql.indexOf('\n\$\$;', start));
  }

  group('the kinds', () {
    test('keep every kind the table already allowed', () {
      // Like the stage migration: the existing list is read, then extended.
      expect(schema, contains("pg_get_constraintdef(c.oid)"));
      expect(
        schema,
        contains(
          "array['text', 'voice', 'forum', 'stage', 'announcement', 'media', 'qa']",
        ),
      );
      expect(
        schema,
        contains(
          'create or replace function public.circle_channel_kind_has_posts',
        ),
      );
      expect(schema, contains("channel_kind in ('forum', 'media', 'qa')"));
    });

    test(
      'every function that branched on the forum kind is patched in place',
      () {
        for (final name in [
          'check_channel_message_send',
          'circle_alert_channel',
          'circle_automod_act',
          'create_circle_from_template',
          'create_forum_post',
          'create_thread',
          'forum_channel_for_management',
          'list_forum_posts',
          'pin_forum_post',
          'save_circle_automod_rule',
          'set_forum_post_tags',
        ]) {
          expect(schema, contains("'$name'"), reason: name);
          // Patched from the current definition, never rewritten here.
          expect(
            schema,
            isNot(contains('create or replace function public.$name(')),
            reason: name,
          );
        }
        expect(schema, contains('pg_get_functiondef(target.oid)'));
        expect(schema, contains('circle_channel_kind_has_posts'));
        expect(schema, contains("''media'', ''qa''"));
      },
    );

    test('no function other migrations patched is rewritten', () {
      for (final sql in [schema, solved, media, export]) {
        for (final name in [
          'forum_post_payload',
          'check_channel_message_send',
          'create_forum_post',
          'create_circle_channel',
          'get_circle_detail',
          'run_later_dispatch',
          'prepare_account_deletion',
        ]) {
          expect(
            sql,
            isNot(contains('create or replace function public.$name(')),
            reason: name,
          );
        }
      }
    });

    test('forum_post_payload is patched, with the bio rule untouched', () {
      expect(solved, contains("pg_get_functiondef(target.oid)"));
      expect(
        solved,
        contains("''solved_message_id'', thread_row.solved_message_id"),
      );
      expect(solved, isNot(contains('.bio')));
    });
  });

  group('solving', () {
    test('who may mark a question', () {
      final can = body(solved, 'qa_can_mark_solved');
      expect(can, contains("'manage_messages'"));
      expect(can, contains("'view_channel'"));
      expect(can, contains('timed_out_until'));
      expect(can, contains('locked_at is null'));
      expect(can, contains('disabled_at is not null'));
      expect(can, contains('is_user_suspended'));
      expect(can, contains('circle_members'));
    });

    test('which messages can be the answer', () {
      final valid = body(solved, 'qa_answer_is_valid');
      expect(valid, contains("m.type <> 'system'"));
      expect(valid, contains('m.recalled_at is null'));
      expect(valid, contains('m.review_state is null'));
      expect(valid, contains('m.expires_at'));
      expect(valid, contains('view_once'));
      expect(valid, contains('qa_opening_message_id'));
    });

    test('marking is audited and tells the right people once', () {
      final mark = body(solved, 'mark_post_solved');
      expect(mark, contains("'forum_post_solved'"));
      expect(mark, contains("'answer_accepted'"));
      expect(mark, contains("'marked_solved'"));
      expect(mark, contains('wake_scheduled_dispatch'));
      expect(mark, contains('for update'));
      expect(body(solved, 'reopen_qa_post'), contains("'forum_post_reopened'"));
      final notice = body(solved, 'qa_queue_notice');
      expect(notice, contains('are_users_blocked'));
      expect(notice, contains("interval '1 day'"));
      expect(notice, contains('p.is_bot'));
    });

    test('the grants', () {
      for (final signature in [
        'mark_post_solved(uuid, uuid)',
        'reopen_qa_post(uuid)',
        'get_qa_post_state(uuid)',
      ]) {
        expect(
          solved,
          contains(
            'grant execute on function public.$signature to authenticated;',
          ),
          reason: signature,
        );
      }
      expect(solved, isNot(contains('to anon')));
      expect(
        solved,
        contains(
          'grant execute on function public.claim_qa_answer_pushes() to service_role;',
        ),
      );
      for (final helper in [
        'qa_can_mark_solved',
        'qa_opening_message_id',
        'qa_answer_is_valid',
        'qa_queue_notice',
      ]) {
        expect(solved, contains('revoke execute on function public.$helper('));
      }
    });

    test('the push is worded in both languages and cleans names', () {
      final push = body(solved, 'claim_qa_answer_pushes');
      expect(push, contains("s.language = 'zh'"));
      expect(push, contains('你的回答被采纳了'));
      expect(push, contains('你的问题已解决'));
      expect(push, contains("replace(replace(ct.title, '<', ''), '>', '')"));
      expect(push, contains('ci.disabled_at is null'));
    });
  });

  group('media posts', () {
    test('need a picture', () {
      expect(
        media,
        contains("channel.kind = ''media'' and post_attachment is null"),
      );
      expect(media, contains('needs a picture'));
      expect(media, contains('pg_get_functiondef(target.oid)'));
    });
  });

  group('what is stored', () {
    test('the waiting pushes are closed to clients', () {
      expect(
        schema,
        contains(
          'alter table public.qa_answer_notices enable row level security;',
        ),
      );
      expect(
        schema,
        contains(
          'revoke all on public.qa_answer_notices from public, anon, authenticated;',
        ),
      );
      expect(schema, isNot(contains('create policy')));
    });

    test('leaving and deleting an account erase it', () {
      expect(
        schema,
        contains('create trigger circle_members_forget_qa_notices'),
      );
      expect(schema, contains('after delete on public.circle_members'));
      expect(schema, contains('create trigger profiles_erase_qa'));
      expect(schema, contains('after update of deleted_at on public.profiles'));
      final erase = body(schema, 'erase_qa_of_deleted_account');
      expect(erase, contains('delete from public.qa_answer_notices'));
      expect(erase, contains('set solved_by = null'));
    });

    test('a solved mark has a time before it has an answer', () {
      expect(
        schema,
        contains('solved_message_id is null or solved_at is not null'),
      );
      expect(schema, contains('on delete set null'));
    });
  });

  group('exporting', () {
    test('the export is closed to clients and holds only my own', () {
      expect(
        export,
        contains(
          'grant execute on function public.export_my_channel_posts(uuid) to service_role;',
        ),
      );
      expect(
        export,
        contains(
          'revoke execute on function public.export_my_channel_posts(uuid)\n  from public, anon, authenticated;',
        ),
      );
      final fn = body(export, 'export_my_channel_posts');
      expect(fn, contains('ct.created_by = target_user_id'));
      expect(fn, contains('m.sender_id = target_user_id'));
      // The title of somebody else's question is their words.
      final accepted = fn.substring(fn.indexOf("'accepted_answers'"));
      expect(accepted, isNot(contains('ct.title')));
    });
  });

  behaviourTest(
    'the behaviour script passes',
    'test/supabase/channel_types_behaviour.sql',
  );
}

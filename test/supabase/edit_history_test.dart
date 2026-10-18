import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for edit history and re-review after edits, plus the
/// behaviour script.
void main() {
  late String history;
  late String review;
  late String window;

  setUpAll(() {
    history = File(
      'supabase/migrations/202610220210_message_edit_history.sql',
    ).readAsStringSync();
    review = File(
      'supabase/migrations/202610220220_edit_review.sql',
    ).readAsStringSync();
    window = File(
      'supabase/migrations/202610220230_circle_edit_window.sql',
    ).readAsStringSync();
  });

  test('the edit time limit is a trigger and a managers-only setter', () {
    expect(window, contains('edit_window_seconds in (900, 3600, 86400)'));
    expect(window, isNot(contains('function public.edit_message')));
    expect(window, contains('create trigger messages_enforce_edit_window'));
    expect(window, contains("'manage_circle'"));
    expect(
      window,
      contains(
        'revoke execute on function public.set_circle_edit_window(uuid, integer) from public, anon;',
      ),
    );
    expect(window, contains("'edit_window_update'"));
  });

  test('the history is read-only for clients and follows the message', () {
    expect(history, contains('alter table public.message_edits enable row'));
    expect(
      history,
      contains('revoke all on public.message_edits from anon, authenticated;'),
    );
    expect(
      history,
      contains('grant select on public.message_edits to authenticated;'),
    );
    // Cleaned with the message by the foreign key.
    expect(
      history,
      contains('references public.messages(id) on delete cascade'),
    );
    // Read through the messages table's own policy as the caller.
    expect(
      history,
      contains('select 1 from public.messages m where m.id = message_edits.'),
    );
  });

  test('versions are written by a trigger, edit_message is not redefined', () {
    expect(history, contains('create trigger messages_edit_history'));
    expect(history, contains('before update of body, recalled_at'));
    expect(history, isNot(contains('function public.edit_message')));
    expect(review, isNot(contains('function public.edit_message')));
    // Recall deletes the history and does not keep the blanked body.
    expect(history, contains('if new.recalled_at is not null then'));
    expect(history, contains('delete from public.message_edits e'));
    // Search is untouched.
    expect(
      history,
      isNot(contains('function public.sync_message_search_entry')),
    );
  });

  test('an edit goes back through the guard without redefining it', () {
    for (final function in [
      'messages_review_guard',
      'messages_review_open',
      'finish_message_review',
      'ai_guard_release_message',
      'run_ai_guard_sweep',
    ]) {
      expect(
        review,
        isNot(contains('create or replace function public.$function(')),
        reason: function,
      );
    }
    expect(review, contains('create trigger messages_review_recheck_edit'));
    expect(review, contains('create trigger messages_review_recheck_open'));
    // Sorts after the lock so a waiting message still cannot be edited.
    expect(
      'messages_review_recheck_edit'.compareTo('messages_review_lock_edit'),
      greaterThan(0),
    );
    expect(review, contains('ai_guard_wake('));
    expect(review, contains("'action', 'guard'"));
    expect(review, contains("'not_checked', null, 'unavailable'"));
  });

  behaviourTest(
    'history, visibility, cleanup paths and re-review after an edit',
    'test/supabase/edit_history_behaviour.sql',
  );
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Advanced chat privacy (G6) and screenshot reports of view-once media (G7),
/// migrations 202610280900 to 202610280940: what the files promise, and the
/// behaviour script that runs them against the local database.
void main() {
  late String schema;
  late String rpc;
  late String enforce;
  late String screenshots;
  late String account;

  String read(String name) =>
      File('supabase/migrations/$name').readAsStringSync();

  setUpAll(() {
    schema = read('202610280900_chat_privacy_schema.sql');
    rpc = read('202610280910_chat_privacy_rpc.sql');
    enforce = read('202610280920_chat_privacy_enforce.sql');
    screenshots = read('202610280930_view_once_screenshots.sql');
    account = read('202610280940_chat_privacy_account.sql');
  });

  test('the flag is a plain column with a cap on who asked', () {
    expect(
      schema,
      contains(
        'add column if not exists restrict_sharing boolean not null default false',
      ),
    );
    expect(schema, contains('cardinality(restrict_sharing_by) <= 2'));
    // Realtime does not carry generated columns: the flag is kept by the RPC.
    expect(schema, isNot(contains('generated always')));
  });

  test('the only way to change it is the checked function', () {
    expect(
      rpc,
      contains(
        'grant execute on function public.set_chat_restrict_sharing(uuid, boolean)\n  to authenticated;',
      ),
    );
    expect(rpc, contains('security definer'));
    expect(rpc, contains('set search_path = public'));
    expect(rpc, isNot(contains('create policy')));
    expect(schema, isNot(contains('create policy')));
  });

  test(
    'the database refuses forwards, bundles and saves of a restricted chat',
    () {
      for (final trigger in [
        'messages_check_restricted_forward',
        'message_bundles_check_restricted',
        'saved_items_check_restricted',
      ]) {
        expect(enforce, contains('create trigger $trigger'), reason: trigger);
      }
      expect(enforce, contains("'chat_privacy_restricted'"));
    },
  );

  test('the AI gates and the group space are patched in place', () {
    for (final name in [
      'add_album_items_from_messages(uuid, uuid[])',
      'add_folder_files_from_messages(uuid, uuid, uuid[])',
      'conversation_ai_allowed(uuid)',
      'conversation_ai_assistant_allowed(uuid)',
      'list_my_ai_digests()',
    ]) {
      expect(
        enforce,
        contains("pg_get_functiondef('public.$name'::regprocedure)"),
        reason: name,
      );
      expect(
        enforce,
        isNot(
          contains(
            'create or replace function public.${name.split('(').first}',
          ),
        ),
        reason: name,
      );
    }
    // A patch that finds nothing to change stops the migration.
    expect('patch it by hand'.allMatches(enforce).length, 5);
    // The rest of the chat features and push are left alone.
    expect(enforce, isNot(contains('run_later_dispatch')));
    expect(
      enforce,
      isNot(contains('create or replace function public.forward_message')),
    );
  });

  test('screenshot reports are readable by the sender and the reporter only', () {
    expect(
      screenshots,
      contains('alter table public.message_view_once_screenshots'),
    );
    expect(screenshots, contains('enable row level security'));
    expect(
      screenshots,
      contains(
        'revoke all on public.message_view_once_screenshots from anon, authenticated;',
      ),
    );
    expect(
      screenshots,
      contains(
        'grant select on public.message_view_once_screenshots to authenticated;',
      ),
    );
    expect(screenshots, isNot(contains('grant insert')));
    expect(screenshots, isNot(contains('to anon')));
    expect(screenshots, contains('view_once_not_open'));
  });

  test('account deletion and the export helpers cover the new data', () {
    expect(account, contains('deleted_at'));
    expect(account, contains('message_view_once_screenshots'));
    for (final signature in [
      'restricted_conversation_ids(uuid[])',
      'export_my_chat_privacy(uuid)',
    ]) {
      expect(
        account,
        contains('revoke execute on function public.$signature'),
        reason: signature,
      );
      expect(
        account,
        contains('grant execute on function public.$signature'),
        reason: signature,
      );
      expect(account, isNot(contains('$signature\n  to authenticated')));
    }
  });

  test('no migration of the package touches push or the later dispatcher', () {
    for (final sql in [schema, rpc, enforce, screenshots, account]) {
      expect(sql, isNot(contains('run_later_dispatch')));
      expect(sql, isNot(contains('push_')));
    }
  });

  behaviourTest(
    'advanced chat privacy: switching, refusals, AI gates, screenshot reports, export and deletion',
    'test/supabase/chat_privacy_behaviour.sql',
  );
}

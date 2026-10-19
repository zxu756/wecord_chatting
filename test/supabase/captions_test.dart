import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for call captions (E1: migration 202610240100), plus the
/// behaviour script that plays who may turn captions on.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610240100_call_captions_host.sql',
    ).readAsStringSync();
  });

  test('stores nothing and hard-codes no user id', () {
    final uuid = RegExp(
      r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}',
    );
    expect(uuid.hasMatch(sql), isFalse);
    expect(sql, isNot(contains('create table')));
    expect(sql, isNot(contains('insert into')));
    expect(sql, isNot(contains('update public.')));
    expect(sql, isNot(contains('delete from')));
  });

  test('answers only for the signed-in caller, and is closed to anon', () {
    expect(sql, contains('uid uuid := auth.uid();'));
    expect(sql, contains('security definer'));
    expect(sql, contains('set search_path = public'));
    expect(
      sql,
      contains(
        'revoke execute on function public.can_current_user_host_captions(uuid, uuid)\n  from public, anon;',
      ),
    );
    expect(
      sql,
      contains(
        'grant execute on function public.can_current_user_host_captions(uuid, uuid)\n  to authenticated;',
      ),
    );
  });

  test('uses the existing permission and call rules', () {
    expect(sql, contains("'mute_members'"));
    expect(sql, contains('can_current_user_call_in_conversation'));
    expect(sql, contains("('owner', 'admin')"));
  });

  behaviourTest(
    'captions: who may turn them on in channels, one-to-one and group calls',
    'test/supabase/captions_behaviour.sql',
  );
}

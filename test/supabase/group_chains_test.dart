import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'behaviour_runner.dart';

/// Schema checks for group chains, plus the behaviour script.
void main() {
  late String sql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/202610180060_group_chains.sql',
    ).readAsStringSync();
  });

  test('clients can read chains but never write the tables', () {
    for (final table in ['chains', 'chain_entries']) {
      expect(sql, contains('alter table public.$table enable row level'));
      expect(
        sql,
        contains('revoke all on public.$table from anon, authenticated;'),
      );
      expect(sql, contains('grant select on public.$table to authenticated;'));
    }
  });

  test('every change goes through a function for signed-in people', () {
    for (final signature in [
      'create_chain(uuid, text, text, text, timestamptz, integer)',
      'get_chain(uuid)',
      'join_chain(uuid, text)',
      'update_chain_entry(uuid, text)',
      'leave_chain(uuid)',
      'remove_chain_entry(uuid)',
      'set_chain_closed(uuid, boolean)',
    ]) {
      expect(
        sql,
        contains(
          'revoke execute on function public.$signature from public, anon;',
        ),
        reason: signature,
      );
      expect(
        sql,
        contains(
          'grant execute on function public.$signature to authenticated;',
        ),
        reason: signature,
      );
    }
  });

  test('one line per person and chains are live over Realtime', () {
    expect(sql, contains('unique (chain_id, user_id)'));
    expect(
      sql,
      contains('alter publication supabase_realtime add table public.chains'),
    );
  });

  behaviourTest(
    'chains enforce membership, deadline, cap, one line each and the guard',
    'test/supabase/group_chains_behaviour.sql',
  );
}

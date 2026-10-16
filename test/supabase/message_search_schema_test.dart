import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Schema checks for message search (202610160043 … 202610160045). The SQL
/// itself was exercised in rolled-back transactions on seeded data.
void main() {
  String migration(String prefix) {
    final file = Directory('supabase/migrations')
        .listSync()
        .whereType<File>()
        .singleWhere(
          (file) => file.uri.pathSegments.last.startsWith(prefix),
          orElse: () => throw StateError('Missing migration $prefix'),
        );
    return file.readAsStringSync();
  }

  String functionBody(String sql, String name, {bool first = false}) {
    final match = RegExp(
      'create or replace function public\\.$name\\s*\\([\\s\\S]*?\\n\\\$\\\$;',
    ).allMatches(sql);
    expect(match, isNotEmpty, reason: 'Missing function $name');
    return (first ? match.first : match.last).group(0)!;
  }

  test('search entries: one per searchable message, indexed', () {
    final sql = migration('202610160043');
    expect(sql, contains('create extension if not exists pg_trgm'));
    expect(
      sql,
      contains('create table if not exists public.message_search_entries'),
    );
    expect(
      sql,
      contains('references public.messages(id) on delete cascade'),
    );
    expect(
      sql,
      contains(
        'alter table public.message_search_entries enable row level security;',
      ),
    );
    expect(
      sql,
      contains(
        'revoke all on public.message_search_entries from anon, authenticated;',
      ),
    );
    for (final index in [
      'using gin (vector)',
      'using gin (document extensions.gin_trgm_ops)',
      'using gin (kinds)',
      '(conversation_id, created_at desc, message_id desc)',
      '(sender_id, created_at desc)',
      '(created_at desc, message_id desc)',
    ]) {
      expect(sql, contains(index));
    }
    // Kept in step with messages, and filled for what is already there.
    expect(sql, contains('create trigger messages_sync_search_entry'));
    expect(
      sql,
      contains('after insert or update of type, body, attachment, recalled_at'),
    );
    final sync = functionBody(sql, 'sync_message_search_entry');
    expect(sync, contains("new.recalled_at is not null or new.type = 'system'"));
    expect(sync, contains('on conflict (message_id) do update'));
    expect(sql, contains('insert into public.message_search_entries ('));
    // CJK characters become words of their own for phrase search.
    expect(functionBody(sql, 'search_split_cjk'), contains(r'\x4E00-\x9FFF'));
    for (final name in [
      'search_split_cjk',
      'message_search_document',
      'message_search_vector',
      'message_search_kinds',
      'search_like_pattern',
    ]) {
      expect(functionBody(sql, name), contains('immutable'));
    }
    expect(sql, contains('drop index if exists public.messages_body_search_idx'));
  });

  test('search_messages only reads what the caller can read', () {
    final sql = migration('202610160044');
    final scope = functionBody(sql, 'search_scope_conversation_ids');
    expect(scope, contains('security definer'));
    expect(
      scope,
      contains('from public.current_user_readable_conversation_ids()'),
    );
    final search = functionBody(sql, 'search_messages', first: true);
    expect(search, contains('security definer'));
    expect(search, contains('set search_path = public'));
    expect(search, contains('public.search_scope_conversation_ids(scope)'));
    expect(search, contains("' where e.conversation_id = any(\$1)%s'"));
    expect(search, contains("raise exception 'Sign in to search messages'"));
    // Filters are built from %L literals or parameters, never raw text.
    expect(search, isNot(contains('|| query')));
    expect(search, contains("'%s like %L'"));
    expect(search, contains("'%s @@ %L::tsquery'"));
    expect(search, contains('limit 1001'));
    for (final grant in [
      'grant execute on function public.search_messages(text, jsonb, jsonb, text, integer, jsonb) to authenticated;',
      'grant execute on function public.search_message_context(uuid, integer, integer) to authenticated;',
      'revoke execute on function public.search_messages(text, jsonb, jsonb, text, integer, jsonb) from anon;',
      'revoke execute on function public.search_message_json(public.messages, real, uuid) from authenticated;',
    ]) {
      expect(sql, contains(grant));
    }
    final context = functionBody(sql, 'search_message_context');
    expect(
      context,
      contains('select public.current_user_readable_conversation_ids()'),
    );
  });

  test('filter suggestions stay inside the readable scope', () {
    final sql = migration('202610160045');
    final suggestions = functionBody(sql, 'search_filter_suggestions');
    expect(suggestions, contains('security definer'));
    expect(
      suggestions,
      contains('public.search_scope_conversation_ids(scope)'),
    );
    expect(suggestions, contains('cm.conversation_id = any(conversation_ids)'));
    expect(suggestions, contains('c.id = any(conversation_ids)'));
    expect(
      sql,
      contains(
        'revoke execute on function public.search_filter_suggestions(text, text, jsonb, integer) from anon;',
      ),
    );
  });
}
